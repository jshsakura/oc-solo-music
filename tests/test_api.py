import base64

from app import library
from tests.conftest import add_song, make_client


def test_new_mp3_appears_with_title_from_file_name(lib, client):
    add_song(lib, "rain-on-the-window")

    tracks = client.get("/api/tracks").json()

    assert [t["title"] for t in tracks] == ["Rain On The Window"]
    assert tracks[0]["liked"] is False and tracks[0]["cover"] is False


def test_recorder_metadata_wins_over_file_name(lib, client):
    add_song(lib, "a")
    library.upsert(lib, "a", title="Real Title", artist="Someone", duration=12.5, suno_id="x")

    track = client.get("/api/tracks").json()[0]

    assert (track["title"], track["artist"], track["duration"]) == ("Real Title", "Someone", 12.5)


def test_track_list_answers_304_when_unchanged(lib, client):
    add_song(lib, "a")
    etag = client.get("/api/tracks").headers["etag"]

    assert client.get("/api/tracks", headers={"If-None-Match": etag}).status_code == 304
    add_song(lib, "b")
    assert client.get("/api/tracks", headers={"If-None-Match": etag}).status_code == 200


def test_like_toggles_and_survives_reload(lib, client):
    add_song(lib, "a")
    client.get("/api/tracks")

    assert client.post("/api/like/a").json() == {"liked": True}
    assert client.get("/api/tracks").json()[0]["liked"] is True
    assert client.post("/api/like/a").json() == {"liked": False}


def test_removing_a_song_keeps_its_files_in_archive(lib, client):
    add_song(lib, "a")
    (lib / "a.jpg").write_bytes(b"jpg")
    client.get("/api/tracks")

    assert client.delete("/api/tracks/a").status_code == 200

    assert client.get("/api/tracks").json() == []
    assert (lib / "archive" / "a.mp3").exists() and (lib / "archive" / "a.jpg").exists()
    assert [t["id"] for t in client.get("/api/archive").json()] == ["a"]


def test_archived_song_can_be_restored_with_its_likes(lib, client):
    add_song(lib, "a")
    client.get("/api/tracks")
    client.post("/api/like/a")
    client.delete("/api/tracks/a")

    assert client.post("/api/archive/a/restore").status_code == 200

    tracks = client.get("/api/tracks").json()
    assert [(t["id"], t["liked"]) for t in tracks] == [("a", True)]
    assert (lib / "a.mp3").exists() and not (lib / "archive" / "a.mp3").exists()
    assert client.get("/api/archive").json() == []


def test_restore_rejects_unknown_or_escaping_ids(client):
    assert client.post("/api/archive/nope/restore").status_code == 404
    assert client.post("/api/archive/..%2Fx/restore").status_code in (404, 405)


def test_file_moved_by_hand_follows_its_folder(lib, client):
    add_song(lib, "a")
    client.get("/api/tracks")
    (lib / "archive").mkdir()
    (lib / "a.mp3").rename(lib / "archive" / "a.mp3")

    assert client.get("/api/tracks").json() == []
    assert [t["id"] for t in client.get("/api/archive").json()] == ["a"]


def test_file_deleted_outside_app_drops_from_list(lib, client):
    add_song(lib, "a")
    client.get("/api/tracks")
    (lib / "a.mp3").unlink()

    assert client.get("/api/tracks").json() == []


def test_audio_supports_range_requests(lib, client):
    add_song(lib, "a", size=1000)

    r = client.get("/api/audio/a", headers={"Range": "bytes=0-1"})

    assert r.status_code == 206 and r.content == b"\xff\xfb"
    assert r.headers["content-range"] == "bytes 0-1/1000"


def test_unknown_or_escaping_ids_are_404(lib, client):
    (lib.parent / "secret.mp3").write_bytes(b"x")

    assert client.get("/api/audio/nope").status_code == 404
    assert client.get("/api/audio/..%2Fsecret").status_code == 404
    assert client.get("/api/cover/..%2Fsecret").status_code == 404


def test_add_rejects_non_suno_urls(client):
    r = client.post("/api/add", json={"urls": ["https://example.com/song/1"]})

    assert r.status_code == 400


def test_old_json_sidecar_and_likes_are_imported_once(lib, client):
    add_song(lib, "a")
    (lib / "a.json").write_text('{"title": "From Json", "artist": "Me"}')
    (lib / ".likes.json").write_text('["a"]')

    track = client.get("/api/tracks").json()[0]

    assert (track["title"], track["liked"]) == ("From Json", True)
    assert not (lib / "a.json").exists() and not (lib / ".likes.json").exists()


def test_password_guards_everything_but_health(lib, monkeypatch):
    with make_client(lib, monkeypatch, password="hunter2") as c:
        good = "Basic " + base64.b64encode(b"any:hunter2").decode()
        bad = "Basic " + base64.b64encode(b"any:nope").decode()

        assert c.get("/healthz").status_code == 200
        assert c.get("/").status_code == 401
        assert c.get("/api/tracks", headers={"Authorization": bad}).status_code == 401
        assert c.get("/api/tracks", headers={"Authorization": good}).status_code == 200


def test_index_fills_absolute_og_image_url(client):
    html = client.get("/", headers={"Host": "music.example.com", "X-Forwarded-Proto": "https"}).text

    assert 'content="https://music.example.com/og-image.png"' in html
    assert "{{origin}}" not in html


def test_index_escapes_hostile_host_header(client):
    page = client.get("/", headers={"Host": 'x"><script>alert(1)</script>'}).text

    assert "<script>alert(1)" not in page


def test_queued_and_recording_jobs_can_be_canceled(lib, monkeypatch):
    import asyncio
    from tests.conftest import make_client

    with make_client(lib, monkeypatch) as c:
        import app.main as main
        started = []

        async def fake_record(job):
            job["status"] = "recording"; started.append(job["id"])
            while job["status"] == "recording":
                await asyncio.sleep(0.01)

        monkeypatch.setattr(main, "record", fake_record)
        urls = ["https://suno.com/s/AAAA0000", "https://suno.com/s/BBBB1111"]
        c.post("/api/add", json={"urls": urls})
        for _ in range(100):
            if started:
                break
            import time; time.sleep(0.01)
        jobs = {j["url"]: j for j in c.get("/api/jobs").json()}
        first, second = jobs[urls[0]], jobs[urls[1]]
        assert (first["status"], second["status"]) == ("recording", "queued")

        assert c.post(f"/api/jobs/{second['id']}/cancel").status_code == 200
        assert c.post(f"/api/jobs/{first['id']}/cancel").status_code == 200

        statuses = {j["url"]: j["status"] for j in c.get("/api/jobs").json()}
        assert statuses == {urls[0]: "canceled", urls[1]: "canceled"}
        assert c.post(f"/api/jobs/{first['id']}/cancel").status_code == 409
        assert c.post("/api/jobs/nope/cancel").status_code == 404


def test_download_names_file_after_artist_and_title(lib, client):
    from app import library

    add_song(lib, "a")
    library.upsert(lib, "a", title='Night/Drive: "1"', artist="Solo", source="suno")

    response = client.get("/api/download/a")

    assert response.status_code == 200
    from urllib.parse import unquote

    disposition = unquote(response.headers["content-disposition"])
    assert disposition.startswith("attachment") and disposition.endswith("Solo - Night Drive 1.mp3")


def test_download_of_unknown_track_is_404(client):
    assert client.get("/api/download/nope").status_code == 404


def test_job_progress_lines_update_the_job_while_it_runs(lib, client, monkeypatch):
    import asyncio

    import app.main as main

    monkeypatch.setattr(main, "job_command", lambda job: ["tests.fake_job"])
    job = {"id": "j", "kind": "suno", "title": "", "url": "", "status": "queued"}

    asyncio.run(main.record(job))

    assert job["progress"] == 0.5
    assert job["status"] == "failed" and "잡담 한 줄" in job["detail"]


def test_job_history_survives_a_restart_and_unfinished_jobs_are_queued_again(lib, monkeypatch):
    import asyncio
    import importlib

    import app.main

    library.save_job(lib, {"id": "old", "kind": "suno", "key": "k1", "url": "", "status": "done", "detail": "ok", "title": "A"}, 50)
    library.save_job(lib, {"id": "cut", "kind": "youtube", "key": "k2", "url": "", "status": "downloading", "detail": "", "title": "B"}, 50)
    main = importlib.reload(app.main)
    main.queues.update(suno=asyncio.Queue(), youtube=asyncio.Queue())

    main.restore_jobs()

    assert {j["id"]: j["status"] for j in main.jobs} == {"old": "done", "cut": "queued"}
    assert main.queues["youtube"].qsize() == 1 and main.queues["suno"].qsize() == 0
    assert {j["id"]: j["status"] for j in library.load_jobs(lib)} == {"old": "done", "cut": "queued"}


def test_stopping_a_youtube_job_keeps_the_other_jobs_temp_folders(lib, client):
    import app.main as main

    (lib / ".yt-AAAAAAAAAA1").mkdir()
    (lib / ".yt-BBBBBBBBBB2").mkdir()
    (lib / ".recording-x").mkdir()

    class Gone:
        pid = 2 ** 22 + 12345  # 없는 프로세스 그룹

    main.stop_recorder(Gone(), {"kind": "youtube", "key": "AAAAAAAAAA1"})

    assert not (lib / ".yt-AAAAAAAAAA1").exists()
    assert (lib / ".yt-BBBBBBBBBB2").exists() and (lib / ".recording-x").exists()


def test_malformed_progress_line_is_not_read_as_progress():
    import app.main as main

    assert main.PROGRESS_LINE.match("[progress] 0.42")
    assert not main.PROGRESS_LINE.match("[progress] .")
    assert not main.PROGRESS_LINE.match("[progress] 1.2.3")
