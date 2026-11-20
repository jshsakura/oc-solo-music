import base64
import time

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from app import auth
from tests.conftest import make_client

TEAM = "team.example.com"
AUD = "a" * 64


def basic(password):
    return {"authorization": "Basic " + base64.b64encode(f"solo:{password}".encode()).decode()}


def pair(c, headers=None):
    code = c.post("/api/pair", headers=headers or {}).json()["code"]
    return c.post("/api/pair/claim", json={"code": code, "name": "Pixel", "platform": "android"}).json()


def test_open_server_treats_everyone_as_owner(client):
    assert client.get("/api/me").json()["via"] == "open"


def test_password_guards_the_api_and_the_page(lib, monkeypatch):
    with make_client(lib, monkeypatch, password="pw") as c:
        assert c.get("/api/tracks").status_code == 401
        assert c.get("/").status_code == 401
        assert c.get("/healthz").status_code == 200
        assert c.get("/api/me", headers=basic("pw")).json() == {"via": "password", "owner": True, "email": "", "device": ""}


def test_qr_pairing_gives_the_app_a_working_device_token(lib, monkeypatch):
    with make_client(lib, monkeypatch, password="pw") as c:
        res = c.post("/api/pair", headers=basic("pw")).json()
        assert res["uri"].startswith("solo://pair?server=")
        device = c.post("/api/pair/claim", json={"code": res["code"], "name": "Pixel", "platform": "android"}).json()
        bearer = {"authorization": "Bearer " + device["token"]}

        assert c.get("/api/tracks", headers=bearer).status_code == 200
        me = c.get("/api/me", headers=bearer).json()
        assert me["via"] == "device" and me["owner"] is False
        assert [d["name"] for d in c.get("/api/devices", headers=basic("pw")).json()] == ["Pixel"]


def test_a_pair_code_works_once(lib, monkeypatch):
    with make_client(lib, monkeypatch) as c:
        code = c.post("/api/pair").json()["code"]
        assert c.post("/api/pair/claim", json={"code": code}).status_code == 200
        again = c.post("/api/pair/claim", json={"code": code})
    assert again.status_code == 400 and again.json()["code"] == "pair.invalid"


def test_an_expired_pair_code_is_refused(lib):
    code, _ = auth.new_pair_code(lib, now=1000.0)
    assert auth.claim_pair_code(lib, code, "x", "", now=1000.0 + auth.PAIR_TTL + 1) is None


def test_tokens_are_stored_only_as_hashes(lib):
    code, _ = auth.new_pair_code(lib)
    device = auth.claim_pair_code(lib, code, "x", "")
    raw = (lib / "solo.db").read_bytes()
    assert device["token"].encode() not in raw and code.encode() not in raw


def test_a_device_cannot_manage_devices_and_a_removed_one_is_locked_out(lib, monkeypatch):
    with make_client(lib, monkeypatch, password="pw") as c:
        device = pair(c, basic("pw"))
        bearer = {"authorization": "Bearer " + device["token"]}
        assert c.post("/api/pair", headers=bearer).status_code == 403
        assert c.delete(f"/api/devices/{device['id']}", headers=basic("pw")).status_code == 200
        assert c.get("/api/tracks", headers=bearer).status_code == 401


@pytest.fixture
def access(monkeypatch):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    jwk = jwt.algorithms.RSAAlgorithm.to_jwk(key.public_key(), as_dict=True) | {"kid": "k1"}
    verifier = auth.AccessVerifier(TEAM, AUD, fetch=lambda: {"keys": [jwk]})

    def token(aud=AUD, exp=None):
        claims = {"aud": aud, "iss": f"https://{TEAM}", "email": "owner@example.com",
                  "exp": exp or int(time.time()) + 600}
        return jwt.encode(claims, key, algorithm="RS256", headers={"kid": "k1"})

    return verifier, token


def test_access_login_cookie_is_checked_on_api_calls(lib, monkeypatch, access):
    verifier, token = access
    with make_client(lib, monkeypatch) as c:
        import app.main as main
        monkeypatch.setattr(main, "ACCESS", verifier)
        assert c.get("/api/tracks").status_code == 401
        c.cookies.set("CF_Authorization", token())
        me = c.get("/api/me").json()
    assert me == {"via": "access", "owner": True, "email": "owner@example.com", "device": ""}


def test_access_rejects_a_token_for_another_app_or_an_expired_one(access):
    verifier, token = access
    assert verifier.email(token(aud="b" * 64)) is None
    assert verifier.email(token(exp=int(time.time()) - 10)) is None
    assert verifier.email("not-a-jwt") is None


def test_with_access_the_page_itself_is_left_to_access(lib, monkeypatch, access):
    verifier, _ = access
    with make_client(lib, monkeypatch) as c:
        import app.main as main
        monkeypatch.setattr(main, "ACCESS", verifier)
        assert c.get("/").status_code == 200
        assert c.get("/api/app").status_code == 401
