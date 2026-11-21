// 웹에서만 브라우저의 Media Session 에 곡 정보를 넘깁니다. 앱은 just_audio_background 가 맡습니다.
export 'now_playing_stub.dart'
    if (dart.library.js_interop) 'now_playing_web.dart';
