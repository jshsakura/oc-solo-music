"""본인 수노 곡의 브라우저 재생을 실시간으로 녹음해 MP3 로 저장합니다.

암호화된 원본 파일이나 해독 키는 다루지 않고, 쿠키도 쓰지 않습니다.
플레이어가 비로그인 상태에서 재생하는 소리만 녹음합니다.
"""
import argparse
import asyncio
import base64
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit

import numpy as np

from . import library
from .messages import msg, pick_language, render, to_wire

SAMPLE_RATE = 48000
DURATION_TOLERANCE_SEC = 0.5
PAGE_SETTLE_MS = 5000
PLAY_SETTLE_MS = 6000
MAX_RECORD_MARGIN_SEC = 60
CLIP_API = "https://studio-api.prod.suno.com/api/clip/"
HOOK_API = "https://studio-api.prod.suno.com/api/video/hooks/"
USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/130.0 Safari/537.36"
)
UUID_RE = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"

RECORD_JS = """async () => {
  const a = [...document.querySelectorAll('audio')].find(x => x.currentSrc.startsWith('blob:'));
  if (!a) return {error: 'no audio element'};
  a.pause(); a.loop = false; a.currentTime = 0;
  await new Promise(r => setTimeout(r, 1500));
  let stalls = 0;
  a.addEventListener('waiting', () => stalls++);
  const stream = new MediaStream(a.captureStream().getAudioTracks());
  const rec = new MediaRecorder(stream, {mimeType: 'audio/webm;codecs=opus', audioBitsPerSecond: 510000});
  rec.ondataavailable = async e => {
    if (!e.data.size) return;
    const b = new Uint8Array(await e.data.arrayBuffer());
    let s = '';
    for (let i = 0; i < b.length; i += 8192) s += String.fromCharCode(...b.subarray(i, i + 8192));
    await window.__chunk(btoa(s));
  };
  const stopped = new Promise(r => rec.onstop = r);
  rec.start(1000);
  await a.play();
  const duration = a.duration;
  await new Promise(r => {
    a.addEventListener('ended', r, {once: true});
    const t = setInterval(() => {
      if (a.currentTime >= duration - 0.05) { clearInterval(t); r(); }
    }, 100);
  });
  rec.stop();
  await stopped;
  await new Promise(r => setTimeout(r, 1500));
  return {duration, stalls};
}"""


@dataclass(frozen=True)
class Result:
    name: str
    status: str
    detail: str | dict  # 문구 코드(messages.msg) 이거나 원문 그대로의 사유

    @property
    def ok(self) -> bool:
        return self.status in ("saved", "skipped")


def validate_url(url: str) -> str:
    """수노 곡 주소, 공유 주소, 훅 주소만 받습니다."""
    parts = urlsplit(url)
    is_suno = parts.scheme == "https" and parts.hostname in ("suno.com", "www.suno.com")
    is_song = re.fullmatch(rf"/song/{UUID_RE}/?", parts.path) is not None
    is_share = re.fullmatch(r"/s/[A-Za-z0-9]+/?", parts.path) is not None
    is_hook = re.fullmatch(rf"/hook/{UUID_RE}/?", parts.path) is not None
    if not (is_suno and (is_song or is_share or is_hook)):
        raise ValueError(f"not a Suno song link: {url}")
    return url


def clip_id_from_url(url: str) -> str:
    """곡 주소면 곡 ID 를, 훅(짧은 영상) 주소면 그 훅이 쓴 원래 곡의 ID 를 돌려줍니다."""
    if match := re.search(rf"/song/({UUID_RE})", url):
        return match.group(1)
    if match := re.search(rf"/hook/({UUID_RE})", url):
        return fetch_hook(match.group(1))["original_clip_id"]
    raise ValueError(f"no song ID in: {url}")


def fetch_hook(hook_id: str) -> dict:
    request = urllib.request.Request(HOOK_API + hook_id, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def song_url(clip_id: str) -> str:
    return f"https://suno.com/song/{clip_id}"


def slugify(title: str, fallback: str) -> str:
    slug = re.sub(r"\W+", "-", title.lower()).strip("-_")
    return slug or fallback


def duration_matches(actual: float, expected: float) -> bool:
    return abs(actual - expected) <= DURATION_TOLERANCE_SEC


def find_dropouts(samples: np.ndarray, sample_rate: int = SAMPLE_RATE) -> list[float]:
    """소리가 나다가 0.1초 단위로 갑자기 무음이 된 지점(초)을 돌려줍니다."""
    window = sample_rate // 10
    count = len(samples) // window
    if count < 3:
        return []
    rms = np.sqrt((samples[: count * window].reshape(count, -1) ** 2).mean(axis=1))
    db = 20 * np.log10(rms + 1e-9)
    return [round(i * 0.1, 1) for i in range(1, count - 1) if db[i] < -55 and db[i - 1] > -35]


def count_click_candidates(samples: np.ndarray, sample_rate: int = SAMPLE_RATE) -> int:
    """튀는 지점의 개수입니다. 타악기와 구분되지 않으므로 후보로만 봅니다."""
    if len(samples) < 3:
        return 0
    curvature = np.abs(np.diff(samples, 2))
    window = sample_rate // 10
    local = np.convolve(curvature, np.ones(window) / window, "same") + 1e-4
    return int(((curvature > 12 * local) & (curvature > 0.08)).sum())


def fetch_clip(clip_id: str) -> dict:
    request = urllib.request.Request(CLIP_API + clip_id, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def peek_clip(url: str, cover: Path) -> dict:
    """녹음 전에 곡 제목과 표지를 미리 받아 둡니다. 공유 주소는 수노가 곡 주소로 넘겨 주는 곳을 따라갑니다."""
    if "/song/" not in url:
        request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=20) as response:
            url = response.geturl()
    clip = fetch_clip(clip_id_from_url(url))
    save_cover(cover, clip.get("image_large_url") or clip.get("image_url") or "")
    try:  # 데크가 지난 시간과 전체 길이를 보여 주려고 곡 길이도 같이 넘깁니다
        duration = float((clip.get("metadata") or {}).get("duration") or 0)
    except (TypeError, ValueError):
        duration = 0.0
    info = {"title": (clip.get("title") or "")[:200], "cover": cover.exists()}
    return info | ({"duration": duration} if duration > 0 else {})


def write_sidecar(target: Path, clip_id: str, clip: dict, duration: float) -> None:
    """플레이어가 제목·커버·태그를 보여줄 수 있게 곡 정보를 solo.db 에 남기고 표지를 받아 둡니다.
    서버가 재시작돼도 정보가 빠지지 않도록 녹음기가 끝까지 직접 저장합니다."""
    library.upsert(
        target.parent, target.stem, title=clip.get("title") or "", artist=clip.get("display_name") or "",
        tags=(clip.get("metadata") or {}).get("tags") or "", duration=duration,
        image_url=clip.get("image_large_url") or clip.get("image_url") or "", suno_id=clip_id)
    save_cover(target, clip.get("image_large_url") or clip.get("image_url") or "")


def save_cover(target: Path, url: str) -> None:
    """표지는 있으면 좋은 것이라 실패해도 녹음은 성공으로 둡니다."""
    cover = target.with_suffix(".jpg")
    if not url.startswith("https://") or cover.exists():
        return
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            cover.write_bytes(response.read())
    except OSError:
        pass


def run_ffmpeg(*args: str) -> None:
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", *args], check=True)


def to_mp3(source: Path, target: Path) -> None:
    run_ffmpeg("-i", str(source), "-vn", "-af", "asetpts=N/SR/TB",
               "-c:a", "libmp3lame", "-q:a", "0", "-f", "mp3", str(target))


def decode_mono(path: Path) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-nostdin", "-v", "error", "-i", str(path), "-ac", "1",
         "-ar", str(SAMPLE_RATE), "-f", "s16le", "-"],
        capture_output=True, check=True,
    ).stdout
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768


async def capture_playback(page, webm: Path, expected: float) -> dict:
    started = time.monotonic()

    def on_chunk(data: str) -> None:
        # 녹음은 곡 길이만큼 걸리므로 흐른 시간이 곧 진행률입니다. 끝의 5% 는 mp3 로 바꾸고 검사하는 몫입니다.
        sink.write(base64.b64decode(data))
        if expected > 0:
            library.report_progress((time.monotonic() - started) / expected * 0.95)

    with webm.open("wb") as sink:
        await page.expose_function("__chunk", on_chunk)
        await page.locator('button[aria-label*="Play" i]').first.click(timeout=10000)
        await page.wait_for_timeout(PLAY_SETTLE_MS)
        return await asyncio.wait_for(page.evaluate(RECORD_JS), expected + MAX_RECORD_MARGIN_SEC)


def finish_recording(webm: Path, target: Path, expected: float, stalls: int) -> Result:
    """검사를 통과한 녹음만 최종 경로로 옮깁니다."""
    mp3 = webm.with_suffix(".mp3")
    to_mp3(webm, mp3)
    samples = decode_mono(mp3)
    actual = len(samples) / SAMPLE_RATE
    dropouts = find_dropouts(samples)
    clicks = count_click_candidates(samples)
    numbers = {"actual": f"{actual:.2f}", "expected": f"{expected:.2f}",
               "dropouts": len(dropouts), "stalls": stalls, "clicks": clicks}
    if not duration_matches(actual, expected) or dropouts or stalls:
        return Result(target.name, "failed", msg("suno.take_rejected", **numbers))
    os.replace(mp3, target)
    return Result(target.name, "saved", msg("suno.take", **numbers))


async def record_one(browser, url: str, out_dir: Path, force: bool) -> Result:
    context = await browser.new_context()
    try:
        page = await context.new_page()
        await page.goto(url, wait_until="domcontentloaded", timeout=60000)
        await page.wait_for_timeout(PAGE_SETTLE_MS)
        clip_id = clip_id_from_url(page.url)
        if "/song/" not in page.url:  # 공유 주소가 훅으로 가면 원래 곡 화면에서 녹음합니다
            await page.goto(song_url(clip_id), wait_until="domcontentloaded", timeout=60000)
            await page.wait_for_timeout(PAGE_SETTLE_MS)
        clip = fetch_clip(clip_id)
        expected = float(clip["metadata"]["duration"])
        target = out_dir / f"{slugify(clip.get('title') or '', clip_id)}.mp3"
        if target.exists() and not force:
            # 앞서 녹음이 중간에 끊겨 표지만 빠진 곡이면 표지를 채워 둡니다.
            save_cover(target, clip.get("image_large_url") or clip.get("image_url") or "")
            return Result(target.name, "skipped", msg("suno.exists"))
        with tempfile.TemporaryDirectory(dir=out_dir, prefix=".recording-") as tmp:
            webm = Path(tmp) / "capture.webm"
            info = await capture_playback(page, webm, expected)
            if "error" in info:
                return Result(target.name, "failed", info["error"])
            result = finish_recording(webm, target, expected, info["stalls"])
        if target.exists():
            write_sidecar(target, clip_id, clip, expected)
        return result
    finally:
        await context.close()


async def record_all(urls: list[str], out_dir: Path, jobs: int, force: bool) -> list[Result]:
    from playwright.async_api import async_playwright

    chrome = shutil.which("google-chrome")
    limit = asyncio.Semaphore(jobs)
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(
            executable_path=chrome, headless=True,
            args=["--autoplay-policy=no-user-gesture-required", "--disable-dev-shm-usage",
                  *(["--no-sandbox"] if os.environ.get("RECORDER_NO_SANDBOX") else [])],
        )

        async def guarded(url: str) -> Result:
            async with limit:
                try:
                    return await record_one(browser, url, out_dir, force)
                except Exception as error:
                    return Result(url, "failed", f"{type(error).__name__}: {str(error)[:200]}")

        results = await asyncio.gather(*(guarded(url) for url in urls))
        await browser.close()
    return list(results)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("urls", nargs="+", help="suno.com/song/<id> or suno.com/s/<code>")
    parser.add_argument("-o", "--out", type=Path, default=Path.home() / "app" / "suno-music")
    parser.add_argument("-j", "--jobs", type=int, default=1, help="songs to record at once (default 1)")
    parser.add_argument("--force", action="store_true", help="record again even if the file exists")
    parser.add_argument("--codes", action="store_true", help="print message codes for the server instead of text")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be 1 or more")
    try:
        urls = [validate_url(url) for url in args.urls]
    except ValueError as error:
        parser.error(str(error))
    if shutil.which("ffmpeg") is None:
        parser.error("ffmpeg is required")
    args.out.mkdir(parents=True, exist_ok=True)
    results = asyncio.run(record_all(urls, args.out, args.jobs, args.force))
    lang = pick_language(None, os.environ.get("LANG", "").replace("_", "-"))
    for result in results:
        detail = result.detail
        shown = to_wire(detail) if args.codes and isinstance(detail, dict) else render(detail, lang)
        print(f"[{result.status}] {result.name}: {shown}")
    print(f"Saved to: {args.out}")
    return 0 if all(result.ok for result in results) else 1


if __name__ == "__main__":
    sys.exit(main())
