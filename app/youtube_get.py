"""유튜브 곡 하나를 mp3 로 받아 라이브러리에 넣습니다. 서버가 별도 프로세스로 띄워서 정지할 수 있게 합니다.

    python -m app.youtube_get '<곡 JSON>' -o <라이브러리 폴더>

곡 JSON 은 app.youtube 가 만든 {videoId, title, artist, album, duration, art} 입니다.
끝나면 서버가 읽는 결과 한 줄을 찍습니다: "[ok] 영상 ID: 아티스트" 또는 "[failed] 영상 ID: 이유".
제목에는 ":" 가 흔해서 줄 앞에는 영상 ID 를 둡니다.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
from urllib.parse import urlparse
from pathlib import Path

from . import library
from .messages import msg, to_wire
from .youtube import UA, VIDEO_ID, cookies_path, track_id

# 140 = m4a(AAC 128k). 받기가 가장 안정적인 형식이라 먼저 고르고, 수노 곡과 같은 mp3 로 바꿔 둡니다.
FORMAT = "140/bestaudio[acodec^=mp4a]/bestaudio[ext=m4a]/bestaudio"
# 2026-08 실측으로 받아지는 조합입니다. 서명 풀이 스크립트(ejs), 이 두 클라이언트, PO Token 공급자가 모두 있어야 합니다.
PLAYER_CLIENTS = ["tv_simply", "web_embedded"]
# 원본이 AAC 128k 라 mp3 로 옮기면서 깎이는 것을 줄이려고 192k 로 넉넉히 씁니다.
MP3_QUALITY = "192"


def make_progress_hook():
    """받는 동안은 0~90%, mp3 로 바꾸는 동안은 95% 로 알립니다. 1% 넘게 움직일 때만 찍습니다."""
    last: list[float] = []

    def hook(state: dict) -> None:
        fraction = progress_of(state)
        if fraction is not None and (not last or fraction != last[-1]):
            last.append(fraction)
            library.report_progress(fraction)
    return hook


def progress_of(state: dict) -> float | None:
    total = state.get("total_bytes") or state.get("total_bytes_estimate")
    if state.get("status") == "downloading" and total:
        return round(state.get("downloaded_bytes", 0) / total * 0.9, 2)
    if state.get("status") == "finished":
        return 0.95
    return None


def download(video_id: str, workdir: Path, cookies: Path) -> Path:
    from yt_dlp import YoutubeDL

    opts = {
        "format": FORMAT, "outtmpl": str(workdir / "%(id)s.%(ext)s"), "quiet": True, "no_warnings": True,
        "noplaylist": True, "retries": 3, "fragment_retries": 3, "concurrent_fragment_downloads": 1,
        "noprogress": True, "remote_components": ["ejs:github"], "progress_hooks": [make_progress_hook()],
        "extractor_args": {"youtube": {"player_client": PLAYER_CLIENTS}},
        "postprocessors": [{"key": "FFmpegExtractAudio", "preferredcodec": "mp3", "preferredquality": MP3_QUALITY}],
    }
    if pot := os.environ.get("SOLO_POT_BASE_URL", "").strip():
        opts["extractor_args"]["youtubepot-bgutilhttp"] = {"base_url": [pot]}
    if cookies.is_file():
        opts["cookiefile"] = str(cookies)
    with YoutubeDL(opts) as ydl:
        ydl.download([f"https://www.youtube.com/watch?v={video_id}"])
    files = [p for p in workdir.glob("*.mp3") if p.stat().st_size > 0]
    if not files:
        raise NoAudio("no mp3 after download")
    return files[0]


COVER_HOSTS = ("ytimg.com", "googleusercontent.com", "ggpht.com")
MAX_COVER_BYTES = 5 * 1024 * 1024


def save_cover(url: str, target: Path) -> None:
    """유튜브 뮤직 표지는 주소에 크기가 박혀 있어 키워 받습니다. 영상 썸네일은 16:9 라 가운데를 정사각형으로 자릅니다."""
    if urlparse(url).scheme != "https" or not (urlparse(url).hostname or "").endswith(COVER_HOSTS):
        return  # 곡 정보는 화면에서 오므로 유튜브 표지 서버가 아닌 주소는 열지 않습니다
    url = re.sub(r"=w\d+-h\d+", "=w600-h600", url)
    raw = target.with_suffix(".src")
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=20) as r:
            raw.write_bytes(r.read(MAX_COVER_BYTES))
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(raw),
                        "-vf", "crop='min(iw,ih)':'min(iw,ih)'", "-q:v", "3", str(target)], check=True)
    except (OSError, subprocess.CalledProcessError):
        pass  # 표지가 없어도 곡은 들립니다
    finally:
        raw.unlink(missing_ok=True)


def probe_duration(path: Path) -> float | None:
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                             capture_output=True, text=True, check=True).stdout
        return float(out)
    except (OSError, subprocess.CalledProcessError, ValueError):
        return None


# yt-dlp 의 영어 오류를 화면에 그대로 띄우지 않고 무슨 일인지 한 줄로 알립니다.
# 문구는 messages.py 에 언어별로 있고, 여기서는 코드만 고릅니다.
FRIENDLY_ERRORS = (
    ("Requested format is not available", "youtube.format_unavailable"),
    ("Sign in to confirm", "youtube.sign_in"),
    ("Private video", "youtube.private"),
    ("Video unavailable", "youtube.unavailable"),
)


class NoAudio(RuntimeError):
    """yt-dlp 가 오류 없이 끝났는데 mp3 가 없습니다."""


def friendly(error: Exception) -> str | dict:
    """알아보는 실패는 문구 코드로, 모르는 실패는 yt-dlp 원문 한 줄로 돌려줍니다."""
    if isinstance(error, NoAudio):
        return msg("youtube.no_file")
    text = str(error).splitlines()[0] if str(error) else type(error).__name__
    for needle, code in FRIENDLY_ERRORS:
        if needle in text:
            return msg(code)
    return re.sub(r"^ERROR:\s*(\[\w+\]\s*[\w-]+:\s*)?", "", text)[:200]


def wire(reason: str | dict) -> str:
    return to_wire(reason) if isinstance(reason, dict) else reason


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("track")
    parser.add_argument("-o", "--out", type=Path, required=True)
    args = parser.parse_args()
    track = json.loads(args.track)
    video_id, title = track["videoId"], track.get("title") or track["videoId"]
    if not VIDEO_ID.fullmatch(video_id):
        print(f"[failed] {video_id}: {wire(msg('youtube.bad_id'))}")
        return 1
    lib: Path = args.out
    tid = track_id(video_id)
    workdir = lib / f".yt-{video_id}"  # 숨김 폴더라 받는 중에는 목록에 안 잡힙니다
    workdir.mkdir(parents=True, exist_ok=True)
    try:
        audio = download(video_id, workdir, cookies_path(lib))
        save_cover(track.get("art") or "", workdir / "cover.jpg")
        target = lib / f"{tid}.mp3"
        duration = track.get("duration") or probe_duration(audio)
        if (workdir / "cover.jpg").exists():
            shutil.move(workdir / "cover.jpg", lib / f"{tid}.jpg")
        # 같은 폴더 안의 이름 바꾸기라 한 번에 옮겨집니다. 반쯤 받은 곡이 목록에 뜨지 않습니다.
        shutil.move(audio, target)
        library.upsert(lib, tid, title=title, artist=track.get("artist") or "", tags=track.get("album") or "",
                       duration=duration, image_url=track.get("art") or "", source="youtube")
    except Exception as error:  # noqa: BLE001 - 어떤 실패든 서버에는 한 줄로 알립니다
        print(f"[failed] {video_id}: {wire(friendly(error))}")
        return 1
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
    print(f"[ok] {video_id}: {track.get('artist') or 'YouTube'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
