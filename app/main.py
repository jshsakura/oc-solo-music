"""수노 곡을 녹음해 쌓고, 폰에서 화면을 꺼도 재생되게 내려주는 서버."""

from __future__ import annotations

import asyncio
import hashlib
import html
import json
import os
import re
import secrets
import shutil
import signal
import sqlite3
import sys
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
import base64

from fastapi.responses import FileResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import library, messages, youtube
from .messages import msg
from .serving import ranged_file

LIB = Path(os.environ.get("SOLO_LIB", Path.home() / "app" / "suno-music"))
# 화면은 Flutter 웹 빌드입니다. 이미지에서는 /app/web, 개발 중에는 client/build/web 을 씁니다.
WEB = Path(os.environ.get("SOLO_WEB", Path(__file__).resolve().parent.parent / "client" / "build" / "web"))
# 비워 두면 인증 없이 엽니다(LAN 이나 Cloudflare Access 같은 앞단 인증 뒤에 둘 때).
PASSWORD = os.environ.get("SOLO_PASSWORD", "")

UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
SUNO_URL = re.compile(rf"https://(www\.)?suno\.com/(song/{UUID}|s/[A-Za-z0-9]+)/?")
RESULT_LINE = re.compile(r"^\[(\w+)\] (.+?): (.*)$")
PROGRESS_LINE = re.compile(r"^\[progress\] (\d+(?:\.\d+)?)$")
MAX_JOBS_KEPT = 30

YOUTUBE_GAP_SECONDS = 3  # 유튜브에 연달아 요청하지 않도록 곡 사이에 쉽니다
ACTIVE = ("queued", "recording", "downloading")

jobs: list[dict] = []
# 수노 녹음은 곡 길이만큼 걸리므로 유튜브 받기와 대기열을 나눕니다. 각자 한 곡씩 처리합니다.
queues: dict[str, asyncio.Queue[dict]] = {}
running: dict[str, asyncio.subprocess.Process] = {}  # 진행 중인 작업 id → 녹음기나 다운로더 프로세스


def track_json(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"], "title": row["title"], "artist": row["artist"], "tags": row["tags"],
        "duration": row["duration"], "cover": (LIB / f"{row['id']}.jpg").exists(),
        "liked": bool(row["liked"]), "added": row["added"], "source": row["source"],
    }


def list_tracks() -> list[dict]:
    library.sync(LIB)
    with library.connect(LIB) as db:
        return [track_json(r) for r in db.execute("SELECT * FROM tracks WHERE archived=0 ORDER BY added DESC, id")]


def list_archived() -> list[dict]:
    library.sync(LIB)
    with library.connect(LIB) as db:
        rows = db.execute("SELECT * FROM tracks WHERE archived=1 ORDER BY title")
        return [{**track_json(r), "cover": False} for r in rows]


def find_track_file(track_id: str) -> Path:
    audio = library.find_audio(LIB, track_id)
    if audio is None:
        raise SoloError(404, "track.not_found")
    return audio


def job_command(job: dict) -> list[str]:
    if job["kind"] == "youtube":
        return ["app.youtube_get", json.dumps(job["track"], ensure_ascii=False), "-o", str(LIB)]
    return ["app.suno_record", job["url"], "-o", str(LIB), "--codes"]


async def record(job: dict) -> None:
    """녹음기나 다운로더를 따로 띄웁니다. 곡 정보와 표지는 그쪽이 solo.db 와 폴더에 직접 남깁니다.
    새 프로세스 그룹으로 띄워서, 취소할 때 녹음기가 띄운 크롬까지 한꺼번에 끕니다."""
    persist(job, status="downloading" if job["kind"] == "youtube" else "recording", progress=0.0)
    process = await asyncio.create_subprocess_exec(
        sys.executable, "-m", *job_command(job),
        stdin=asyncio.subprocess.DEVNULL, cwd=Path(__file__).parent.parent,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT, start_new_session=True)
    running[job["id"]] = process
    lines: list[str] = []
    try:
        async for raw in process.stdout:  # 진행률 줄은 오는 대로 반영하고 나머지는 결과를 찾으려고 모아 둡니다
            line = raw.decode(errors="replace").rstrip()
            if progress := PROGRESS_LINE.match(line):
                job["progress"] = round(min(float(progress.group(1)), 1.0), 3)
            else:
                lines.append(line)
        await process.wait()
    finally:
        running.pop(job["id"], None)
    if job["status"] == "canceled":
        return
    match = next((m for m in map(RESULT_LINE.match, lines) if m), None)
    if process.returncode == 0 and match:
        status, name, detail = match.groups()
        persist(job, status="done", detail=messages.from_wire(detail), title=job["title"] or name, progress=1.0)
    else:
        persist(job, status="failed", detail=messages.from_wire(match.group(3)) if match else "\n".join(lines[-3:])[:300])


async def worker(kind: str) -> None:
    queue = queues[kind]
    while True:
        job = await queue.get()
        try:
            if job["status"] == "canceled":
                continue
            await record(job)
            if kind == "youtube":
                await asyncio.sleep(YOUTUBE_GAP_SECONDS)
        except Exception as error:
            persist(job, status="failed", detail=f"{type(error).__name__}: {error}"[:300])
        finally:
            queue.task_done()


def persist(job: dict, **changes) -> None:
    job.update(changes)
    library.save_job(LIB, job, MAX_JOBS_KEPT)


def enqueue(kind: str, key: str, title: str = "", **extra) -> bool:
    """같은 곡이 이미 대기 중이거나 진행 중이면 넣지 않습니다."""
    if any(j["key"] == key and j["status"] in ACTIVE for j in jobs):
        return False
    job = {"id": secrets.token_hex(6), "kind": kind, "key": key, "url": extra.pop("url", ""),
           "status": "queued", "detail": "", "title": title, **extra}
    jobs.append(job)
    persist(job)
    queues[kind].put_nowait(job)
    del jobs[:-MAX_JOBS_KEPT]
    return True


def restore_jobs() -> None:
    """지난 기록을 불러오고, 끝내지 못한 작업은 처음부터 다시 대기열에 넣습니다. 녹음은 이어 붙일 수 없어서입니다."""
    jobs[:] = library.load_jobs(LIB)[-MAX_JOBS_KEPT:]
    for job in jobs:
        if job["status"] in ACTIVE and job["kind"] in queues:
            persist(job, status="queued", progress=0.0)
            queues[job["kind"]].put_nowait(job)


@asynccontextmanager
async def lifespan(_: FastAPI):
    LIB.mkdir(parents=True, exist_ok=True)
    queues.update(suno=asyncio.Queue(), youtube=asyncio.Queue())
    restore_jobs()
    tasks = [asyncio.create_task(worker(kind)) for kind in queues]
    yield
    # 서버가 꺼질 때 녹음기와 다운로더도 함께 끕니다. 남겨 두면 다음에 켜질 때 같은 곡을 한 번 더 받습니다.
    for job_id, process in list(running.items()):
        stop_recorder(process, next((j for j in jobs if j["id"] == job_id), None))
    for task in tasks:
        task.cancel()


app = FastAPI(lifespan=lifespan)


class SoloError(Exception):
    """화면에 나갈 실패입니다. 응답할 때 요청한 언어로 바꿉니다."""

    def __init__(self, status: int, code: str, **args) -> None:
        super().__init__(code)
        self.status = status
        self.message = msg(code, **args)


def language(request: Request) -> str:
    return messages.pick_language(request.query_params.get("lang"), request.headers.get("accept-language"))


@app.exception_handler(SoloError)
async def solo_error(request: Request, error: SoloError) -> JSONResponse:
    return JSONResponse({"detail": messages.render(error.message, language(request)), "code": error.message["code"]},
                        status_code=error.status)


class AddRequest(BaseModel):
    urls: list[str]


@app.get("/api/tracks")
def api_tracks(request: Request) -> Response:
    """목록이 그대로면 304 만 돌려줍니다. 폰 회선에서 매번 전체를 받지 않게 합니다."""
    body = json.dumps(list_tracks(), ensure_ascii=False, separators=(",", ":")).encode()
    etag = '"' + hashlib.sha1(body).hexdigest()[:16] + '"'
    headers = {"ETag": etag, "Cache-Control": "no-cache"}
    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers=headers)
    return Response(body, media_type="application/json", headers=headers)


@app.get("/api/audio/{track_id}")
def api_audio(track_id: str, request: Request):
    audio = find_track_file(track_id)
    return ranged_file(audio, request, "audio/mp4" if audio.suffix == ".m4a" else "audio/mpeg")


_UNSAFE_NAME = re.compile(r'[\\/:*?"<>|\x00-\x1f]+')


@app.get("/api/download/{track_id}")
def api_download(track_id: str):
    """곡 파일을 기기에 저장합니다. 파일 이름은 "아티스트 - 제목" 입니다."""
    audio = find_track_file(track_id)
    with library.connect(LIB) as db:
        row = db.execute("SELECT title, artist FROM tracks WHERE id=?", (track_id,)).fetchone()
    title, artist = (row["title"], row["artist"]) if row else (track_id, "")
    name = " ".join(_UNSAFE_NAME.sub(" ", f"{artist} - {title}" if artist else title).split())[:150] or track_id
    return FileResponse(audio, filename=name + audio.suffix,
                        media_type="audio/mp4" if audio.suffix == ".m4a" else "audio/mpeg")


@app.get("/api/cover/{track_id}")
def api_cover(track_id: str):
    cover = find_track_file(track_id).with_suffix(".jpg")
    if not cover.exists():
        raise HTTPException(404)
    return FileResponse(cover, headers={"Cache-Control": "private, max-age=604800"})


@app.post("/api/add")
async def api_add(body: AddRequest) -> dict:
    """수노 주소는 녹음하고, 유튜브 주소는 곡 목록으로 펴서 받습니다."""
    urls = list(dict.fromkeys(u.strip() for u in body.urls if u.strip()))
    bad = [u for u in urls if not (SUNO_URL.fullmatch(u) or youtube.YOUTUBE_URL.fullmatch(u))]
    if bad or not urls:
        raise SoloError(400, "add.bad_url", url=bad[0] if bad else "")
    queued = 0
    for url in urls:
        if SUNO_URL.fullmatch(url):
            queued += enqueue("suno", url, url=url)
            continue
        try:
            tracks = await asyncio.to_thread(youtube.resolve, url, youtube.cookies_path(LIB))
        except Exception as error:
            raise SoloError(502, "add.youtube_unreadable", reason=str(error)[:200])
        if not tracks:
            raise SoloError(404, "add.nothing_found")
        queued += sum(add_youtube(t) for t in tracks)
    return {"queued": queued}


def add_youtube(track: dict) -> bool:
    if library.find_audio(LIB, youtube.track_id(track["videoId"])):
        return False  # 이미 받은 곡
    return enqueue("youtube", track["videoId"], track["title"], track=track,
                   url=f"https://www.youtube.com/watch?v={track['videoId']}")


class YoutubeTrack(BaseModel):
    videoId: str
    title: str
    artist: str = ""
    album: str = ""
    duration: int | None = None
    art: str = ""


@app.get("/api/search")
async def api_search(q: str) -> dict:
    """유튜브에서 곡을 찾습니다. 이미 받은 곡에는 owned 를 붙입니다."""
    q = q.strip()
    if not q:
        return {"music": False, "tracks": []}
    try:
        found = await asyncio.to_thread(youtube.search, q[:200], youtube.cookies_path(LIB))
    except Exception as error:
        raise SoloError(502, "search.failed", reason=str(error)[:200])
    for t in found["tracks"]:
        t["owned"] = library.find_audio(LIB, youtube.track_id(t["videoId"])) is not None
    return found


@app.post("/api/youtube/get")
async def api_youtube_get(track: YoutubeTrack) -> dict:
    if not youtube.VIDEO_ID.fullmatch(track.videoId):
        raise SoloError(400, "youtube.bad_id")
    return {"queued": int(add_youtube(track.model_dump()))}


@app.get("/api/youtube/status")
def api_youtube_status() -> dict:
    jar = youtube.read_cookies(youtube.cookies_path(LIB))
    return {"cookies": bool(jar), "loggedIn": youtube.is_logged_in(jar)}


@app.put("/api/youtube/cookies")
async def api_youtube_cookies(request: Request) -> dict:
    """서브 계정에서 내보낸 cookies.txt 를 받습니다. 유튜브와 구글 쿠키만 남기고 나머지는 버립니다."""
    body = (await request.body())[:1_000_000].decode(errors="replace")
    path = youtube.cookies_path(LIB)
    tmp = path.with_suffix(".tmp")
    path.parent.mkdir(parents=True, exist_ok=True)
    kept = [line for line in body.splitlines()
            if line.removeprefix("#HttpOnly_").split("\t", 1)[0].lstrip(".").endswith(youtube.COOKIE_DOMAINS)
            and len(line.split("\t")) >= 7]
    path.parent.chmod(0o700)
    tmp.touch(mode=0o600)  # 계정 쿠키라 처음부터 나만 읽게 만듭니다
    tmp.write_text("# Netscape HTTP Cookie File\n" + "\n".join(kept) + "\n")
    if not youtube.is_logged_in(youtube.read_cookies(tmp)):
        tmp.unlink()
        raise SoloError(400, "youtube.no_login_cookie")
    tmp.replace(path)
    return api_youtube_status()


@app.delete("/api/youtube/cookies")
def api_youtube_logout() -> dict:
    youtube.cookies_path(LIB).unlink(missing_ok=True)
    return api_youtube_status()


def stop_recorder(process: asyncio.subprocess.Process, job: dict | None) -> None:
    """녹음기와 녹음기가 띄운 크롬을 함께 끄고, 그 작업이 남긴 임시 폴더만 치웁니다.
    수노와 유튜브는 각자 한 번에 하나씩만 돌므로 종류별 임시 폴더는 지금 끈 작업의 것입니다."""
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    if job is None:
        return
    leftovers = [LIB / f".yt-{job['key']}"] if job["kind"] == "youtube" else list(LIB.glob(".recording-*"))
    for leftover in leftovers:
        shutil.rmtree(leftover, ignore_errors=True)


@app.post("/api/jobs/{job_id}/cancel")
async def api_cancel(job_id: str) -> dict:
    """대기 중이면 대기열에서 빼고, 녹음 중이면 녹음을 멈춥니다. 녹음하던 파일은 남기지 않습니다."""
    job = next((j for j in jobs if j["id"] == job_id), None)
    if job is None:
        raise SoloError(404, "job.not_found")
    if job["status"] not in ACTIVE:
        raise SoloError(409, "job.already_finished")
    stopped = msg({"recording": "job.stopped_recording", "downloading": "job.stopped_downloading"}.get(job["status"], "job.dequeued"))
    persist(job, status="canceled", detail=stopped)
    process = running.get(job_id)
    if process is not None:
        stop_recorder(process, job)
    return {"canceled": job_id}


@app.get("/api/jobs")
def api_jobs(request: Request) -> list[dict]:
    lang = language(request)
    return [{**j, "detail": messages.render(j.get("detail"), lang)} for j in reversed(jobs)]


@app.post("/api/like/{track_id}")
def api_like(track_id: str) -> dict:
    find_track_file(track_id)
    with library.connect(LIB) as db:
        db.execute("UPDATE tracks SET liked = 1 - liked WHERE id=?", (track_id,))
        row = db.execute("SELECT liked FROM tracks WHERE id=?", (track_id,)).fetchone()
    if row is None:
        raise SoloError(404, "track.not_found")
    return {"liked": bool(row["liked"])}


@app.delete("/api/tracks/{track_id}")
def api_delete(track_id: str) -> dict:
    """앱 목록에서만 뺍니다. 파일은 지우지 않고 archive/ 폴더로 옮겨 호스트에 남깁니다."""
    find_track_file(track_id)
    library.archive(LIB, track_id)
    return {"archived": track_id}


@app.get("/api/archive")
def api_archive() -> list[dict]:
    return list_archived()


@app.post("/api/archive/{track_id}/restore")
def api_restore(track_id: str) -> dict:
    if library.find_audio(LIB / library.ARCHIVE, track_id) is None:
        raise SoloError(404, "archive.not_found")
    library.restore(LIB, track_id)
    return {"restored": track_id}


def authorized(header: str) -> bool:
    scheme, _, value = header.partition(" ")
    if scheme.lower() != "basic":
        return False
    try:
        _, _, given = base64.b64decode(value).decode().partition(":")
    except (ValueError, UnicodeDecodeError):
        return False
    return secrets.compare_digest(given.encode(), PASSWORD.encode())


@app.middleware("http")
async def require_password(request: Request, call_next):
    """SOLO_PASSWORD 가 있으면 모든 요청에 HTTP Basic 인증을 겁니다. 사용자 이름은 보지 않습니다."""
    if PASSWORD and request.url.path != "/healthz" and not authorized(request.headers.get("authorization", "")):
        return Response(messages.render(msg("auth.required"), language(request)), status_code=401, headers={"WWW-Authenticate": 'Basic realm="Solo", charset="UTF-8"'})
    return await call_next(request)


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True}


@app.middleware("http")
async def no_stale_shell(request: Request, call_next):
    """화면 파일은 매번 재검증한다. 옛 CSS/JS 와 새 HTML 이 섞이면 화면이 깨진다."""
    resp = await call_next(request)
    if not request.url.path.startswith("/api/"):
        resp.headers["Cache-Control"] = "no-cache"
    return resp


@app.get("/", include_in_schema=False)
def index(request: Request) -> Response:
    """링크 미리보기는 절대 주소를 요구하므로, 요청이 들어온 주소를 OG 이미지 경로에 넣습니다."""
    proto = request.headers.get("x-forwarded-proto", request.url.scheme)
    proto = proto if proto in ("http", "https") else "https"
    origin = html.escape(f"{proto}://{request.headers.get('host', request.url.netloc)}", quote=True)
    page = (WEB / "index.html").read_text().replace("{{origin}}", origin)
    return Response(page, media_type="text/html; charset=utf-8")


if WEB.is_dir():
    app.mount("/", StaticFiles(directory=WEB, html=True), name="web")
