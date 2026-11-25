import importlib
import shutil
from pathlib import Path

import pytest
from fastapi.testclient import TestClient


@pytest.fixture(autouse=True)
def no_suno_lookup(monkeypatch):
    """테스트가 진짜 수노에 곡 정보를 묻지 않게 막습니다. 필요한 테스트는 따로 바꿔 끼웁니다."""
    import app.suno_record

    def offline(url, cover):
        raise OSError("offline in tests")

    def no_clip(clip_id):
        raise OSError("offline in tests")

    monkeypatch.setattr(app.suno_record, "peek_clip", offline)
    monkeypatch.setattr(app.suno_record, "fetch_clip", no_clip)


@pytest.fixture
def lib(tmp_path, monkeypatch):
    monkeypatch.setenv("SOLO_LIB", str(tmp_path))
    monkeypatch.delenv("SOLO_PASSWORD", raising=False)
    web = tmp_path / "_web"
    web.mkdir()
    shutil.copy(Path(__file__).parent.parent / "client" / "web" / "index.html", web)
    monkeypatch.setenv("SOLO_WEB", str(web))
    monkeypatch.setenv("SOLO_APK_DIR", str(tmp_path / "_apk"))
    return tmp_path


def make_client(lib, monkeypatch, password=""):
    if password:
        monkeypatch.setenv("SOLO_PASSWORD", password)
    import app.main
    module = importlib.reload(app.main)
    return TestClient(module.app)


@pytest.fixture
def client(lib, monkeypatch):
    with make_client(lib, monkeypatch) as c:
        yield c


def add_song(lib, stem, size=2048):
    (lib / f"{stem}.mp3").write_bytes(b"\xff\xfb" + b"\0" * (size - 2))
