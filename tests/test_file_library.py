"""곡 정보의 정본은 파일입니다. solo.db 를 지우거나 파일만 다른 보관함으로 옮겨도 정보가 따라가야 합니다."""

import json
import shutil
import sqlite3
import subprocess

import pytest

from app import library, suno_record, tags
from tests.conftest import add_song

needs_ffmpeg = pytest.mark.skipif(shutil.which("ffmpeg") is None, reason="ffmpeg 가 없습니다")


def real_mp3(path, **meta):
    args = [a for k, v in meta.items() for a in ("-metadata", f"{k}={v}")]
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
                    *args, str(path)], check=True)
    return path


def decoded_md5(path):
    out = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", str(path), "-map", "0:a", "-f", "md5", "-"],
                         capture_output=True, check=True)
    return out.stdout


def test_deleting_the_db_loses_nothing(lib, client):
    add_song(lib, "a")
    library.upsert(lib, "a", title="Kept", artist="Me", tags="city pop", suno_id="x", lyrics="la la")
    client.post("/api/like/a")
    before = client.get("/api/tracks").json()

    for leftover in lib.glob("solo.db*"):
        leftover.unlink()

    assert client.get("/api/tracks").json() == before
    assert client.get("/api/lyrics/a").json() == {"lyrics": "la la"}
    assert before[0]["liked"] is True and before[0]["tags"] == "city pop"


def test_a_file_carried_to_another_library_keeps_its_info(lib, client, tmp_path):
    add_song(lib, "a")
    library.upsert(lib, "a", title="Travels", artist="Me", lyrics="words")
    client.post("/api/like/a")
    other = tmp_path / "other"
    other.mkdir()
    shutil.copy(lib / "a.mp3", other / "a.mp3")

    library.sync(other)

    with library.connect(other) as db:
        row = dict(db.execute("SELECT title, artist, liked, lyrics FROM tracks").fetchone())
    assert row == {"title": "Travels", "artist": "Me", "liked": 1, "lyrics": "words"}


def test_old_db_only_library_moves_its_info_into_the_files(lib):
    add_song(lib, "a")
    (lib / "a.jpg").write_bytes(b"\xff\xd8cover")
    with sqlite3.connect(lib / "solo.db") as db:
        db.execute("CREATE TABLE tracks (id TEXT PRIMARY KEY, title TEXT, artist TEXT, tags TEXT, duration REAL,"
                   " image_url TEXT, suno_id TEXT, liked INTEGER, added INTEGER, archived INTEGER, source TEXT,"
                   " lyrics TEXT)")
        db.execute("INSERT INTO tracks VALUES ('a','Old','Me','rock',90,'','sx',1,1700000000,0,'suno','old words')")

    library.sync(lib)

    found = tags.read(lib / "a.mp3")
    assert (found[tags.TITLE], found[tags.GENRE], found[tags.LYRICS]) == ("Old", "rock", "old words")
    assert (found[tags.SUNO_ID], found[tags.LIKED], found[tags.ADDED]) == ("sx", "1", "1700000000")
    assert tags.read_cover(lib / "a.mp3") == b"\xff\xd8cover"


@needs_ffmpeg
def test_writing_tags_leaves_the_sound_untouched(tmp_path):
    song = real_mp3(tmp_path / "s.mp3")
    sound = decoded_md5(song)

    tags.write(song, {tags.TITLE: "T", tags.LYRICS: "long " * 500, tags.SUNO_CLIP: "{}"}, b"\xff\xd8" + b"x" * 5000)

    assert decoded_md5(song) == sound
    assert not list(tmp_path.glob(".*"))


@needs_ffmpeg
def test_a_tagged_mp3_dropped_into_the_folder_shows_with_its_tags_and_cover(lib, client):
    song = real_mp3(lib / "dropped.mp3", title="Dropped In", artist="Someone", genre="jazz")
    tags.write(song, {}, b"\xff\xd8art")

    track = client.get("/api/tracks").json()[0]

    assert (track["title"], track["artist"], track["tags"], track["cover"]) == ("Dropped In", "Someone", "jazz", True)
    assert (lib / "dropped.jpg").read_bytes() == b"\xff\xd8art"


@needs_ffmpeg
def test_upload_keeps_genre_and_lyrics_from_the_file(lib, client, tmp_path):
    src = real_mp3(tmp_path / "src.mp3", title="Mine", genre="folk", album="Home")
    tags.write(src, {tags.LYRICS: "my words"})

    track_id = client.put("/api/upload", params={"name": "x.mp3"}, content=src.read_bytes()).json()["id"]

    track = next(t for t in client.get("/api/tracks").json() if t["id"] == track_id)
    assert (track["title"], track["tags"], track["source"]) == ("Mine", "folk", "upload")
    assert client.get(f"/api/lyrics/{track_id}").json() == {"lyrics": "my words"}
    assert tags.read(lib / f"{track_id}.mp3")[tags.ALBUM] == "Home"


def test_suno_info_keeps_style_lyrics_and_the_raw_clip_without_noise():
    clip = {"title": "Song", "display_name": "me", "model_name": "chirp-v5", "created_at": "2026-11-20T01:02:03Z",
            "user_id": "u", "play_count": 3, "action_config": {"actions": []},
            "metadata": {"tags": "dream pop, female vocals", "prompt": "[Verse]\nhi", "model_badges": {}}}

    info = suno_record.clip_info("cid", clip)

    assert (info[tags.GENRE], info[tags.LYRICS], info[tags.YEAR]) == ("dream pop, female vocals", "[Verse]\nhi", "2026")
    assert (info[tags.SUNO_MODEL], info[tags.SUNO_URL]) == ("chirp-v5", "https://suno.com/song/cid")
    raw = json.loads(info[tags.SUNO_CLIP])
    assert raw["metadata"] == {"tags": "dream pop, female vocals", "prompt": "[Verse]\nhi"}
    assert not {"user_id", "play_count", "action_config"} & raw.keys()


def test_genre_text_comes_back_exactly_even_where_id3_would_reinterpret_it(tmp_path):
    song = tmp_path / "s.mp3"
    song.write_bytes(b"\xff\xfb" + b"\0" * 100)
    style = "(80s) synthwave\nfemale vocals / slow"

    tags.write(song, {tags.GENRE: style})

    assert tags.read(song)[tags.GENRE] == style
    assert tags.GENRE_TEXT not in tags.read(song)


def test_song_info_comes_from_the_file_for_any_source(lib, client):
    add_song(lib, "a")
    tags.write(lib / "a.mp3", {tags.TITLE: "Made", tags.GENRE: "(80s) synthwave\nslow", tags.LYRICS: "la",
                               tags.SUNO_URL: "https://suno.com/song/x", tags.SUNO_MODEL: "chirp-v5",
                               tags.ADDED: "1700000000"})
    add_song(lib, "b")
    tags.write(lib / "b.mp3", {tags.TITLE: "Mine", tags.ALBUM: "Home"})

    made = client.get("/api/info/a").json()
    mine = client.get("/api/info/b").json()

    assert (made["genre"], made["lyrics"], made["suno_model"], made["added"]) == (
        "(80s) synthwave\nslow", "la", "chirp-v5", 1700000000)
    assert (mine["album"], mine["suno_url"], mine["genre"]) == ("Home", "", "")
    assert client.get("/api/info/nope").status_code == 404
    assert client.get("/api/info/..%2Fsolo").status_code == 404
