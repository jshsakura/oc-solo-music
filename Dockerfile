# deno 는 yt-dlp 가 유튜브 서명과 n 챌린지를 푸는 데 씁니다. 없으면 포맷이 통째로 사라집니다.
FROM denoland/deno:bin AS deno

# 화면은 Flutter 웹으로 빌드합니다. 결과물만 마지막 이미지로 옮깁니다.
# CI 의 flutter-version 과 같이 올립니다.
FROM ghcr.io/cirruslabs/flutter:3.44.0 AS web
WORKDIR /client
COPY client/pubspec.yaml client/pubspec.lock ./
RUN flutter pub get
COPY client/ ./
RUN flutter build web --release --base-href /

# Docker Hub 익명 pull 제한(429)을 피하려고 구글의 Docker Hub 미러를 씁니다.
# AWS Public ECR 미러는 2026-11-20 에 CI 에서 "Data limit exceeded" 로 막힌 적이 있습니다.
FROM mirror.gcr.io/library/python:3.12-slim

ARG VERSION=dev
# 패키지를 저장소에 묶어 저장소와 같은 공개 범위를 따르게 합니다. 서버가 로그인 없이 이미지를 받습니다.
LABEL org.opencontainers.image.source="https://github.com/jshsakura/oc-solo-music" \
      org.opencontainers.image.description="Solo: your own record shelf" \
      org.opencontainers.image.licenses="MIT"
ENV SOLO_VERSION=$VERSION \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    RECORDER_NO_SANDBOX=1 \
    SOLO_LIB=/library \
    SOLO_WEB=/app/web \
    SOLO_APK_DIR=/app/apk

# 수노 플레이어는 MSE 로 소리를 풀어 재생하므로 헤드리스 크롬 안에서 실제로 재생시켜 녹음한다.
# 크롬은 .deb 로 깐다(playwright 번들 chromium 은 코덱이 빠져 있어 쓰지 않는다).
RUN apt-get update && apt-get install -y --no-install-recommends \
      ffmpeg tzdata curl ca-certificates fonts-noto-cjk \
    && curl -fsSL -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && apt-get install -y --no-install-recommends /tmp/chrome.deb \
    && rm -rf /tmp/chrome.deb /var/lib/apt/lists/*

COPY --from=deno /deno /usr/local/bin/deno

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app/ ./app/
COPY --from=web /client/build/web ./web/
# CI 가 빌드한 안드로이드 앱입니다. 로컬 빌드에서는 비어 있어 /solo.apk 가 404 를 냅니다.
COPY apk/ ./apk/

VOLUME ["/library"]
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=5 \
  CMD curl -fsS http://127.0.0.1:8000/healthz >/dev/null || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
