"""유튜브에서 곡을 찾고, 붙여넣은 주소를 곡 목록으로 폅니다.

받은 곡은 서버가 mp3 파일로 들고 있다가 직접 내줍니다. 구글은 2026-02 부터 비프리미엄 계정의
모바일 브라우저 백그라운드 재생을 서버에서 끊는데, 그 차단은 youtube.com 에서 재생할 때만 걸립니다.

음악만 골라내는 건 유튜브 뮤직의 "노래" 검색이 합니다. 뮤직비디오나 커버 대신 공식 음원이
곡명, 아티스트, 앨범, 정사각형 표지와 함께 나옵니다. 이 검색은 로그인해야만 결과가 나오므로
cookies.txt(Netscape 형식, 서브 계정 권장)가 있을 때만 쓰고, 없으면 yt-dlp 일반 검색으로 대신합니다.

유튜브에는 한 번에 한 요청씩만 보냅니다. 목록을 통째로 긁거나 병렬로 받지 않습니다.
"""

from __future__ import annotations

import os
import re
from pathlib import Path
from urllib.parse import parse_qs, urlparse

VIDEO_ID = re.compile(r"[A-Za-z0-9_-]{11}")
YOUTUBE_URL = re.compile(r"https?://((www|m|music)\.)?(youtube\.com|youtu\.be)/\S+")
MAX_FROM_URL = 1000  # 재생목록 주소 하나로 받는 최대 곡 수. 받기는 어차피 한 곡씩 띄워서 합니다
COOKIE_DOMAINS = ("youtube.com", "google.com")
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
_TOPIC = re.compile(r"\s*-\s*Topic$")


def cookies_path(lib: Path) -> Path:
    return Path(os.environ.get("SOLO_YT_COOKIES") or lib / ".youtube" / "cookies.txt")


def read_cookies(path: Path) -> dict[str, str]:
    """Netscape cookies.txt 에서 유튜브와 구글 쿠키만 {이름: 값} 으로 꺼냅니다."""
    jar: dict[str, str] = {}
    if not path.is_file():
        return jar
    for line in path.read_text(errors="replace").splitlines():
        line = line.strip()
        if line.startswith("#HttpOnly_"):  # 주석이 아니라 HttpOnly 쿠키입니다
            line = line[len("#HttpOnly_"):]
        elif not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) >= 7 and parts[0].lstrip(".").endswith(COOKIE_DOMAINS):
            jar[parts[5]] = parts[6]
    return jar


def is_logged_in(jar: dict[str, str]) -> bool:
    return any(k in jar for k in ("__Secure-3PAPISID", "SAPISID"))


def ytmusic_headers(jar: dict[str, str]) -> dict[str, str]:
    """ytmusicapi 는 Cookie 헤더만 있으면 SAPISIDHASH 를 스스로 계산합니다."""
    return {
        "Cookie": "; ".join(f"{k}={v}" for k, v in jar.items()), "User-Agent": UA,
        "Accept": "*/*", "Accept-Language": "ko-KR,ko;q=0.9", "Content-Type": "application/json",
        "X-Goog-AuthUser": "0", "Origin": "https://music.youtube.com",
    }


def _art(thumbs) -> str:
    if isinstance(thumbs, dict):
        thumbs = thumbs.get("thumbnails") or []
    if not isinstance(thumbs, list) or not thumbs:
        return ""
    best = max((t for t in thumbs if isinstance(t, dict)), key=lambda t: t.get("width", 0), default={})
    return best.get("url", "")


def _names(items) -> str:
    if isinstance(items, str):
        return items
    if isinstance(items, dict):
        return items.get("name") or ""
    return ", ".join(i.get("name", "") for i in items or [] if isinstance(i, dict) and i.get("name"))


def _seconds(text) -> int | None:
    if isinstance(text, (int, float)):
        return int(text)
    if isinstance(text, str) and re.fullmatch(r"\d+(:\d+)+", text):
        total = 0
        for part in text.split(":"):
            total = total * 60 + int(part)
        return total
    return None


def from_ytmusic(item: dict) -> dict | None:
    vid = item.get("videoId")
    if not vid or not VIDEO_ID.fullmatch(vid):
        return None
    album = item.get("album")
    return {
        "videoId": vid, "title": item.get("title") or "Untitled",
        "artist": _names(item.get("artists")), "album": album.get("name", "") if isinstance(album, dict) else "",
        "duration": item.get("duration_seconds") or _seconds(item.get("duration")),
        "art": _art(item.get("thumbnails")),
    }


def from_ytdlp(entry: dict) -> dict | None:
    vid = entry.get("id") or ""
    if not VIDEO_ID.fullmatch(vid):  # 검색 결과에 섞인 채널, 재생목록은 뺍니다
        return None
    return {
        "videoId": vid, "title": entry.get("title") or "Untitled",
        "artist": _TOPIC.sub("", entry.get("uploader") or entry.get("channel") or ""), "album": "",
        "duration": int(entry["duration"]) if entry.get("duration") else None,
        "art": f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg",
    }


def _ytdlp_flat(url: str, cookies: Path, **extra) -> dict:
    from yt_dlp import YoutubeDL

    opts = {"quiet": True, "no_warnings": True, "skip_download": True,
            "extract_flat": "in_playlist", "ignoreerrors": True, **extra}
    if cookies.is_file():
        opts["cookiefile"] = str(cookies)
    with YoutubeDL(opts) as ydl:
        return ydl.extract_info(url, download=False) or {}


def search(query: str, cookies: Path, limit: int = 20) -> dict:
    """로그인돼 있으면 유튜브 뮤직 노래 검색, 아니면 yt-dlp 일반 검색입니다."""
    jar = read_cookies(cookies)
    if is_logged_in(jar):
        from ytmusicapi import YTMusic

        raw = YTMusic(ytmusic_headers(jar), language="ko", location="KR").search(query, filter="songs", limit=limit)
        return {"music": True, "tracks": [t for t in map(from_ytmusic, raw) if t][:limit]}
    info = _ytdlp_flat(f"ytsearch{limit}:{query}", cookies)
    return {"music": False, "tracks": [t for t in map(from_ytdlp, info.get("entries") or []) if t]}


def resolve(url: str, cookies: Path) -> list[dict]:
    """붙여넣은 주소를 곡 목록으로 폅니다. v= 가 있으면 딸려 온 라디오 목록은 무시하고 그 곡만 받습니다."""
    single = "v" in parse_qs(urlparse(url).query) or "youtu.be/" in url
    info = _ytdlp_flat(url, cookies, playlistend=MAX_FROM_URL, **({"noplaylist": True} if single else {}))
    entries = info.get("entries")
    if entries is None:
        track = from_ytdlp(info)
        return [track] if track else []
    return [t for t in map(from_ytdlp, entries) if t][:MAX_FROM_URL]


def track_id(video_id: str) -> str:
    return f"yt-{video_id}"
