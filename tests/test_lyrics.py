from app import library, suno_record
from tests.conftest import add_song


def test_song_with_lyrics_reports_them_and_serves_the_text(lib, client):
    add_song(lib, "a")
    library.upsert(lib, "a", title="A", suno_id="x", lyrics="[Verse]\nfirst line\nsecond line")

    track = client.get("/api/tracks").json()[0]
    body = client.get("/api/lyrics/a").json()

    assert track["lyrics"] is True
    assert body == {"lyrics": "[Verse]\nfirst line\nsecond line"}


def test_song_without_lyrics_says_so(lib, client):
    add_song(lib, "a")
    library.upsert(lib, "a", title="A", suno_id="x", lyrics="")

    assert client.get("/api/tracks").json()[0]["lyrics"] is False
    assert client.get("/api/lyrics/a").json() == {"lyrics": ""}


def test_lyrics_of_unknown_or_escaping_ids_are_404(client):
    assert client.get("/api/lyrics/nope").status_code == 404
    assert client.get("/api/lyrics/..%2Fsolo").status_code == 404


def test_updating_song_info_keeps_lyrics_fetched_earlier(lib, client):
    add_song(lib, "a")
    library.upsert(lib, "a", title="A", suno_id="x", lyrics="la la")
    library.upsert(lib, "a", title="A again", suno_id="x")

    assert client.get("/api/lyrics/a").json() == {"lyrics": "la la"}


def test_instrumental_clip_has_no_lyrics():
    clip = {"metadata": {"make_instrumental": True, "prompt": "ignored"}}

    assert suno_record.lyrics_of(clip) == ""
    assert suno_record.lyrics_of({"metadata": {"prompt": " words \n"}}) == "words"
    assert suno_record.lyrics_of({}) == ""


def test_backfill_fills_only_songs_not_checked_yet(lib, monkeypatch):
    add_song(lib, "a")
    add_song(lib, "b")
    add_song(lib, "c")
    library.upsert(lib, "a", title="A", suno_id="sa")
    library.upsert(lib, "b", title="B", suno_id="sb", lyrics="kept")
    library.upsert(lib, "c", title="C", source="upload")
    asked = []
    monkeypatch.setattr(suno_record, "fetch_clip", lambda cid: asked.append(cid) or {"metadata": {"prompt": "new"}})
    monkeypatch.setattr(suno_record.time, "sleep", lambda s: None)

    assert suno_record.backfill_lyrics(lib) == 1

    assert asked == ["sa"]
    with library.connect(lib) as db:
        got = dict(db.execute("SELECT id, lyrics FROM tracks").fetchall())
    assert got == {"a": "new", "b": "kept", "c": None}
