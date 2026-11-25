from app import library, suno_record, tags
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


def test_suno_fill_asks_only_for_songs_whose_files_lack_suno_info(lib, monkeypatch):
    add_song(lib, "a")
    add_song(lib, "b")
    add_song(lib, "c")
    library.upsert(lib, "a", title="A", suno_id="sa")
    library.save(lib, "b", {tags.SUNO_ID: "sb", tags.SUNO_CLIP: "{}", tags.LYRICS: "kept"})
    library.upsert(lib, "c", title="C", source="upload")
    asked = []
    monkeypatch.setattr(suno_record, "fetch_clip",
                        lambda cid: asked.append(cid) or {"title": "A", "metadata": {"prompt": "new", "tags": "lofi"}})
    monkeypatch.setattr(suno_record.time, "sleep", lambda s: None)

    assert suno_record.fill_from_suno(lib) == 1

    assert asked == ["sa"]
    assert library.lyrics(lib, "a") == "new" and library.lyrics(lib, "b") == "kept"
    assert tags.read(lib / "a.mp3")[tags.GENRE] == "lofi"
    assert suno_record.fill_from_suno(lib) == 0
