/// 웹이 아닌 곳에서는 아무것도 하지 않습니다.
void showNowPlaying({
  required String title,
  required String artist,
  Uri? artwork,
}) {}

void bindNowPlayingActions({
  required void Function() onPlay,
  required void Function() onPause,
  required void Function() onNext,
  required void Function() onPrevious,
}) {}
