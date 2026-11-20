import importlib
import shutil
from pathlib import Path

import pytest
from fastapi.testclient import TestClient


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
