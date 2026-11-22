"""수노 공유 주소가 곡이 아니라 훅(짧은 영상)으로 가도 원래 곡을 찾는지 봅니다."""

import pytest

from app import suno_record

SONG = "11111111-2222-3333-4444-555555555555"
HOOK = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"


def test_song_link_gives_its_id():
    assert suno_record.clip_id_from_url(f"https://suno.com/song/{SONG}") == SONG


def test_hook_link_gives_the_original_song(monkeypatch):
    asked = []

    def fake_hook(hook_id):
        asked.append(hook_id)
        return {"id": hook_id, "original_clip_id": SONG}

    monkeypatch.setattr(suno_record, "fetch_hook", fake_hook)

    assert suno_record.clip_id_from_url(f"https://suno.com/hook/{HOOK}") == SONG
    assert asked == [HOOK]
    assert suno_record.song_url(SONG) == f"https://suno.com/song/{SONG}"


def test_other_pages_are_rejected():
    with pytest.raises(ValueError):
        suno_record.clip_id_from_url("https://suno.com/playlist/x")


def test_hook_links_are_accepted_as_input(client, monkeypatch):
    import app.main as main

    async def no_record(job):  # 진짜 녹음은 띄우지 않습니다
        main.persist(job, status="done")

    monkeypatch.setattr(main, "record", no_record)
    assert suno_record.validate_url(f"https://suno.com/hook/{HOOK}")
    r = client.post("/api/add", json={"urls": [f"https://suno.com/hook/{HOOK}"]})
    assert r.status_code == 200


def test_silence_at_the_same_second_in_both_takes_is_part_of_the_song():
    from app.suno_record import unexplained

    # 두 번 녹음해 같은 초에 무음이 있으면 곡의 브레이크이고, 다른 자리면 재생이 끊긴 것입니다.
    assert unexplained([61.2, 122.4], [61.3, 122.4]) == []
    assert unexplained([61.2, 90.0], [61.2]) == [90.0]
    assert unexplained([10.0], []) == [10.0]
