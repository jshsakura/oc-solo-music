import 'dart:math' as math;

import '../api.dart';

/// 홈 판 상자의 분류입니다. 서버가 곡을 최근에 넣은 순서로 주므로 최근은 전부입니다.
enum HomeCrate { recent, liked, suno, youtube }

List<Track> crateTracks(List<Track> all, HomeCrate crate) => all
    .where(
      (t) => switch (crate) {
        HomeCrate.recent => true,
        HomeCrate.liked => t.liked,
        HomeCrate.suno => t.source == 'suno',
        HomeCrate.youtube => t.source == 'youtube',
      },
    )
    .toList(growable: false);

/// 손가락이 이만큼 움직이면 판 한 장이 넘어갑니다.
const double flipPixels = 120;

/// 끌고 있는 동안의 위치입니다. 양 끝에서는 반 장 못 미치게 살짝만 더 넘어갑니다.
double dragPosition(double start, double dy, int count) {
  if (count == 0) return 0;
  return (start + dy / flipPixels).clamp(-0.3, count - 0.7);
}

/// 손을 뗐을 때 멈출 판입니다. 던진 속도만큼 더 넘깁니다.
int snapTarget(double position, double velocity, int count) {
  if (count == 0) return 0;
  final fling = velocity * 0.1 / flipPixels * 1.5;
  return (position + fling).round().clamp(0, count - 1);
}

/// 지금 맨 앞에 서 있는 판의 번호입니다.
int frontIndex(double position, int count) =>
    count == 0 ? 0 : position.clamp(0, count - 1).round();

/// 판 한 장의 자세입니다. 각도는 도 단위입니다.
class SleevePose {
  const SleevePose({
    required this.dy,
    required this.dz,
    required this.tilt,
    required this.opacity,
    required this.layer,
  });
  final double dy;
  final double dz;
  final double tilt;
  final double opacity;
  final int layer;
}

double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0, 1);

/// [offset] 은 맨 앞에서 몇 장 떨어졌는지입니다. 음수면 이미 넘겨서 앞으로 쓰러진 판입니다.
SleevePose sleevePose(double offset, int index) {
  if (offset < -0.5) {
    return SleevePose(
      dy: 150,
      dz: 0,
      tilt: -78,
      opacity: offset < -1.2 ? _lerp(0.5, 0, (-offset - 1.2) / 0.3) : 0.5,
      layer: 220 + index,
    );
  }
  if (offset <= 0) {
    final k = -offset * 2;
    return SleevePose(
      dy: k * 150,
      dz: 0,
      tilt: -8 - k * 70,
      opacity: _lerp(1, 0.5, (k - 0.6) / 0.4),
      layer: 200 - index,
    );
  }
  final d = math.min(offset, 5.0);
  return SleevePose(
    dy: -d * 16,
    dz: -d * 26,
    tilt: _lerp(-8, 6 + d * 3, offset * 2),
    opacity: (6 - offset).clamp(0, 1),
    layer: 200 - index,
  );
}
