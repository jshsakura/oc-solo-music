"""가진 곡 파일을 올리는 길을 봅니다. 유튜브 같은 남의 서비스에서 받아 오는 길은 없습니다."""

import shutil
import subprocess

import pytest

from tests.test_file_library import decoded_md5

needs_ffmpeg = pytest.mark.skipif(shutil.which("ffmpeg") is None, reason="ffmpeg 가 없습니다")


def tone(path, *, title="", artist="", seconds=1):
    """짧은 사인파 파일을 만듭니다. 확장자로 형식이 정해집니다. 보관함 폴더 밖(_in)에 만듭니다."""
    path = path.parent / "_in" / path.name
    path.parent.mkdir(exist_ok=True)
    meta = [arg for k, v in (("title", title), ("artist", artist)) if v for arg in ("-metadata", f"{k}={v}")]
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "lavfi", "-i", f"sine=frequency=440:duration={seconds}",
                    *meta, str(path)], check=True)
    return path.read_bytes()


@needs_ffmpeg
def test_uploaded_wav_becomes_an_mp3_track_with_its_tags(lib, client, tmp_path):
    body = tone(tmp_path / "src.wav", title="My Own Song", artist="Me")

    r = client.put("/api/upload", params={"name": "whatever.wav"}, content=body)

    assert r.status_code == 200 and r.json()["added"] is True
    track_id = r.json()["id"]
    assert (lib / f"{track_id}.mp3").is_file()
    track = next(t for t in client.get("/api/tracks").json() if t["id"] == track_id)
    assert (track["title"], track["artist"], track["source"]) == ("My Own Song", "Me", "upload")
    assert track["duration"] == pytest.approx(1, abs=0.2)
    assert not list(lib.glob(".upload-*")) and not list(lib.glob(".up-*"))


@needs_ffmpeg
def test_mp3_is_kept_as_is_and_file_name_is_the_fallback_title(lib, client, tmp_path):
    body = tone(tmp_path / "src.mp3")

    r = client.put("/api/upload", params={"name": "Night Drive.mp3"}, content=body)

    track_id = r.json()["id"]
    assert decoded_md5(lib / f"{track_id}.mp3") == decoded_md5(tmp_path / "_in" / "src.mp3")
    assert next(t for t in client.get("/api/tracks").json() if t["id"] == track_id)["title"] == "Night Drive"


@needs_ffmpeg
def test_same_file_twice_is_added_once(client, tmp_path):
    body = tone(tmp_path / "src.mp3")

    first = client.put("/api/upload", params={"name": "a.mp3"}, content=body).json()
    second = client.put("/api/upload", params={"name": "b.mp3"}, content=body).json()

    assert first["added"] is True and second == {"id": first["id"], "added": False}
    assert len(client.get("/api/tracks").json()) == 1


def test_rejects_unknown_types_and_files_without_audio(lib, client):
    bad_type = client.put("/api/upload", params={"name": "notes.txt"}, content=b"hello")
    not_audio = client.put("/api/upload", params={"name": "fake.mp3"}, content=b"not really audio",
                           headers={"accept-language": "en"})
    empty = client.put("/api/upload", params={"name": "empty.mp3"}, content=b"")

    assert bad_type.status_code == 400 and bad_type.json()["code"] == "upload.bad_type"
    assert not_audio.status_code == 400 and not_audio.json()["code"] == "upload.not_audio"
    assert empty.status_code == 400
    assert client.get("/api/tracks").json() == []
    assert not [p for p in lib.iterdir() if p.name.startswith((".upload-", ".up-"))]


def test_youtube_links_and_endpoints_are_gone(client):
    r = client.post("/api/add", json={"urls": ["https://www.youtube.com/watch?v=AAAAAAAAAAA"]})

    assert r.status_code == 400 and r.json()["code"] == "add.bad_url"
    assert client.get("/api/search", params={"q": "x"}).status_code == 404
    assert client.get("/api/youtube/status").status_code == 404
