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
        "ko": "수노나 유튜브 주소가 아닙니다: {url}",
        "en": "Not a Suno or YouTube link: {url}",
        "ja": "Suno か YouTube のリンクではありません: {url}",
    },
    "add.youtube_unreadable": {
        "ko": "유튜브 주소를 읽지 못했습니다: {reason}",
        "en": "Could not read the YouTube link: {reason}",
        "ja": "YouTube のリンクを読み込めませんでした: {reason}",
    },
    "add.nothing_found": {
        "ko": "이 주소에서 받을 곡을 찾지 못했습니다",
        "en": "No songs to get from this link",
        "ja": "このリンクから保存できる曲が見つかりませんでした",
    },
    "search.failed": {
        "ko": "유튜브 검색이 실패했습니다: {reason}",
        "en": "YouTube search failed: {reason}",
        "ja": "YouTube の検索に失敗しました: {reason}",
    },
    "youtube.bad_id": {
        "ko": "영상 ID 가 올바르지 않습니다",
        "en": "Invalid video ID",
        "ja": "動画 ID が正しくありません",
    },
    "youtube.no_login_cookie": {
        "ko": "로그인 쿠키가 없습니다. 유튜브에 로그인한 상태에서 cookies.txt 를 내보내 주세요",
        "en": "No sign-in cookie found. Export cookies.txt while signed in to YouTube",
        "ja": "ログイン Cookie がありません。YouTube にログインした状態で cookies.txt を書き出してください",
    },
    "youtube.format_unavailable": {
        "ko": "유튜브가 이 곡의 음원을 내주지 않았습니다. 잠시 뒤 다시 받아 보세요",
        "en": "YouTube did not hand over the audio. Try again in a little while",
        "ja": "YouTube が音源を渡しませんでした。少し待ってからもう一度お試しください",
    },
    "youtube.sign_in": {
        "ko": "유튜브가 로그인을 요구합니다. 유튜브 계정을 연결해 보세요",
        "en": "YouTube wants you to sign in. Try connecting a YouTube account",
        "ja": "YouTube がログインを求めています。YouTube アカウントを連携してください",
    },
    "youtube.private": {
        "ko": "비공개 영상이라 받을 수 없습니다",
        "en": "This video is private",
        "ja": "非公開の動画なので保存できません",
    },
    "youtube.unavailable": {
        "ko": "지금은 볼 수 없는 영상입니다",
        "en": "This video is not available right now",
        "ja": "現在視聴できない動画です",
    },
    "youtube.no_file": {
        "ko": "받은 파일이 없습니다",
        "en": "Nothing was downloaded",
        "ja": "保存されたファイルがありません",
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
    "job.stopped_downloading": {
        "ko": "받기를 멈췄습니다",
        "en": "Download stopped",
        "ja": "保存を止めました",
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
