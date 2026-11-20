"""화면에 나가는 서버 문구입니다. 한국어, 영어, 일본어를 지원하고 나머지 언어는 영어로 답합니다.

문구는 저장할 때 글자로 굳히지 않고 {"code": 키, "args": {...}} 로 남깁니다. 작업 기록처럼
나중에 다른 언어 화면이 읽어도 그 언어로 나가게 하려는 것입니다. 요청마다 [render] 가 글자로 바꿉니다.
"""

from __future__ import annotations

import json

LANGS = ("ko", "en", "ja")
FALLBACK = "en"

CATALOG: dict[str, dict[str, str]] = {
    "track.not_found": {
        "ko": "곡을 찾지 못했습니다",
        "en": "Song not found",
        "ja": "曲が見つかりませんでした",
    },
    "archive.not_found": {
        "ko": "보관한 곡을 찾지 못했습니다",
        "en": "Removed song not found",
        "ja": "外した曲が見つかりませんでした",
    },
    "add.bad_url": {
        "ko": "수노 곡 주소가 아닙니다: {url}",
        "en": "Not a Suno song link: {url}",
        "ja": "Suno の曲のリンクではありません: {url}",
    },
    "upload.bad_type": {
        "ko": "올릴 수 없는 형식입니다: {name}. mp3, m4a, flac, wav, ogg, opus, aac 를 올립니다",
        "en": "Can't upload this type: {name}. Use mp3, m4a, flac, wav, ogg, opus or aac",
        "ja": "この形式はアップロードできません: {name}。mp3、m4a、flac、wav、ogg、opus、aac に対応しています",
    },
    "upload.not_audio": {
        "ko": "소리가 든 파일이 아닙니다",
        "en": "This file has no audio",
        "ja": "音声が入ったファイルではありません",
    },
    "upload.too_big": {
        "ko": "파일이 너무 큽니다. {mb}MB 까지 올립니다",
        "en": "The file is too large. The limit is {mb} MB",
        "ja": "ファイルが大きすぎます。{mb}MB まで対応しています",
    },
    "job.not_found": {
        "ko": "녹음 작업을 찾지 못했습니다",
        "en": "Job not found",
        "ja": "作業が見つかりませんでした",
    },
    "job.already_finished": {
        "ko": "이미 끝난 작업입니다",
        "en": "This job has already finished",
        "ja": "この作業はすでに終わっています",
    },
    "job.stopped_recording": {
        "ko": "녹음을 멈췄습니다",
        "en": "Recording stopped",
        "ja": "録音を止めました",
    },
    "job.dequeued": {
        "ko": "대기열에서 뺐습니다",
        "en": "Removed from the queue",
        "ja": "キューから外しました",
    },
    "suno.take": {
        "ko": "{actual}초 (원곡 {expected}초), 끊김 {dropouts}, 재생 지연 {stalls}, 잡음 후보 {clicks}",
        "en": "{actual}s (original {expected}s), dropouts {dropouts}, stalls {stalls}, possible clicks {clicks}",
        "ja": "{actual}秒 (原曲 {expected}秒)、途切れ {dropouts}、再生の遅れ {stalls}、ノイズ候補 {clicks}",
    },
    "suno.take_rejected": {
        "ko": "{actual}초 (원곡 {expected}초), 끊김 {dropouts}, 재생 지연 {stalls}, 잡음 후보 {clicks}, 저장하지 않습니다",
        "en": "{actual}s (original {expected}s), dropouts {dropouts}, stalls {stalls}, possible clicks {clicks}; not saved",
        "ja": "{actual}秒 (原曲 {expected}秒)、途切れ {dropouts}、再生の遅れ {stalls}、ノイズ候補 {clicks}。保存しません",
    },
    "suno.exists": {
        "ko": "이미 있습니다. 다시 받으려면 --force 를 씁니다",
        "en": "Already saved. Use --force to record it again",
        "ja": "すでにあります。もう一度録音するには --force を使います",
    },
    "app.no_apk": {
        "ko": "아직 받을 수 있는 안드로이드 앱이 없습니다",
        "en": "No Android app is available yet",
        "ja": "ダウンロードできる Android アプリはまだありません",
    },
    "auth.owner_only": {
        "ko": "관리자만 할 수 있습니다",
        "en": "Only the owner can do this",
        "ja": "管理者だけが操作できます",
    },
    "pair.invalid": {
        "ko": "QR 코드가 맞지 않거나 시간이 지났습니다. 웹에서 새 QR 을 띄워 주세요",
        "en": "This QR code is invalid or expired. Show a new one on the web",
        "ja": "QR コードが正しくないか期限切れです。Web で新しい QR を表示してください",
    },
    "device.not_found": {
        "ko": "기기를 찾지 못했습니다",
        "en": "Device not found",
        "ja": "端末が見つかりませんでした",
    },
    "auth.required": {
        "ko": "인증이 필요합니다",
        "en": "Authentication required",
        "ja": "認証が必要です",
    },
}

# 녹음기와 다운로더가 결과 줄에 문구 대신 이 표시를 붙여 코드를 넘깁니다.
WIRE_PREFIX = "@"


def msg(code: str, **args) -> dict:
    """나중에 글자로 바꿀 문구 하나입니다."""
    if code not in CATALOG:
        raise KeyError(code)
    return {"code": code, "args": args}


def to_wire(message: dict) -> str:
    return WIRE_PREFIX + json.dumps(message, ensure_ascii=False)


def from_wire(text: str) -> str | dict:
    """결과 줄의 사유를 읽습니다. 코드면 문구로, 아니면 받은 글 그대로 돌려줍니다."""
    if text.startswith(WIRE_PREFIX + "{"):
        try:
            data = json.loads(text[len(WIRE_PREFIX):])
        except ValueError:
            return text
        if isinstance(data, dict) and data.get("code") in CATALOG:
            return {"code": data["code"], "args": data.get("args") or {}}
    return text


def render(message: str | dict | None, lang: str) -> str:
    """문구를 그 언어 글자로 바꿉니다. 이미 글자인 것(예전 기록, yt-dlp 원문)은 그대로 둡니다."""
    if not message:
        return ""
    if isinstance(message, str):
        return message
    table = CATALOG.get(message.get("code", ""))
    if table is None:
        return str(message)
    template = table.get(lang) or table[FALLBACK]
    try:
        return template.format(**(message.get("args") or {}))
    except (KeyError, IndexError):
        return template


def pick_language(query: str | None, accept: str | None) -> str:
    """?lang= 이 있으면 그것을, 없으면 Accept-Language 에서 지원하는 첫 언어를 고릅니다."""
    if query and query[:2].lower() in LANGS:
        return query[:2].lower()
    weighted = []
    for i, part in enumerate((accept or "").split(",")):
        tag, _, params = part.strip().partition(";")
        q = 1.0
        if params.strip().startswith("q="):
            try:
                q = float(params.strip()[2:])
            except ValueError:
                q = 0.0
        weighted.append((-q, i, tag.strip()[:2].lower()))
    for _, _, code in sorted(weighted):
        if code in LANGS:
            return code
    return FALLBACK
