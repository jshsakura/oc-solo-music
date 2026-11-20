"""내가 만든 수노 곡을 녹음하거나 가진 곡 파일을 올려 쌓고, 폰에서 화면을 꺼도 재생되게 내려주는 서버."""

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
from urllib.parse import urlencode

from fastapi import FastAPI, HTTPException, Request

from fastapi.responses import FileResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import auth, library, messages, suno_record, upload
from .messages import msg
from .serving import ranged_file

LIB = Path(os.environ.get("SOLO_LIB", Path.home() / "app" / "suno-music"))
# 화면은 Flutter 웹 빌드입니다. 이미지에서는 /app/web, 개발 중에는 client/build/web 을 씁니다.
WEB = Path(os.environ.get("SOLO_WEB", Path(__file__).resolve().parent.parent / "client" / "build" / "web"))
# 안드로이드 앱입니다. CI 가 빌드한 solo.apk 와 version.txt 를 이미지의 /app/apk 에 넣습니다.
APK_DIR = Path(os.environ.get("SOLO_APK_DIR", Path(__file__).resolve().parent.parent / "apk"))
# 비워 두면 인증 없이 엽니다(LAN 이나 Cloudflare Access 같은 앞단 인증 뒤에 둘 때).
PASSWORD = os.environ.get("SOLO_PASSWORD", "")
# Cloudflare Access(구글 로그인)를 앞에 세울 때 씁니다. 팀 도메인(xxx.cloudflareaccess.com)과 애플리케이션 AUD 태그입니다.
ACCESS = (auth.AccessVerifier(os.environ["SOLO_ACCESS_TEAM"], os.environ["SOLO_ACCESS_AUD"])
          if os.environ.get("SOLO_ACCESS_TEAM") and os.environ.get("SOLO_ACCESS_AUD") else None)
# QR 에 담을 서버 주소입니다. 비우면 요청이 들어온 주소를 씁니다.
PUBLIC_URL = os.environ.get("SOLO_PUBLIC_URL", "").rstrip("/")

UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
SUNO_URL = re.compile(rf"https://(www\.)?suno\.com/(song/{UUID}|hook/{UUID}|s/[A-Za-z0-9]+)/?")
RESULT_LINE = re.compile(r"^\[(\w+)\] (.+?): (.*)$")
PROGRESS_LINE = re.compile(r"^\[progress\] (\d+(?:\.\d+)?)$")
MAX_JOBS_KEPT = 30

ACTIVE = ("queued", "recording")
UPLOAD_MAX = 300 * 1024 * 1024  # 올리는 파일 하나의 상한입니다

jobs: list[dict] = []
# 수노 녹음은 곡 길이만큼 걸려서 한 곡씩 차례로 처리합니다.
queues: dict[str, asyncio.Queue[dict]] = {}
running: dict[str, asyncio.subprocess.Process] = {}  # 진행 중인 작업 id → 녹음기 프로세스


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
    return ["app.suno_record", job["url"], "-o", str(LIB), "--codes"]


async def record(job: dict) -> None:
    """녹음기를 따로 띄웁니다. 곡 정보와 표지는 그쪽이 solo.db 와 폴더에 직접 남깁니다.
    새 프로세스 그룹으로 띄워서, 취소할 때 녹음기가 띄운 크롬까지 한꺼번에 끕니다."""
    persist(job, status="recording", progress=0.0)
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
        except Exception as error:
            persist(job, status="failed", detail=f"{type(error).__name__}: {error}"[:300])
        finally:
            queue.task_done()


def persist(job: dict, **changes) -> None:
    job.update(changes)
    library.save_job(LIB, job, MAX_JOBS_KEPT)
    if job["status"] not in ACTIVE:  # 다 끝난 곡은 보관함에 제 표지가 생기므로 미리 받은 표지를 치웁니다
        job_cover(job["id"]).unlink(missing_ok=True)


def job_cover(job_id: str) -> Path:
    return LIB / f".job-{job_id}.jpg"  # 점으로 시작해 목록 동기화가 건너뜁니다


peeks: set[asyncio.Task] = set()


async def peek(job: dict) -> None:
    """대기열에 넣자마자 제목과 표지를 받아 데크의 테이프에 붙입니다. 실패해도 녹음은 그대로 합니다."""
    try:
        info = await asyncio.to_thread(suno_record.peek_clip, job["url"], job_cover(job["id"]))
    except Exception:
        return
    if job["status"] in ACTIVE:
        extra = {"duration": info["duration"]} if info.get("duration") else {}
        persist(job, title=job["title"] or info["title"], cover=info["cover"], **extra)


def enqueue(kind: str, key: str, title: str = "", **extra) -> bool:
    """같은 곡이 이미 대기 중이거나 진행 중이면 넣지 않습니다."""
    if any(j["key"] == key and j["status"] in ACTIVE for j in jobs):
        return False
    job = {"id": secrets.token_hex(6), "kind": kind, "key": key, "url": extra.pop("url", ""),
           "status": "queued", "detail": "", "title": title, **extra}
    jobs.append(job)
    persist(job)
    queues[kind].put_nowait(job)
    if kind == "suno":
        task = asyncio.get_running_loop().create_task(peek(job))
        peeks.add(task)
        task.add_done_callback(peeks.discard)
    del jobs[:-MAX_JOBS_KEPT]
    return True


def restore_jobs() -> None:
    """지난 기록을 불러오고, 끝내지 못한 작업은 처음부터 다시 대기열에 넣습니다. 녹음은 이어 붙일 수 없어서입니다."""
    # 예전 버전이 남긴 유튜브 받기 기록은 더 다루지 않으므로 불러오지 않습니다.
    jobs[:] = [j for j in library.load_jobs(LIB) if j.get("kind") in queues][-MAX_JOBS_KEPT:]
    for job in jobs:
        if job["status"] in ACTIVE:
            persist(job, status="queued", progress=0.0)
            queues[job["kind"]].put_nowait(job)


@asynccontextmanager
async def lifespan(_: FastAPI):
    LIB.mkdir(parents=True, exist_ok=True)
    queues.update(suno=asyncio.Queue())
    restore_jobs()
    tasks = [asyncio.create_task(worker(kind)) for kind in queues]
    yield
    # 서버가 꺼질 때 녹음기도 함께 끕니다. 남겨 두면 다음에 켜질 때 같은 곡을 한 번 더 받습니다.
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
    """내가 만든 수노 곡 주소를 녹음 대기열에 넣습니다."""
    urls = list(dict.fromkeys(u.strip() for u in body.urls if u.strip()))
    bad = [u for u in urls if not SUNO_URL.fullmatch(u)]
    if bad or not urls:
        raise SoloError(400, "add.bad_url", url=bad[0] if bad else "")
    return {"queued": sum(enqueue("suno", url, url=url) for url in urls)}


@app.put("/api/upload")
async def api_upload(request: Request, name: str) -> dict:
    """내가 만들었거나 산 곡 파일 하나를 몸통 그대로 받아 보관함에 넣습니다. 같은 파일은 한 번만 들어갑니다."""
    suffix = Path(name).suffix.lower()
    if suffix not in upload.TYPES:
        raise SoloError(400, "upload.bad_type", name=Path(name).name[:100])
    tmp = LIB / f".upload-{secrets.token_hex(6)}{suffix}"
    digest, size = hashlib.sha256(), 0
    try:
        with tmp.open("wb") as out:
            async for chunk in request.stream():
                size += len(chunk)
                if size > UPLOAD_MAX:
                    raise SoloError(413, "upload.too_big", mb=UPLOAD_MAX // 1024 // 1024)
                digest.update(chunk)
                out.write(chunk)
        if size == 0:
            raise SoloError(400, "upload.not_audio")
        track_id = "up-" + digest.hexdigest()[:16]
        if library.find_audio(LIB, track_id):
            return {"id": track_id, "added": False}
        try:
            await asyncio.to_thread(upload.add_file, LIB, tmp, track_id, Path(name).stem)
        except upload.Rejected as error:
            raise SoloError(400, error.code)
    finally:
        tmp.unlink(missing_ok=True)
    return {"id": track_id, "added": True}


def stop_recorder(process: asyncio.subprocess.Process, job: dict | None) -> None:
    """녹음기와 녹음기가 띄운 크롬을 함께 끄고, 녹음이 남긴 임시 폴더를 치웁니다.
    녹음은 한 번에 하나씩만 돌므로 남은 임시 폴더는 지금 끈 작업의 것입니다."""
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    if job is None:
        return
    for leftover in LIB.glob(".recording-*"):
        shutil.rmtree(leftover, ignore_errors=True)


@app.post("/api/jobs/{job_id}/cancel")
async def api_cancel(job_id: str) -> dict:
    """대기 중이면 대기열에서 빼고, 녹음 중이면 녹음을 멈춥니다. 녹음하던 파일은 남기지 않습니다."""
    job = next((j for j in jobs if j["id"] == job_id), None)
    if job is None:
        raise SoloError(404, "job.not_found")
    if job["status"] not in ACTIVE:
        raise SoloError(409, "job.already_finished")
    stopped = msg("job.stopped_recording" if job["status"] == "recording" else "job.dequeued")
    persist(job, status="canceled", detail=stopped)
    process = running.get(job_id)
    if process is not None:
        stop_recorder(process, job)
    return {"canceled": job_id}


@app.get("/api/jobs/{job_id}/cover")
def api_job_cover(job_id: str):
    cover = job_cover(job_id) if re.fullmatch(r"[0-9a-f]{12}", job_id) else None
    if cover is None or not cover.exists():
        raise SoloError(404, "track.not_found")
    return FileResponse(cover, headers={"Cache-Control": "private, max-age=3600"})


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


# 인증 없이 열어 두는 길입니다. 짝짓기 코드 교환은 코드 자체가 열쇠입니다.
OPEN_PATHS = {"/healthz", "/api/pair/claim"}


@app.middleware("http")
async def require_login(request: Request, call_next):
    """/api 는 늘 확인합니다. 화면 파일은 Access 를 쓸 때 Access 가 지키고, 비밀번호만 쓸 때는 여기서 지킵니다."""
    path = request.url.path
    guarded = path.startswith("/api/") or (PASSWORD and ACCESS is None)
    if path in OPEN_PATHS or not guarded:
        return await call_next(request)
    who = auth.identify(
        lib=LIB,
        authorization=request.headers.get("authorization", ""),
        access_token=request.headers.get("cf-access-jwt-assertion") or request.cookies.get("CF_Authorization", ""),
        password=PASSWORD,
        access=ACCESS,
    )
    if who is None:
        headers = {"WWW-Authenticate": 'Basic realm="Solo", charset="UTF-8"'} if PASSWORD and ACCESS is None else {}
        return JSONResponse({"detail": messages.render(msg("auth.required"), language(request)), "code": "auth.required"},
                            status_code=401, headers=headers)
    request.state.who = who
    return await call_next(request)


def owner_only(request: Request) -> auth.Who:
    who = getattr(request.state, "who", None)
    if who is None or not who.owner:
        raise SoloError(403, "auth.owner_only")
    return who


def public_origin(request: Request) -> str:
    if PUBLIC_URL:
        return PUBLIC_URL
    proto = request.headers.get("x-forwarded-proto", request.url.scheme)
    proto = proto if proto in ("http", "https") else "https"
    return f"{proto}://{request.headers.get('host', request.url.netloc)}"


@app.get("/api/me")
def api_me(request: Request):
    who: auth.Who = request.state.who
    return {"via": who.via, "owner": who.owner, "email": who.email, "device": who.device_id}


@app.post("/api/pair")
def api_pair(request: Request):
    """웹이 QR 로 띄울 짝짓기 주소를 만듭니다. 앱이 찍으면 /api/pair/claim 으로 기기 토큰을 받습니다."""
    owner_only(request)
    code, expires = auth.new_pair_code(LIB)
    server = public_origin(request)
    return {"server": server, "code": code, "expires": expires,
            "uri": "solo://pair?" + urlencode({"server": server, "code": code})}


class Claim(BaseModel):
    code: str
    name: str = ""
    platform: str = ""


@app.post("/api/pair/claim")
def api_pair_claim(body: Claim):
    device = auth.claim_pair_code(LIB, body.code, body.name, body.platform)
    if device is None:
        raise SoloError(400, "pair.invalid")
    return device


@app.get("/api/devices")
def api_devices(request: Request):
    owner_only(request)
    return auth.list_devices(LIB)


@app.delete("/api/devices/{device_id}")
def api_device_remove(device_id: str, request: Request):
    owner_only(request)
    if not auth.remove_device(LIB, device_id):
        raise SoloError(404, "device.not_found")
    return {"removed": device_id}


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


def apk_info() -> dict | None:
    apk = APK_DIR / "solo.apk"
    if not apk.is_file():
        return None
    version_file = APK_DIR / "version.txt"
    version = version_file.read_text().strip() if version_file.is_file() else ""
    return {"version": version, "size": apk.stat().st_size, "url": "/solo.apk"}


@app.get("/api/app")
def api_app():
    """웹 화면이 앱 받기 버튼을 띄울지 정할 때 씁니다."""
    return {"android": apk_info()}


@app.get("/solo.apk", include_in_schema=False)
def solo_apk():
    if apk_info() is None:
        raise SoloError(404, "app.no_apk")
    return FileResponse(APK_DIR / "solo.apk", filename="Solo.apk",
                        media_type="application/vnd.android.package-archive")


@app.get("/", include_in_schema=False)
def index(request: Request) -> Response:
    """링크 미리보기는 절대 주소를 요구하므로, 요청이 들어온 주소를 OG 이미지 경로에 넣습니다."""
    proto = request.headers.get("x-forwarded-proto", request.url.scheme)
    proto = proto if proto in ("http", "https") else "https"
    origin = html.escape(f"{proto}://{request.headers.get('host', request.url.netloc)}", quote=True)
    page = (WEB / "index.html").read_text().replace("__SOLO_ORIGIN__", origin)
    return Response(page, media_type="text/html; charset=utf-8")


if WEB.is_dir():
    app.mount("/", StaticFiles(directory=WEB, html=True), name="web")
