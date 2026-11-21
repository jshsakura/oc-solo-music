import 'dart:math';
import 'dart:ui' show Offset;

/// 화면 곳곳의 작은 움직임에 쓰는 계산입니다. 시간과 화면에 묶이지 않아 그대로 시험할 수 있습니다.

/// 줄이 차례로 들어올 때 한 줄마다 늦추는 시간입니다.
const staggerStep = Duration(milliseconds: 45);

/// 이만큼 지난 뒤에 생기는 줄은 차례를 기다리지 않고 바로 나옵니다(스크롤로 새로 보이는 줄).
const staggerWindow = Duration(milliseconds: 700);

/// 이 줄 수를 넘으면 더 늦추지 않습니다. 긴 목록의 끝 줄이 한참 뒤에 나오지 않게 합니다.
const staggerMaxRows = 12;

/// 목록이 처음 그려진 뒤 [sinceStart] 가 지난 시점에 [index] 번째 줄이 기다릴 시간입니다.
/// null 이면 움직이지 않고 바로 보여 줍니다.
Duration? staggerDelay(int index, Duration sinceStart) {
  if (sinceStart >= staggerWindow) return null;
  final slot = staggerStep * min(index, staggerMaxRows);
  final left = slot - sinceStart;
  return left.isNegative ? Duration.zero : left;
}

/// 눌렀을 때 톡 튀는 크기입니다. 0 에서 1 로 가는 동안 부풀었다가 살짝 줄고 1 로 돌아옵니다.
double popScale(double t) {
  if (t <= 0 || t >= 1) return 1;
  final fade = (1 - t) * (1 - t);
  return 1 + 0.55 * sin(t * pi * 2.5) * fade;
}

/// 터지는 조각 하나의 상태입니다.
typedef Spark = ({Offset pos, double size, double opacity, double turn});

double _jitter(int i, int seed) {
  final v = sin(i * 12.9898 + seed * 78.233) * 43758.5453;
  return v - v.floorToDouble();
}

/// [count] 개 조각 중 [i] 번째가 진행도 [t] 에 있는 자리입니다. 가운데에서 [reach] 만큼 퍼지고,
/// [gravity] 가 있으면 떨어지며, 끝에 가까울수록 흐려집니다.
Spark sparkAt(
  int i,
  int count,
  double t, {
  required double reach,
  double gravity = 0,
  int seed = 0,
}) {
  final p = t.clamp(0.0, 1.0);
  final angle = 2 * pi * i / count + (_jitter(i, seed) - 0.5) * 0.6;
  final out = 1 - pow(1 - p, 3).toDouble();
  final dist = reach * out * (0.7 + 0.3 * _jitter(i, seed + 1));
  final pos = Offset(cos(angle) * dist, sin(angle) * dist + gravity * p * p);
  final opacity = p < 0.55 ? 1.0 : ((1 - p) / 0.45).clamp(0.0, 1.0);
  return (
    pos: pos,
    size: 1 - 0.6 * p,
    opacity: opacity,
    turn: (_jitter(i, seed + 2) - 0.5) * 6 * p,
  );
}

/// 재생 중 막대 [bar] 번째의 높이(0.18~1)입니다. 박자가 어긋난 사인 둘이라 고르게 들썩입니다.
double eqLevel(int bar, double t) {
  final a = sin(t * (7.1 + bar * 1.7) + bar * 2.1);
  final b = sin(t * (11.3 - bar * 1.3) + bar * 0.7);
  return 0.18 + 0.82 * (0.5 + 0.25 * a + 0.25 * b);
}

/// 퍼져 나가는 고리입니다. [t] 0~1 동안 [grow] 는 0 에서 1 로 퍼지고, [opacity] 는 흐려집니다.
({double grow, double opacity}) pulseRing(double t) {
  final p = t - t.floorToDouble();
  return (grow: 1 - pow(1 - p, 2).toDouble(), opacity: 0.85 * (1 - p));
}
