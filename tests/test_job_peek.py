"""녹음을 기다리는 동안에도 데크의 테이프에 제목과 표지가 보이는지 봅니다."""

import time

import app.suno_record

REAL_PEEK_CLIP = app.suno_record.peek_clip  # conftest 가 막기 전의 진짜 함수입니다


def wait_for(check):
    for _ in range(200):
        if check():
            return True
        time.sleep(0.01)
    return False


def test_queued_suno_job_gets_title_and_cover_before_recording(lib, client, monkeypatch):
    import app.main as main

    async def hold(job):  # 녹음은 시작하지 않고 붙잡아 둡니다
        main.persist(job, status="recording", progress=0.0)

    def fake_peek(url, cover):
        cover.write_bytes(b"\xff\xd8 jpeg")
        return {"title": "My Own Song", "cover": True, "duration": 201.5}

    monkeypatch.setattr(main, "record", hold)
    monkeypatch.setattr(app.suno_record, "peek_clip", fake_peek)

    client.post("/api/add", json={"urls": ["https://suno.com/s/AAAA0000"]})

    assert wait_for(lambda: client.get("/api/jobs").json()[0].get("cover"))
    job = client.get("/api/jobs").json()[0]
    assert job["title"] == "My Own Song"
    assert job["duration"] == 201.5
    r = client.get(f"/api/jobs/{job['id']}/cover")
    assert r.status_code == 200 and r.content.startswith(b"\xff\xd8")


def test_finished_job_drops_its_preview_cover(lib, client):
    import app.main as main

    job = {"id": "a" * 12, "kind": "suno", "key": "k", "url": "", "status": "recording", "detail": "", "title": ""}
    main.job_cover(job["id"]).write_bytes(b"x")

    main.persist(job, status="done")

    assert not main.job_cover(job["id"]).exists()
    assert client.get(f"/api/jobs/{job['id']}/cover").status_code == 404


def test_job_cover_rejects_odd_ids(client):
    assert client.get("/api/jobs/..%2Fsolo/cover").status_code == 404


def test_peek_clip_reads_duration_and_skips_missing(tmp_path, monkeypatch):
    clips = iter([{"title": "A", "metadata": {"duration": "201.5"}}, {"title": "B", "metadata": {}}])
    monkeypatch.setattr(app.suno_record, "fetch_clip", lambda clip_id: next(clips))
    monkeypatch.setattr(app.suno_record, "save_cover", lambda target, url: None)
    url = "https://suno.com/song/00000000-0000-0000-0000-000000000000"

    assert REAL_PEEK_CLIP(url, tmp_path / "c.jpg")["duration"] == 201.5
    assert "duration" not in REAL_PEEK_CLIP(url, tmp_path / "c.jpg")
