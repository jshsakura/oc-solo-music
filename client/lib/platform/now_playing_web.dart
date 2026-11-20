import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// 잠금 화면과 제어 센터의 지금 재생 칸에 제목, 아티스트, 표지를 보여 줍니다.
/// 넘기지 않으면 iOS 는 사이트 아이콘을 대신 띄웁니다.
void showNowPlaying({
  required String title,
  required String artist,
  Uri? artwork,
}) {
  final images = <web.MediaImage>[
    if (artwork != null)
      for (final size in const ['512x512', '800x800'])
        web.MediaImage(
          src: artwork.toString(),
          sizes: size,
          type: 'image/jpeg',
        ),
  ];
  try {
    web.window.navigator.mediaSession.metadata = web.MediaMetadata(
      web.MediaMetadataInit(
        title: title,
        artist: artist,
        album: 'Solo',
        artwork: images.toJS,
      ),
    );
  } on Object {
    // Media Session 이 없는 브라우저에서는 넘어갑니다.
  }
}

/// 잠금 화면의 이전·다음 버튼이 10초 이동이 아니라 곡을 넘기게 합니다.
void bindNowPlayingActions({
  required void Function() onPlay,
  required void Function() onPause,
  required void Function() onNext,
  required void Function() onPrevious,
}) {
  final session = web.window.navigator.mediaSession;
  void bind(String action, void Function() run) {
    try {
      session.setActionHandler(action, ((JSAny? _) => run()).toJS);
    } on Object {
      // 지원하지 않는 동작은 건너뜁니다.
    }
  }

  bind('play', onPlay);
  bind('pause', onPause);
  bind('nexttrack', onNext);
  bind('previoustrack', onPrevious);
}
