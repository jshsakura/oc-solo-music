import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'api.dart';

enum Repeat { off, all, one }

/// 재생 대기열과 오디오 엔진을 들고 있습니다. 화면은 이것만 봅니다.
class PlayerController extends ChangeNotifier {
  PlayerController(this.api) {
    _listen();
  }

  void _listen() {
    _subs.add(
      _player.positionStream.listen((p) {
        position = p;
        notifyListeners();
      }),
    );
    _subs.add(
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) _onComplete();
        notifyListeners();
      }),
    );
  }

  final Api api;
  AudioPlayer _player = AudioPlayer();
  bool _used = false;
  final List<StreamSubscription<Object?>> _subs = [];
  final Random _rng = Random();
  Timer? _sleepTimer;

  List<Track> queue = const [];
  int index = 0;
  bool shuffle = false;
  Repeat repeat = Repeat.off;
  Duration position = Duration.zero;
  int sleepMinutes = 0;

  /// 마지막 실패입니다. 화면이 언어에 맞는 문구로 바꿔 보여줍니다.
  Object? error;

  /// 판을 손으로 돌리는 동안 보여줄 위치(초)입니다. 손을 떼면 그 자리로 옮깁니다.
  double? scrubbing;

  Track? get current => queue.isEmpty ? null : queue[index];
  bool get playing => _player.playing;

  /// 서버가 잰 길이를 먼저 씁니다. 엔진의 길이는 곡을 바꾼 직전엔 앞 곡 값이 남아 있을 수 있습니다.
  double get durationSecs {
    final known = current?.duration ?? 0;
    if (known > 0) return known;
    final d = _player.duration;
    return d != null && d > Duration.zero ? d.inMilliseconds / 1000 : 0;
  }

  double get shownSecs => scrubbing ?? position.inMilliseconds / 1000;

  double get progress {
    final total = durationSecs;
    return total <= 0 ? 0 : (shownSecs / total).clamp(0.0, 1.0);
  }

  /// Dart 의 `%` 는 음수에도 0 이상을 돌려주므로 앞쪽(-1)도 그대로 됩니다.
  Track peek(int offset) => queue[(index + offset) % queue.length];

  Future<void> load(
    List<Track> tracks, {
    int start = 0,
    bool play = false,
  }) async {
    queue = List.unmodifiable(tracks);
    index = tracks.isEmpty ? 0 : start.clamp(0, tracks.length - 1);
    await _open(play: play);
  }

  Future<void> _open({required bool play}) async {
    final track = current;
    if (track == null) return;
    position = Duration.zero;
    error = null;
    notifyListeners();
    try {
      if (kIsWeb && _used) await _freshPlayer();
      _used = true;
      final auth = api.headers.isEmpty ? null : api.headers;
      await _player.setAudioSource(
        AudioSource.uri(
          api.audioUri(track.id),
          headers: kIsWeb ? null : auth,
          tag: MediaItem(
            id: track.id,
            title: track.title,
            artist: track.artist,
            artUri: track.hasCover ? api.coverUri(track.id) : null,
            artHeaders: auth,
          ),
        ),
      );
      if (play) unawaited(_player.play());
    } on Exception catch (e) {
      error = e;
      notifyListeners();
    }
  }

  /// 웹 재생 엔진(just_audio_web 0.4.16)은 내부 재생목록을 같은 id 로 캐시해서
  /// 두 번째 곡부터 첫 곡을 그대로 다시 틉니다. 웹에서는 곡마다 엔진을 새로 만듭니다.
  Future<void> _freshPlayer() async {
    final old = _player;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _player = AudioPlayer();
    _listen();
    if (repeat == Repeat.one) await _player.setLoopMode(LoopMode.one);
    unawaited(old.dispose());
  }

  void play() => unawaited(_player.play());
  void pause() => unawaited(_player.pause());
  void toggle() => playing ? pause() : play();

  Future<void> seekSecs(double secs) =>
      _player.seek(Duration(milliseconds: (secs * 1000).round()));

  void scrubTo(double? secs) {
    scrubbing = secs?.clamp(0.0, max(0.0, durationSecs - 1));
    notifyListeners();
  }

  int _next(int dir) {
    if (shuffle && queue.length > 1) {
      var n = index;
      while (n == index) {
        n = _rng.nextInt(queue.length);
      }
      return n;
    }
    return (index + dir) % queue.length;
  }

  Future<void> skip(int dir, {bool? play}) async {
    if (queue.isEmpty) return;
    final keepPlaying = play ?? playing;
    index = _next(dir);
    await _open(play: keepPlaying);
  }

  void _onComplete() {
    if (repeat == Repeat.one) {
      unawaited(_player.seek(Duration.zero));
      return;
    }
    final atEnd = !shuffle && index == queue.length - 1;
    if (atEnd && repeat == Repeat.off) {
      unawaited(_player.pause().then((_) => _player.seek(Duration.zero)));
      return;
    }
    unawaited(skip(1, play: true));
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = Repeat.values[(repeat.index + 1) % Repeat.values.length];
    unawaited(
      _player.setLoopMode(repeat == Repeat.one ? LoopMode.one : LoopMode.off),
    );
    notifyListeners();
  }

  static const sleepSteps = [0, 15, 30, 60];

  void cycleSleep() {
    sleepMinutes =
        sleepSteps[(sleepSteps.indexOf(sleepMinutes) + 1) % sleepSteps.length];
    _sleepTimer?.cancel();
    if (sleepMinutes > 0) {
      _sleepTimer = Timer(Duration(minutes: sleepMinutes), () {
        pause();
        sleepMinutes = 0;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  Future<void> toggleLike() async {
    final track = current;
    if (track == null) return;
    try {
      final liked = await api.toggleLike(track.id);
      queue = List.unmodifiable([
        for (final t in queue) t.id == track.id ? t.withLiked(liked) : t,
      ]);
      notifyListeners();
    } on Exception catch (e) {
      error = e;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
