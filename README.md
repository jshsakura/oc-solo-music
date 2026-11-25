# Solo

수노(Suno)에서 내가 만든 곡은 녹음하고, 내가 만들었거나 산 곡 파일은 올려서 서버에 모아 두고, 폰과 PC 에서 나만 듣는 재생기로 내려주는 셀프호스팅 앱입니다.

A self-hosted personal music player. Paste a link to a Suno song you made, or upload audio files you made or bought. The server keeps them and you listen from your own phone or computer, including iPhone with the screen off.

## 무엇을 하나

- 수노 곡 주소를 넣으면 컨테이너 안의 헤드리스 크롬이 곡을 실시간으로 재생해 녹음하고 MP3 로 저장합니다. 제목, 아티스트, 태그, 길이, 표지도 함께 가져옵니다.
- 가진 곡 파일(mp3, m4a, flac, wav, ogg, opus, aac)을 올리면 mp3 와 m4a 는 그대로, 나머지는 mp3 로 바꿔 둡니다. 제목, 아티스트, 표지는 파일 안의 태그에서 가져옵니다.
- 곡 정보(제목, 장르, 가사, 표지, 수노에서 만든 정보)와 좋아요는 곡 파일 안의 태그에 둡니다. 파일만 다른 보관함으로 옮겨도 정보가 따라갑니다. `solo.db` 는 태그를 빠르게 읽으려고 둔 캐시라서 지워도 파일에서 다시 만듭니다. 앱에서 곡을 빼면 파일은 지우지 않고 `archive/` 폴더로 옮깁니다.
- 재생기는 설치 없이 쓰는 웹앱(PWA)입니다. 아이폰 사파리에서 화면을 꺼도 다음 곡으로 넘어가며 이어 재생되고, 잠금 화면 컨트롤과 표지가 나옵니다.
- 네트워크가 끊기면 다음 곡으로 넘기지 않고 끊긴 자리부터 다시 받습니다.

## 담는 곡의 범위

Solo 는 **내가 만든 곡과 정당하게 가진 곡만** 담는 개인용 재생기입니다.

- 수노 녹음은 본인이 만든 곡에만 씁니다. 로그인 쿠키나 암호화 키를 다루지 않고 비로그인 공개 재생을 한 번에 한 곡씩 녹음합니다. 유료 플랜이라면 수노가 내주는 공식 다운로드 파일을 올리는 쪽을 권합니다.
- 다른 스트리밍 서비스(유튜브 등)에서 음원을 받아 오는 기능은 없습니다. 예전 버전에 있던 유튜브 받기는 서비스 약관과 기술적 보호조치 우회 문제로 뺐습니다.
- 서버는 본인 기기에서만 듣도록 둡니다. 남과 계정을 나눠 스트리밍하는 것은 사적 이용의 범위를 벗어날 수 있습니다.

## 실행

```bash
cp .env.example .env      # 필요하면 값 수정
docker compose up -d
```

`http://<서버 주소>:8000` 으로 엽니다. 이미지는 `ghcr.io/jshsakura/oc-solo-music:latest` 입니다(linux/amd64).

| 변수 | 기본값 | 설명 |
|---|---|---|
| `SOLO_PORT` | `8000` | 호스트에 여는 포트 |
| `SOLO_LIBRARY` | `./library` | 곡과 표지를 두는 폴더. 캐시 `solo.db` 도 여기 생깁니다 |
| `SOLO_PASSWORD` | 비어 있음 | 정하면 모든 요청에 HTTP Basic 인증을 겁니다(사용자 이름은 아무거나) |
| `TZ` | `Asia/Seoul` | 시간대 |

**인터넷에 직접 열 때는 `SOLO_PASSWORD` 를 반드시 정하세요.** 비밀번호가 없으면 주소를 아는 누구나 곡을 지우거나 녹음을 걸 수 있습니다. 앞단에 다른 인증(예: Cloudflare Access, VPN)이 있으면 비워 둬도 됩니다.

녹음용 크롬이 공유 메모리를 쓰므로 `shm_size: 1gb` 를 유지하세요.

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
