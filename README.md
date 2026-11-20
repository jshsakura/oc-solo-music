# Solo

수노(Suno)에서 만든 내 곡은 녹음하고 유튜브 곡은 받아서 서버에 모아 두고, 폰과 PC 브라우저에서 나만 듣는 재생기로 내려주는 셀프호스팅 앱입니다.

A self-hosted personal music player. Paste a link to your own Suno song or a YouTube track, the server keeps the audio, and you listen from any browser, including iPhone with the screen off.

## 무엇을 하나

- 수노 곡 주소를 넣으면 컨테이너 안의 헤드리스 크롬이 곡을 실시간으로 재생해 녹음하고 MP3 로 저장합니다. 제목, 아티스트, 태그, 길이, 표지도 함께 가져옵니다.
- 유튜브 주소를 넣거나 곡 이름으로 찾으면 서버가 mp3 로 받아 둡니다. 재생목록 주소는 최대 1000곡까지 폅니다. 한 번에 한 곡씩, 곡 사이를 띄워서 받습니다.
- 곡 정보와 좋아요는 SQLite(`solo.db`) 하나에 두고, 오디오와 표지는 파일로 둡니다. 앱에서 곡을 빼면 파일은 지우지 않고 `archive/` 폴더로 옮깁니다.
- 재생기는 설치 없이 쓰는 웹앱(PWA)입니다. 아이폰 사파리에서 화면을 꺼도 다음 곡으로 넘어가며 이어 재생되고, 잠금 화면 컨트롤과 표지가 나옵니다.
- 네트워크가 끊기면 다음 곡으로 넘기지 않고 끊긴 자리부터 다시 받습니다.

본인이 만든 곡만 넣으세요. 이 앱은 로그인 쿠키나 암호화 키를 다루지 않고, 비로그인 상태의 공개 재생을 녹음합니다. 녹음은 곡 길이만큼 걸리며 한 번에 한 곡씩 처리합니다.

## 실행

```bash
cp .env.example .env      # 필요하면 값 수정
docker compose up -d
```

`http://<서버 주소>:8000` 으로 엽니다. 이미지는 `ghcr.io/jshsakura/oc-solo-music:latest` 입니다(linux/amd64).

| 변수 | 기본값 | 설명 |
|---|---|---|
| `SOLO_PORT` | `8000` | 호스트에 여는 포트 |
| `SOLO_LIBRARY` | `./library` | 곡, 표지, `solo.db` 를 두는 폴더 |
| `SOLO_PASSWORD` | 비어 있음 | 정하면 모든 요청에 HTTP Basic 인증을 겁니다(사용자 이름은 아무거나) |
| `SOLO_POT_BASE_URL` | compose 에서 지정 | PO Token 공급자 주소 |
| `SOLO_YT_COOKIES` | `<라이브러리>/.youtube/cookies.txt` | 유튜브 계정 쿠키 위치 |
| `TZ` | `Asia/Seoul` | 시간대 |

**인터넷에 직접 열 때는 `SOLO_PASSWORD` 를 반드시 정하세요.** 비밀번호가 없으면 주소를 아는 누구나 곡을 지우거나 녹음을 걸 수 있습니다. 앞단에 다른 인증(예: Cloudflare Access, VPN)이 있으면 비워 둬도 됩니다.

녹음용 크롬이 공유 메모리를 쓰므로 `shm_size: 1gb` 를 유지하세요.

## 유튜브 계정 연결 (선택)

계정 없이도 유튜브 일반 검색으로 찾고 받을 수 있습니다. 다만 뮤직비디오, 커버, 라이브가 섞여 나옵니다.
계정을 연결하면 유튜브 뮤직의 "노래" 검색을 써서 공식 음원만 곡명, 아티스트, 앨범, 정사각형 표지와 함께 나옵니다.

1. 주 계정이 아닌 **서브 계정**으로 브라우저에서 youtube.com 에 로그인합니다.
2. "Get cookies.txt LOCALLY" 같은 확장으로 youtube.com 쿠키를 Netscape 형식 `cookies.txt` 로 내보냅니다.
3. 앱의 추가 화면 아래 "유튜브 계정"에서 그 파일을 올립니다.

서버는 youtube.com 과 google.com 쿠키만 남겨 `library/.youtube/cookies.txt` 에 본인만 읽을 수 있는 권한(600)으로 저장합니다. 이 파일은 계정 로그인 정보이므로 라이브러리 폴더를 남과 공유하지 마세요.

받기에는 PO Token 공급자 컨테이너(`bgutil-pot`)가 필요합니다. `compose.yaml` 에 함께 들어 있습니다.

## 아이폰에서

사파리로 연 뒤 공유 → 홈 화면에 추가 하면 주소창 없이 앱처럼 열립니다. 백그라운드 재생은 사파리의 기본 오디오 재생에 맡깁니다.

## 개발

```bash
pip install -r requirements.txt -r requirements-dev.txt
python -m pytest -q
SOLO_LIB=./library uvicorn app.main:app --reload
```

녹음까지 해 보려면 호스트에 Google Chrome 과 ffmpeg 가 있어야 합니다.

## 라이선스

MIT
