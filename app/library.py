"""곡 정보의 정본은 오디오 파일 안의 태그입니다(app/tags.py). solo.db 는 그 태그를 빠르게 읽으려고 둔 캐시라서
지워도 파일만 있으면 목록, 가사, 좋아요가 그대로 돌아옵니다. 곡을 바꾸는 쓰기는 늘 파일에 먼저 합니다.

앱에서 곡을 빼도 파일은 지우지 않습니다. archive/ 폴더로 옮겨 호스트에 남기고 언제든 되살립니다."""

from __future__ import annotations

import json
import shutil
import sqlite3
import time
from pathlib import Path

from app import tags as T


def report_progress(fraction: float) -> None:
    """녹음기와 다운로더가 진행률을 서버에 알리는 한 줄입니다. 서버는 이 줄을 읽어 화면에 % 로 띄웁니다."""
    print(f"[progress] {min(max(fraction, 0.0), 1.0):.3f}", flush=True)

DB_NAME = "solo.db"
ARCHIVE = "archive"
AUDIO = (".mp3", ".m4a")  # 지금은 전부 mp3 로 받고, 올린 m4a 는 그대로 둡니다
SUFFIXES = (*AUDIO, ".jpg")

# 캐시의 모양이 바뀌면 올립니다. 올리면 캐시를 버리고 파일에서 다시 읽습니다.
CACHE_VERSION = 2

SCHEMA = """
CREATE TABLE IF NOT EXISTS tracks (
    id        TEXT PRIMARY KEY,           -- 오디오 파일 이름(확장자 제외). 올린 곡은 up-<내용 해시>
    title     TEXT NOT NULL,
    artist    TEXT NOT NULL DEFAULT '',
    tags      TEXT NOT NULL DEFAULT '',   -- 장르. 수노 곡은 스타일
    duration  REAL,
    suno_id   TEXT NOT NULL DEFAULT '',
    liked     INTEGER NOT NULL DEFAULT 0,
    added     INTEGER NOT NULL,
    archived  INTEGER NOT NULL DEFAULT 0, -- 1 이면 파일이 archive/ 에 있다
    source    TEXT NOT NULL DEFAULT '',   -- suno | upload | 빈 값(폴더에 직접 넣은 파일)
    lyrics    TEXT NOT NULL DEFAULT '',
    mtime     INTEGER NOT NULL DEFAULT 0  -- 캐시를 채울 때 파일의 수정 시각(ns). 다르면 파일이 바뀐 것이다
);
"""


def connect(lib: Path) -> sqlite3.Connection:
    db = sqlite3.connect(lib / DB_NAME, timeout=10)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA journal_mode=WAL")
    if db.execute("PRAGMA user_version").fetchone()[0] != CACHE_VERSION:
        _move_db_info_into_files(lib, db)
        db.execute("DROP TABLE IF EXISTS tracks")
        db.execute(f"PRAGMA user_version={CACHE_VERSION}")
    db.executescript(SCHEMA)
    return db


def _move_db_info_into_files(lib: Path, db: sqlite3.Connection) -> None:
    """곡 정보를 DB 에만 두던 옛 보관함을 한 번 옮깁니다. 아직 Solo 태그가 없는 파일에 DB 의 정보와 표지를 씁니다."""
    if not db.execute("SELECT 1 FROM sqlite_master WHERE name='tracks'").fetchone():
        return
    for row in db.execute("SELECT * FROM tracks").fetchall():
        row = dict(row)
        path = locate(lib, row["id"])
        if path is None or T.ADDED in T.read(path):
            continue
        suno_id = row.get("suno_id") or ""
        info = {T.TITLE: row["title"], T.ARTIST: row.get("artist") or "", T.GENRE: row.get("tags") or "",
                T.SOURCE: row.get("source") or ("suno" if suno_id else ""), T.SUNO_ID: suno_id,
                T.LIKED: "1" if row.get("liked") else "", T.ADDED: str(int(row["added"]))}
        if row.get("lyrics"):
            info[T.LYRICS] = row["lyrics"]
        if row.get("duration"):
            info[T.DURATION] = str(row["duration"])
        cover = path.with_suffix(".jpg")
        T.write_if_possible(path, info, cover.read_bytes() if cover.exists() else None)


JOBS_SCHEMA = """
CREATE TABLE IF NOT EXISTS jobs (
    id    TEXT PRIMARY KEY,
    added REAL NOT NULL,
    data  TEXT NOT NULL                   -- 화면에 보여 주는 작업 정보 그대로(JSON)
)
"""


def save_job(lib: Path, job: dict, keep: int) -> None:
    """녹음, 받기 기록을 남깁니다. 서버가 다시 켜져도 기록과 대기열이 그대로 이어집니다."""
    with connect(lib) as db:
        db.execute(JOBS_SCHEMA)
        db.execute("INSERT INTO jobs (id, added, data) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET data=excluded.data",
                   (job["id"], time.time(), json.dumps(job, ensure_ascii=False)))
        db.execute("DELETE FROM jobs WHERE id NOT IN (SELECT id FROM jobs ORDER BY added DESC LIMIT ?)", (keep,))


def load_jobs(lib: Path) -> list[dict]:
    with connect(lib) as db:
        db.execute(JOBS_SCHEMA)
        return [json.loads(r["data"]) for r in db.execute("SELECT data FROM jobs ORDER BY added")]


def audio_files(folder: Path) -> dict[str, Path]:
    """폴더의 오디오 파일을 {곡 id: 경로} 로 돌려줍니다. 숨김 파일은 받는 중인 임시 파일이라 뺍니다."""
    return {f.stem: f for ext in AUDIO for f in folder.glob(f"*{ext}") if not f.name.startswith(".")}


def find_audio(folder: Path, track_id: str) -> Path | None:
    if "/" in track_id or "\\" in track_id or track_id.startswith("."):
        return None
    return next((p for ext in AUDIO if (p := folder / f"{track_id}{ext}").is_file()), None)


def locate(lib: Path, track_id: str) -> Path | None:
    """보관함이나 archive/ 에서 곡 파일을 찾습니다."""
    return find_audio(lib, track_id) or find_audio(lib / ARCHIVE, track_id)


def _move(src_dir: Path, dst_dir: Path, track_id: str) -> None:
    dst_dir.mkdir(exist_ok=True)
    with T.lock:  # 태그를 쓰는 중에 옮기면 쓰기가 옛 자리에 파일을 되살립니다
        for suffix in SUFFIXES:
            src = src_dir / f"{track_id}{suffix}"
            if src.exists():
                shutil.move(src, dst_dir / src.name)


def archive(lib: Path, track_id: str) -> None:
    """앱 목록에서 빼고 파일은 archive/ 로 옮깁니다. 같은 이름이 이미 있으면 덮어씁니다."""
    _move(lib, lib / ARCHIVE, track_id)
    sync(lib)


def restore(lib: Path, track_id: str) -> None:
    _move(lib / ARCHIVE, lib, track_id)
    sync(lib)


def save(lib: Path, track_id: str, info: dict[str, str], cover: bytes | None = None) -> None:
    """곡 정보를 파일에 쓰고 캐시를 맞춥니다. info 에 없는 칸은 파일에 있던 그대로 둡니다."""
    path = locate(lib, track_id)
    if path is None:
        return
    T.write(path, info, cover)
    with connect(lib) as db:
        _cache(db, path, archived=path.parent != lib)


def upsert(lib: Path, track_id: str, *, title: str, artist: str = "", tags: str = "",
           duration: float | None = None, suno_id: str = "", source: str = "suno",
           lyrics: str | None = None) -> None:
    """곡 정보를 씁니다. 좋아요와 추가 시각은 파일에 있던 그대로 두고, 가사를 안 주면 있던 가사도 그대로 둡니다."""
    info = {T.TITLE: title, T.ARTIST: artist, T.GENRE: tags, T.SUNO_ID: suno_id, T.SOURCE: source}
    if lyrics is not None:
        info[T.LYRICS] = lyrics
    if duration:
        info[T.DURATION] = str(duration)
    save(lib, track_id, info)


def set_lyrics(lib: Path, track_id: str, lyrics: str) -> None:
    save(lib, track_id, {T.LYRICS: lyrics})


def toggle_like(lib: Path, track_id: str) -> bool | None:
    with connect(lib) as db:
        row = db.execute("SELECT liked FROM tracks WHERE id=?", (track_id,)).fetchone()
    if row is None:
        return None
    liked = not row["liked"]
    save(lib, track_id, {T.LIKED: "1" if liked else ""})
    return liked


def lyrics(lib: Path, track_id: str) -> str:
    with connect(lib) as db:
        row = db.execute("SELECT lyrics FROM tracks WHERE id=?", (track_id,)).fetchone()
    return row["lyrics"] if row else ""


def sync(lib: Path) -> None:
    """폴더를 보고 캐시를 맞춥니다. 새로 생기거나 바뀐 파일만 태그를 다시 읽습니다."""
    places = {stem: (path, 1) for stem, path in audio_files(lib / ARCHIVE).items()}
    places |= {stem: (path, 0) for stem, path in audio_files(lib).items()}
    with connect(lib) as db:
        cached = {r["id"]: (r["mtime"], r["archived"]) for r in db.execute("SELECT id, mtime, archived FROM tracks")}
        for stem, (path, archived) in places.items():
            if cached.get(stem) != (path.stat().st_mtime_ns, archived):
                _cache(db, path, archived=bool(archived))
        db.executemany("DELETE FROM tracks WHERE id=?", [(gone,) for gone in cached.keys() - places.keys()])


def _cache(db: sqlite3.Connection, path: Path, *, archived: bool) -> None:
    """파일 하나의 태그를 캐시에 옮깁니다. 처음 보는 파일이면 들어온 시각을 파일에 적고, 표지가 파일 안에만 있으면 꺼내 둡니다."""
    info = T.read(path)
    if T.ADDED not in info and T.write_if_possible(path, {T.ADDED: str(int(path.stat().st_mtime))}):
        info = T.read(path)
    cover = path.with_suffix(".jpg")
    if not cover.exists() and (embedded := T.read_cover(path)):
        cover.write_bytes(embedded)
    duration = T.number(info.get(T.DURATION)) or None
    db.execute(
        """INSERT OR REPLACE INTO tracks
           (id, title, artist, tags, duration, suno_id, liked, added, archived, source, lyrics, mtime)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
        (path.stem, info.get(T.TITLE) or path.stem.replace("-", " ").title(), info.get(T.ARTIST, ""),
         info.get(T.GENRE, ""), duration, info.get(T.SUNO_ID, ""), int(info.get(T.LIKED) == "1"),
         int(T.number(info.get(T.ADDED)) or path.stat().st_mtime), int(archived), info.get(T.SOURCE, ""),
         info.get(T.LYRICS, ""), path.stat().st_mtime_ns))
