"""누가 들어왔는지 가립니다.

세 가지 길이 있습니다.
- 웹: Cloudflare Access(구글 로그인)가 앞에 섭니다. /api 는 Access 를 우회하므로 Access 가 남긴
  CF_Authorization 쿠키(또는 Cf-Access-Jwt-Assertion 헤더)의 서명을 여기서 직접 확인합니다.
- 앱: 웹에서 QR 로 짝지은 기기 토큰을 `Authorization: Bearer` 로 보냅니다. DB 에는 토큰의 해시만 둡니다.
- 집 안: SOLO_PASSWORD 를 HTTP Basic 으로 보냅니다. 아무것도 설정하지 않으면 인증 없이 엽니다.
"""

from __future__ import annotations

import base64
import hashlib
import json
import secrets
import sqlite3
import threading
import time
import urllib.request
from dataclasses import dataclass
from pathlib import Path

import jwt

PAIR_TTL = 300  # QR 하나가 살아 있는 시간(초)
ACCESS_KEYS_TTL = 3600

DEVICES_SCHEMA = """
CREATE TABLE IF NOT EXISTS devices (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    platform   TEXT NOT NULL DEFAULT '',
    token_hash TEXT NOT NULL UNIQUE,
    created    REAL NOT NULL,
    last_seen  REAL
);
CREATE TABLE IF NOT EXISTS pair_codes (
    code_hash TEXT PRIMARY KEY,
    expires   REAL NOT NULL
);
"""


@dataclass(frozen=True)
class Who:
    """요청을 보낸 쪽입니다. owner 만 기기를 짝짓고 지울 수 있습니다."""
    via: str            # access | device | password | open
    owner: bool
    email: str = ""
    device_id: str = ""


def _hash(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def _db(lib: Path) -> sqlite3.Connection:
    db = sqlite3.connect(lib / "solo.db")
    db.row_factory = sqlite3.Row
    db.executescript(DEVICES_SCHEMA)
    return db


# ── 짝짓기 ──────────────────────────────────────────────────────────────

def new_pair_code(lib: Path, now: float | None = None) -> tuple[str, float]:
    """QR 에 담을 1회용 코드입니다. 화면에 오래 떠 있어도 짧게 살고 한 번 쓰면 사라집니다."""
    now = time.time() if now is None else now
    code = secrets.token_urlsafe(18)
    expires = now + PAIR_TTL
    with _db(lib) as db:
        db.execute("DELETE FROM pair_codes WHERE expires < ?", (now,))
        db.execute("INSERT INTO pair_codes (code_hash, expires) VALUES (?, ?)", (_hash(code), expires))
    return code, expires


def claim_pair_code(lib: Path, code: str, name: str, platform: str, now: float | None = None) -> dict | None:
    """코드를 기기 토큰으로 바꿉니다. 코드가 없거나 지났으면 None 입니다."""
    now = time.time() if now is None else now
    with _db(lib) as db:
        row = db.execute("DELETE FROM pair_codes WHERE code_hash=? RETURNING expires", (_hash(code),)).fetchone()
        if row is None or row["expires"] < now:
            return None
        token = secrets.token_urlsafe(32)
        device = {
            "id": secrets.token_hex(8),
            "name": (name.strip() or "Device")[:60],
            "platform": platform.strip()[:20],
            "created": now,
        }
        db.execute(
            "INSERT INTO devices (id, name, platform, token_hash, created) VALUES (?, ?, ?, ?, ?)",
            (device["id"], device["name"], device["platform"], _hash(token), now),
        )
    return {**device, "token": token}


def list_devices(lib: Path) -> list[dict]:
    with _db(lib) as db:
        rows = db.execute("SELECT id, name, platform, created, last_seen FROM devices ORDER BY created DESC")
        return [dict(r) for r in rows]


def remove_device(lib: Path, device_id: str) -> bool:
    with _db(lib) as db:
        return db.execute("DELETE FROM devices WHERE id=?", (device_id,)).rowcount > 0


def device_for_token(lib: Path, token: str, now: float | None = None) -> str | None:
    now = time.time() if now is None else now
    with _db(lib) as db:
        row = db.execute("SELECT id, last_seen FROM devices WHERE token_hash=?", (_hash(token),)).fetchone()
        if row is None:
            return None
        if not row["last_seen"] or now - row["last_seen"] > 60:
            db.execute("UPDATE devices SET last_seen=? WHERE id=?", (now, row["id"]))
        return row["id"]


# ── Cloudflare Access ──────────────────────────────────────────────────

class AccessVerifier:
    """Access 가 서명한 JWT 를 팀의 공개키로 확인합니다. 키는 한 시간 붙들고 있다가 다시 받습니다."""

    def __init__(self, team: str, aud: str, fetch=None):
        self.team = team.removeprefix("https://").rstrip("/")
        self.aud = aud
        self._fetch = fetch or self._fetch_certs
        self._keys: dict[str, object] = {}
        self._at = 0.0
        self._lock = threading.Lock()

    def _fetch_certs(self) -> dict:
        with urllib.request.urlopen(f"https://{self.team}/cdn-cgi/access/certs", timeout=10) as res:
            return json.load(res)

    def _keyset(self, refresh: bool = False) -> dict[str, object]:
        with self._lock:
            if refresh or not self._keys or time.time() - self._at > ACCESS_KEYS_TTL:
                data = self._fetch()
                self._keys = {k["kid"]: jwt.PyJWK(k).key for k in data.get("keys", [])}
                self._at = time.time()
            return self._keys

    def email(self, token: str) -> str | None:
        """서명, 대상(aud), 발급처, 만료가 맞으면 이메일을, 아니면 None 을 돌려줍니다."""
        try:
            kid = jwt.get_unverified_header(token).get("kid", "")
            key = self._keyset().get(kid) or self._keyset(refresh=True).get(kid)
            if key is None:
                return None
            claims = jwt.decode(token, key, algorithms=["RS256"], audience=self.aud,
                                issuer=f"https://{self.team}")
        except (jwt.PyJWTError, OSError, ValueError, KeyError):
            return None
        return str(claims.get("email") or claims.get("sub") or "")


def password_ok(header: str, password: str) -> bool:
    scheme, _, value = header.partition(" ")
    if scheme.lower() != "basic" or not password:
        return False
    try:
        _, _, given = base64.b64decode(value).decode().partition(":")
    except (ValueError, UnicodeDecodeError):
        return False
    return secrets.compare_digest(given.encode(), password.encode())


def identify(*, lib: Path, authorization: str, access_token: str, password: str,
             access: AccessVerifier | None) -> Who | None:
    """요청 하나를 누구로 볼지 정합니다. 아무 인증도 설정하지 않았으면 owner 로 엽니다."""
    scheme, _, value = authorization.partition(" ")
    if scheme.lower() == "bearer" and value:
        device = device_for_token(lib, value.strip())
        if device:
            return Who(via="device", owner=False, device_id=device)
    if access and access_token:
        email = access.email(access_token)
        if email is not None:
            return Who(via="access", owner=True, email=email)
    if password and password_ok(authorization, password):
        return Who(via="password", owner=True)
    if not password and access is None:
        return Who(via="open", owner=True)
    return None
