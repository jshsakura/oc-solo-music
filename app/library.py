"""곡 목록은 SQLite 한 파일(solo.db)에 둡니다. 오디오와 표지 이미지만 파일로 남깁니다.

앱에서 곡을 빼도 파일은 지우지 않습니다. archive/ 폴더로 옮겨 호스트에 남기고 언제든 되살립니다."""

from __future__ import annotations

import json
import shutil
import sqlite3
import time
from pathlib import Path


def report_progress(fraction: float) -> None:
    """녹음기와 다운로더가 진행률을 서버에 알리는 한 줄입니다. 서버는 이 줄을 읽어 화면에 % 로 띄웁니다."""
    print(f"[progress] {min(max(fraction, 0.0), 1.0):.3f}", flush=True)

DB_NAME = "solo.db"
ARCHIVE = "archive"
AUDIO = (".mp3", ".m4a")  # 지금은 전부 mp3 로 받고, 예전에 받은 m4a 도 그대로 읽습니다
SUFFIXES = (*AUDIO, ".jpg")

SCHEMA = """
CREATE TABLE IF NOT EXISTS tracks (
    id        TEXT PRIMARY KEY,           -- 오디오 파일 이름(확장자 제외). 올린 곡은 up-<내용 해시>
    title     TEXT NOT NULL,
    artist    TEXT NOT NULL DEFAULT '',
    tags      TEXT NOT NULL DEFAULT '',
    duration  REAL,
    image_url TEXT NOT NULL DEFAULT '',
    suno_id   TEXT NOT NULL DEFAULT '',
    liked     INTEGER NOT NULL DEFAULT 0,
    added     INTEGER NOT NULL,
    archived  INTEGER NOT NULL DEFAULT 0, -- 1 이면 앱 목록에서 뺐고 파일은 archive/ 에 있다
    source    TEXT NOT NULL DEFAULT '',   -- suno | upload | 빈 값(폴더에 직접 넣은 파일). 예전 youtube 도 남아 있을 수 있다
    lyrics    TEXT                        -- 수노 가사. NULL 이면 아직 안 받아 봤고, 빈 값이면 연주곡이거나 가사가 없다
);
"""


def connect(lib: Path) -> sqlite3.Connection:
    db = sqlite3.connect(lib / DB_NAME, timeout=10)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA journal_mode=WAL")
    db.executescript(SCHEMA)
    columns = {row["name"] for row in db.execute("PRAGMA table_info(tracks)")}
    if "archived" not in columns:
        db.execute("ALTER TABLE tracks ADD COLUMN archived INTEGER NOT NULL DEFAULT 0")
    if "source" not in columns:
        db.execute("ALTER TABLE tracks ADD COLUMN source TEXT NOT NULL DEFAULT ''")
        db.execute("UPDATE tracks SET source='suno' WHERE suno_id != ''")
    if "lyrics" not in columns:
        db.execute("ALTER TABLE tracks ADD COLUMN lyrics TEXT")
    return db


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


def _move(src_dir: Path, dst_dir: Path, track_id: str) -> None:
    dst_dir.mkdir(exist_ok=True)
    for suffix in SUFFIXES:
        src = src_dir / f"{track_id}{suffix}"
        if src.exists():
            shutil.move(src, dst_dir / src.name)


def archive(lib: Path, track_id: str) -> None:
    """앱 목록에서 빼고 파일은 archive/ 로 옮깁니다. 같은 이름이 이미 있으면 덮어씁니다."""
    _move(lib, lib / ARCHIVE, track_id)
    with connect(lib) as db:
        db.execute("UPDATE tracks SET archived=1 WHERE id=?", (track_id,))


def restore(lib: Path, track_id: str) -> None:
    _move(lib / ARCHIVE, lib, track_id)
    with connect(lib) as db:
        db.execute("UPDATE tracks SET archived=0 WHERE id=?", (track_id,))


def upsert(lib: Path, track_id: str, *, title: str, artist: str = "", tags: str = "",
           duration: float | None = None, image_url: str = "", suno_id: str = "",
           source: str = "suno", lyrics: str | None = None) -> None:
    """받아 둔 곡을 넣습니다. 이미 있으면 좋아요와 추가 시각은 그대로 두고, 가사를 안 주면 받아 둔 가사도 그대로 둡니다."""
    with connect(lib) as db:
        db.execute(
            """INSERT INTO tracks (id, title, artist, tags, duration, image_url, suno_id, source, lyrics, added)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(id) DO UPDATE SET title=excluded.title, artist=excluded.artist,
                 tags=excluded.tags, duration=excluded.duration, image_url=excluded.image_url,
                 suno_id=excluded.suno_id, source=excluded.source,
                 lyrics=COALESCE(excluded.lyrics, tracks.lyrics)""",
            (track_id, title, artist, tags, duration, image_url, suno_id, source, lyrics, int(time.time())))


def set_lyrics(lib: Path, track_id: str, lyrics: str) -> None:
    with connect(lib) as db:
        db.execute("UPDATE tracks SET lyrics=? WHERE id=?", (lyrics, track_id))


def lyrics(lib: Path, track_id: str) -> str:
    with connect(lib) as db:
        row = db.execute("SELECT lyrics FROM tracks WHERE id=?", (track_id,)).fetchone()
    return (row["lyrics"] if row else None) or ""


def sync(lib: Path) -> None:
    """폴더와 DB 를 맞춥니다. 처음 한 번은 옛 JSON 사이드카와 좋아요 파일도 가져옵니다."""
    files = audio_files(lib)
    shelved = set(audio_files(lib / ARCHIVE))
    likes_file = lib / ".likes.json"
    old_likes: set[str] = set()
    if likes_file.exists():
        try:
            old_likes = set(json.loads(likes_file.read_text()))
        except (OSError, ValueError):
            pass
    with connect(lib) as db:
        rows = {r["id"]: r["archived"] for r in db.execute("SELECT id, archived FROM tracks")}
        known = set(rows)
        # 손으로 폴더를 오가며 옮긴 파일도 실제 위치를 따릅니다.
        db.executemany("UPDATE tracks SET archived=0 WHERE id=?", [(i,) for i, a in rows.items() if a and i in files])
        db.executemany("UPDATE tracks SET archived=1 WHERE id=?", [(i,) for i, a in rows.items() if not a and i not in files and i in shelved])
        for stem, mp3 in files.items():
            if stem in known:
                continue
            side = mp3.with_suffix(".json")
            try:
                info = json.loads(side.read_text())
            except (OSError, ValueError):
                info = {}
            db.execute(
                "INSERT INTO tracks (id, title, artist, tags, duration, image_url, suno_id, liked, added)"
                " VALUES (?,?,?,?,?,?,?,?,?)",
                (stem, info.get("title") or stem.replace("-", " ").title(), info.get("artist") or "",
                 info.get("tags") or "", info.get("duration"), info.get("image_url") or "",
                 info.get("id") or "", int(stem in old_likes), int(mp3.stat().st_mtime)))
            side.unlink(missing_ok=True)
        gone = known - files.keys() - shelved
        db.executemany("DELETE FROM tracks WHERE id=?", [(g,) for g in gone])
    likes_file.unlink(missing_ok=True)
