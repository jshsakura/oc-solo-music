"""곡 정보의 정본은 오디오 파일 안의 태그입니다. solo.db 는 이 태그를 빠르게 읽으려고 둔 캐시입니다.

표준 칸(제목, 아티스트, 앨범, 연도, 장르, 가사, 길이, 표지)은 다른 플레이어도 읽습니다.
Solo 와 수노만 쓰는 칸은 이름을 붙인 사용자 칸(ID3 TXXX, MP4 freeform)에 둡니다.
다른 플레이어는 그 칸을 읽지 않아도 지우지 않으므로 파일을 어디로 옮겨도 정보가 따라갑니다."""

from __future__ import annotations

import logging
import os
import shutil
import tempfile
import threading
from pathlib import Path

from mutagen import MutagenError
from mutagen.id3 import APIC, ID3, TALB, TCON, TDRC, TIT2, TLEN, TPE1, TXXX, USLT, ID3NoHeaderError
from mutagen.mp3 import MP3
from mutagen.mp4 import MP4, MP4Cover, MP4FreeForm

TITLE, ARTIST, ALBUM, YEAR, GENRE, LYRICS, DURATION = "title", "artist", "album", "year", "genre", "lyrics", "duration"
SOURCE = "SOLO_SOURCE"    # suno | upload | 빈 값(폴더에 직접 넣은 파일)
ADDED = "SOLO_ADDED"      # 보관함에 들어온 시각(유닉스 초)
LIKED = "SOLO_LIKED"      # "1" 이면 좋아요
GENRE_TEXT = "SOLO_GENRE"  # 장르 원문. ID3 장르 칸은 괄호 속 숫자를 옛 장르 번호로 읽고 줄바꿈에서 값을 가르므로 따로 둡니다
SUNO_ID = "SUNO_ID"
SUNO_URL = "SUNO_URL"
SUNO_MODEL = "SUNO_MODEL"
SUNO_CREATED = "SUNO_CREATED"
SUNO_CLIP = "SUNO_CLIP"   # 수노가 준 곡 정보 전체(JSON). 다시 만들 때 쓸 재료를 하나도 버리지 않으려고 통째로 둡니다

_ID3 = {TITLE: TIT2, ARTIST: TPE1, ALBUM: TALB, YEAR: TDRC, GENRE: TCON}
_MP4 = {TITLE: "\xa9nam", ARTIST: "\xa9ART", ALBUM: "\xa9alb", YEAR: "\xa9day", GENRE: "\xa9gen", LYRICS: "\xa9lyr"}
_FREEFORM = "----:com.apple.iTunes:"

# 같은 파일을 두 군데서 동시에 고치거나 옮기면 한쪽이 쓴 것이 사라집니다. 서버 안의 쓰기와 옮기기는 한 줄로 세웁니다.
lock = threading.Lock()
log = logging.getLogger(__name__)


def read(path: Path) -> dict[str, str]:
    """파일의 태그를 {칸: 값} 으로 돌려줍니다. 태그가 없거나 읽을 수 없는 파일이면 빈 dict 입니다."""
    try:
        return _read_mp4(path) if path.suffix.lower() == ".m4a" else _read_id3(path)
    except (MutagenError, OSError, ValueError):
        return {}


def read_cover(path: Path) -> bytes | None:
    try:
        if path.suffix.lower() == ".m4a":
            covers = MP4(path).tags.get("covr") or []
            return bytes(covers[0]) if covers else None
        pics = ID3(path).getall("APIC")
        return pics[0].data if pics else None
    except (MutagenError, OSError, ValueError, AttributeError):
        return None


def write(path: Path, info: dict[str, str], cover: bytes | None = None) -> None:
    """info 의 칸만 바꾸고 나머지 태그는 그대로 둡니다. 값이 빈 문자열이면 그 칸을 지웁니다.

    사본에 쓴 뒤 바꿔 끼웁니다. 재생 중인 파일을 제자리에서 고쳐 쓰면 듣던 소리가 깨집니다."""
    with lock:
        fd, name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tagging", dir=path.parent)
        os.close(fd)
        part = Path(name)
        try:
            shutil.copyfile(path, part)
            shutil.copymode(path, part)  # mkstemp 는 600 으로 만듭니다. 원래 권한을 지켜야 다른 사용자와 컨테이너가 읽습니다
            if path.suffix.lower() == ".m4a":
                _write_mp4(part, info, cover)
            else:
                _write_id3(part, info, cover)
            os.replace(part, path)
        finally:
            part.unlink(missing_ok=True)


def write_if_possible(path: Path, info: dict[str, str], cover: bytes | None = None) -> bool:
    """망가진 파일 하나 때문에 보관함 전체가 멈추지 않도록, 쓰지 못하면 기록만 남기고 넘어갑니다."""
    try:
        write(path, info, cover)
        return True
    except (MutagenError, OSError, ValueError) as e:
        log.warning("태그를 쓰지 못했습니다: %s (%s)", path.name, type(e).__name__)
        return False


def number(value: str | None) -> float:
    """다른 태거가 쓴 숫자 칸이 이상해도 0 으로 읽습니다."""
    try:
        return float(value or 0)
    except ValueError:
        return 0.0


def _read_id3(path: Path) -> dict[str, str]:
    try:
        tags = ID3(path)
    except ID3NoHeaderError:
        tags = None
    out: dict[str, str] = {}
    if tags is not None:
        for key, frame in _ID3.items():
            found = tags.get(frame.__name__)
            if found and found.text:
                out[key] = str(found.text[0])
        lyrics = tags.getall("USLT")
        if lyrics:
            out[LYRICS] = lyrics[0].text
        if "TLEN" in tags and (ms := number(str(tags["TLEN"].text[0]))):
            out[DURATION] = f"{ms / 1000:g}"
        for frame in tags.getall("TXXX"):
            out[frame.desc] = str(frame.text[0]) if frame.text else ""
        if GENRE_TEXT in out:
            out[GENRE] = out.pop(GENRE_TEXT)
    if DURATION not in out:
        try:
            out[DURATION] = f"{MP3(path).info.length:g}"
        except MutagenError:
            pass
    return out


def _write_id3(path: Path, info: dict[str, str], cover: bytes | None) -> None:
    try:
        tags = ID3(path)
    except ID3NoHeaderError:
        tags = ID3()
    if GENRE in info:
        info = {**info, GENRE_TEXT: info[GENRE]}
    for key, value in info.items():
        if key in _ID3:
            name = _ID3[key].__name__
            tags.delall(name)
            if value:
                tags.add(_ID3[key](encoding=3, text=value))
        elif key == LYRICS:
            tags.delall("USLT")
            if value:
                tags.add(USLT(encoding=3, lang="und", desc="", text=value))
        elif key == DURATION:
            tags.delall("TLEN")
            if value:
                tags.add(TLEN(encoding=3, text=str(round(float(value) * 1000))))
        else:
            tags.delall(f"TXXX:{key}")
            if value:
                tags.add(TXXX(encoding=3, desc=key, text=value))
    if cover:
        tags.delall("APIC")
        tags.add(APIC(encoding=3, mime="image/jpeg", type=3, desc="", data=cover))
    tags.save(path, v2_version=3)  # 윈도와 차량 오디오까지 읽는 2.3 으로 씁니다


def _read_mp4(path: Path) -> dict[str, str]:
    audio = MP4(path)
    tags = audio.tags or {}
    out = {key: str(tags[atom][0]) for key, atom in _MP4.items() if tags.get(atom)}
    for atom, values in tags.items():
        if atom.startswith(_FREEFORM) and values:
            out[atom[len(_FREEFORM):]] = bytes(values[0]).decode("utf-8", "replace")
    out[DURATION] = f"{audio.info.length:g}"
    return out


def _write_mp4(path: Path, info: dict[str, str], cover: bytes | None) -> None:
    audio = MP4(path)
    if audio.tags is None:
        audio.add_tags()
    for key, value in info.items():
        if key == DURATION:
            continue  # MP4 는 길이를 컨테이너가 들고 있습니다
        atom = _MP4.get(key) or f"{_FREEFORM}{key}"
        audio.tags.pop(atom, None)
        if value:
            audio.tags[atom] = [MP4FreeForm(value.encode())] if atom.startswith(_FREEFORM) else [value]
    if cover:
        audio.tags["covr"] = [MP4Cover(cover, imageformat=MP4Cover.FORMAT_JPEG)]
    audio.save()
