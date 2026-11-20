package app.solo.music

import com.ryanheise.audioservice.AudioServiceActivity

// 백그라운드 재생 서비스와 같은 엔진을 쓰려면 AudioServiceActivity 를 이어받아야 합니다.
class MainActivity : AudioServiceActivity()
