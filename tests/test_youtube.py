"""유튜브 연동 검사. 유튜브에는 요청하지 않고, 바깥과 닿는 함수만 바꿔 끼웁니다."""

import stat
import time

import pytest

from app import youtube
from tests.conftest import make_client

COOKIES = "\n".join([
    "# Netscape HTTP Cookie File",
    ".youtube.com\tTRUE\t/\tTRUE\t0\tSAPISID\tAAAA0000",
    "#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tBBBB1111",
    ".example.com\tTRUE\t/\tTRUE\t0\tsession\tnot-for-google",
])
TRACK = {"videoId": "AAAAAAAAAA1", "title": "Song", "artist": "Band", "album": "LP", "duration": 200, "art": ""}


@pytest.fixture
def yt(lib, monkeypatch):
    """받기 프로세스 대신 곡 상태만 바꾸는 가짜를 끼운 서버."""
    with make_client(lib, monkeypatch) as c:
        import app.main as main

        async def fake_record(job):
            job["status"] = "done"

        monkeypatch.setattr(main, "record", fake_record)
        monkeypatch.setattr(main, "YOUTUBE_GAP_SECONDS", 0)
        yield c, main


def wait_jobs(c, until):
    for _ in range(100):
        jobs = c.get("/api/jobs").json()
        if until(jobs):
            return jobs
        time.sleep(0.01)
    return c.get("/api/jobs").json()


def test_m4a_from_youtube_is_listed_and_served_as_mp4(lib, client):
    (lib / "yt-AAAAAAAAAA1.m4a").write_bytes(b"\0" * 1024)
    youtube_track = client.get("/api/tracks").json()[0]

    response = client.get(f"/api/audio/{youtube_track['id']}")

    assert youtube_track["id"] == "yt-AAAAAAAAAA1"
    assert response.headers["content-type"] == "audio/mp4"


def test_search_marks_songs_already_in_library(lib, yt, monkeypatch):
    c, _ = yt
    (lib / "yt-AAAAAAAAAA1.m4a").write_bytes(b"\0")
    other = {**TRACK, "videoId": "BBBBBBBBBB2"}
    monkeypatch.setattr(youtube, "search", lambda q, cookies: {"music": True, "tracks": [dict(TRACK), other]})

    found = c.get("/api/search", params={"q": "band"}).json()

    assert [(t["videoId"], t["owned"]) for t in found["tracks"]] == [("AAAAAAAAAA1", True), ("BBBBBBBBBB2", False)]


def test_youtube_link_queues_each_new_song_once(lib, yt, monkeypatch):
    c, _ = yt
    (lib / "yt-AAAAAAAAAA1.m4a").write_bytes(b"\0")
    songs = [dict(TRACK), {**TRACK, "videoId": "BBBBBBBBBB2", "title": "New"}]
    monkeypatch.setattr(youtube, "resolve", lambda url, cookies: songs)

    added = c.post("/api/add", json={"urls": ["https://www.youtube.com/playlist?list=PLxxxx"]}).json()

    jobs = wait_jobs(c, lambda js: js and all(j["status"] == "done" for j in js))
    assert added == {"queued": 1}
    assert [(j["kind"], j["title"], j["status"]) for j in jobs] == [("youtube", "New", "done")]


def test_search_result_can_be_queued_directly(yt):
    c, main = yt

    assert c.post("/api/youtube/get", json=TRACK).json() == {"queued": 1}
    assert c.post("/api/youtube/get", json={**TRACK, "videoId": "../../etc/pa"}).status_code == 400
    command = main.job_command({"kind": "youtube", "track": TRACK, "url": ""})
    assert command[0] == "app.youtube_get" and '"videoId": "AAAAAAAAAA1"' in command[1]


def test_rejects_links_that_are_neither_suno_nor_youtube(client):
    assert client.post("/api/add", json={"urls": ["https://example.com/song"]}).status_code == 400


def test_cookie_upload_keeps_only_google_cookies_and_is_private(lib, client):
    assert client.get("/api/youtube/status").json() == {"cookies": False, "loggedIn": False}

    status = client.put("/api/youtube/cookies", content=COOKIES).json()

    saved = youtube.cookies_path(lib)
    assert status == {"cookies": True, "loggedIn": True}
    assert "example.com" not in saved.read_text() and "SID\tBBBB1111" in saved.read_text()
    assert stat.S_IMODE(saved.stat().st_mode) == 0o600
    assert client.delete("/api/youtube/cookies").json()["cookies"] is False


def test_cookie_upload_without_login_is_rejected(lib, client):
    logged_out = COOKIES.replace("SAPISID", "PREF")

    assert client.put("/api/youtube/cookies", content=logged_out).status_code == 400
    assert not youtube.cookies_path(lib).exists()


def test_youtube_music_and_ytdlp_results_share_one_shape():
    music = youtube.from_ytmusic({"videoId": "AAAAAAAAAA1", "title": "Song", "artists": [{"name": "A"}, {"name": "B"}],
                                  "album": {"name": "LP"}, "duration": "3:20",
                                  "thumbnails": [{"url": "s", "width": 60}, {"url": "big", "width": 544}]})
    plain = youtube.from_ytdlp({"id": "AAAAAAAAAA1", "title": "Song", "uploader": "Band - Topic", "duration": 200.0})

    assert music == {"videoId": "AAAAAAAAAA1", "title": "Song", "artist": "A, B", "album": "LP", "duration": 200, "art": "big"}
    assert plain["artist"] == "Band" and plain["duration"] == 200
    assert youtube.from_ytdlp({"id": "UCchannel-id-is-longer"}) is None


def test_download_errors_are_shown_in_plain_words():
    from app.youtube_get import friendly

    assert friendly(Exception("ERROR: [youtube] AAAAAAAAAA1: Requested format is not available. Use --list-formats")) == {"code": "youtube.format_unavailable", "args": {}}
    assert friendly(Exception("ERROR: [youtube] AAAAAAAAAA1: something new\ntrace")) == "something new"


def test_progress_follows_bytes_then_holds_at_95_while_converting():
    from app.youtube_get import progress_of

    assert progress_of({"status": "downloading", "downloaded_bytes": 50, "total_bytes": 100}) == 0.45
    assert progress_of({"status": "finished"}) == 0.95
    assert progress_of({"status": "downloading"}) is None


def test_cover_is_only_fetched_from_youtube_image_hosts(tmp_path, monkeypatch):
    import app.youtube_get as yg

    opened = []
    monkeypatch.setattr(yg.urllib.request, "urlopen", lambda *a, **k: opened.append(a) or (_ for _ in ()).throw(OSError()))

    yg.save_cover("https://192.0.2.1/x.jpg", tmp_path / "c.jpg")
    yg.save_cover("https://example.com/x.jpg", tmp_path / "c.jpg")
    yg.save_cover("https://i.ytimg.com/vi/AAAAAAAAAA1/hqdefault.jpg", tmp_path / "c.jpg")

    assert len(opened) == 1
