"""내가 만들었거나 정당하게 가진 곡 파일을 보관함에 넣습니다.

mp3 와 aac(m4a)는 그대로 두고, 나머지 형식은 mp3 로 바꿉니다. 제목과 아티스트는 파일 안의 태그를,
표지는 파일에 박힌 그림을 씁니다. 태그가 없으면 파일 이름을 제목으로 씁니다."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

from . import library

TYPES = (".mp3", ".m4a", ".flac", ".wav", ".ogg", ".opus", ".aac")
KEEP_AS_IS = {".mp3": "mp3", ".m4a": "aac"}  # 확장자 → 그대로 둘 때 있어야 하는 코덱
COVER_SIZE = 800


class Rejected(Exception):
    """화면에 보여 줄 거절 사유입니다. code 는 messages 의 문구 코드입니다."""

    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def probe(path: Path) -> dict:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-print_format", "json", "-show_format", "-show_streams", str(path)],
        capture_output=True, check=False, timeout=60)
    if out.returncode != 0:
        raise Rejected("upload.not_audio")
    return json.loads(out.stdout or b"{}")


def _ffmpeg(*args: str) -> None:
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", *args], check=True, timeout=600)


def add_file(lib: Path, src: Path, track_id: str, fallback_title: str) -> dict:
    """src 를 보관함의 곡 track_id 로 넣고, 넣은 곡 정보를 돌려줍니다."""
    info = probe(src)
    streams = info.get("streams") or []
    audio = next((s for s in streams if s.get("codec_type") == "audio"), None)
    if audio is None:
        raise Rejected("upload.not_audio")
    fmt = info.get("format") or {}
    tags = {k.lower(): str(v).strip() for k, v in (fmt.get("tags") or {}).items()}

    suffix = src.suffix.lower()
    keep = KEEP_AS_IS.get(suffix) == audio.get("codec_name")
    ext = suffix if keep else ".mp3"
    part = lib / f".{track_id}{ext}"  # 점으로 시작하면 목록 동기화가 건너뜁니다
    try:
        if keep:
            shutil.copyfile(src, part)
        else:
            _ffmpeg("-i", str(src), "-map", "0:a:0", "-vn", "-codec:a", "libmp3lame", "-q:a", "2",
                    "-f", "mp3", str(part))
        if any(s.get("disposition", {}).get("attached_pic") for s in streams):
            try:
                _ffmpeg("-i", str(src), "-an", "-frames:v", "1", "-vf",
                        f"scale={COVER_SIZE}:{COVER_SIZE}:force_original_aspect_ratio=decrease",
                        str(lib / f"{track_id}.jpg"))
            except subprocess.CalledProcessError:
                pass  # 표지가 깨져 있어도 곡은 넣습니다
        part.replace(lib / f"{track_id}{ext}")
    finally:
        part.unlink(missing_ok=True)

    try:
        duration = float(fmt.get("duration") or audio.get("duration") or 0) or None
    except ValueError:
        duration = None
    title = tags.get("title") or fallback_title.strip() or track_id
    track = {"title": title[:200], "artist": tags.get("artist", "")[:200], "tags": tags.get("album", "")[:200],
             "duration": duration}
    library.upsert(lib, track_id, **track, source="upload")
    return {"id": track_id, **track}
