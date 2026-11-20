import 'dart:math';
import 'dart:ui' show Offset;

/// 턴테이블 움직임의 계산만 모았습니다. 화면과 시간에 묶이지 않아 그대로 시험할 수 있습니다.

/// 33⅓ rpm 을 도/초로 바꾼 값입니다.
const normalSpeed = 200.0;

/// 판이 멈춘 데서 제 속도까지 오르는 시간과, 제 속도에서 멈출 때까지 걸리는 시간입니다.
const spinUpSecs = 0.8, spinDownSecs = 1.0;

/// 바늘 각도(도)입니다. 받침에 쉬는 자리, 판 바깥 홈, 곡 끝까지 들어가는 폭, 손으로 끌 수 있는 끝입니다.
const armRest = 0.0, armStart = 20.0, armSpan = 18.0, armMax = 40.0;

/// 바늘 내려앉음이 끝나고 판이 떨리는 시간입니다.
const rumbleSecs = 0.35;

/// 판을 손으로 돌릴 때 이만큼(초) 지날 때마다 손끝에 틱을 줍니다.
const scrubTickSecs = 2.0;

/// 바늘이 목표와 이만큼(도) 넘게 떨어져 있으면 들어 올린 채로 옮깁니다.
const liftGap = 1.2;

/// 판 속도를 한 프레임 진행합니다. 손으로 튕겨 제 속도를 넘으면 마찰처럼 천천히 풀리고,
/// 그 안에서는 모터처럼 일정하게 붙어 올라가거나 관성으로 서서히 멈춥니다.
double spinStep(double speed, double target, double dt) {
  if (speed.abs() > normalSpeed + 0.5) {
    return speed + (target - speed) * min(1.0, dt * 1.2);
  }
  final speedingUp = target.abs() > speed.abs();
  final rate =
      normalSpeed / (speedingUp ? spinUpSecs : spinDownSecs) * dt.abs();
  final diff = target - speed;
  return diff.abs() <= rate ? target : speed + rate * diff.sign;
}

/// 감쇠 용수철을 dt 만큼 진행합니다. 감쇠비가 1 보다 작으면 목표를 살짝 넘었다 돌아옵니다.
({double pos, double vel}) springStep(
  double pos,
  double vel,
  double target,
  double dt, {
  required double stiffness,
  required double dampingRatio,
}) {
  const step = 1 / 240;
  final damping = 2 * dampingRatio * sqrt(stiffness);
  var left = dt;
  while (left > 0) {
    final h = min(step, left);
    vel += (-stiffness * (pos - target) - damping * vel) * h;
    pos += vel * h;
    left -= h;
  }
  return (pos: pos, vel: vel);
}

/// 재생 중이면 곡이 흐른 만큼 바늘이 안쪽으로 들어가고, 멈추면 받침으로 돌아갑니다.
double armAngleFor({required bool playing, required double progress}) =>
    playing ? armStart + armSpan * progress.clamp(0.0, 1.0) : armRest;

/// 바늘을 들어 올릴지(1) 내려놓을지(0)입니다. 손에 들렸거나 목표에서 멀면 듭니다.
double liftTarget({required double armGap, required bool dragging}) =>
    dragging || armGap.abs() > liftGap ? 1.0 : 0.0;

/// 재생 중 바늘의 잔떨림(도)입니다. 박자가 어긋난 사인 셋에, 판 한 바퀴마다 한 번씩
/// 흔들리는 편심을 더해 불규칙하게 보입니다. 크기는 0.8도를 넘지 않습니다.
double armWobble(double t, double rotDeg) {
  const tau = 2 * pi;
  return 0.30 * sin(tau * 0.9 * t) +
      0.16 * sin(tau * 2.3 * t + 1.3) +
      0.08 * sin(tau * 5.7 * t + 0.4) +
      0.14 * sin(rotDeg * pi / 180);
}

/// 바늘이 내려앉은 뒤 t 초에 판이 흔들리는 거리(px)입니다. 빠르게 떨다 금세 잦아듭니다.
Offset rumbleOffset(double t) {
  if (t <= 0 || t >= rumbleSecs) return Offset.zero;
  final amp = 2.4 * exp(-t * 11);
  return Offset(
    amp * sin(t * 2 * pi * 31),
    amp * 0.6 * sin(t * 2 * pi * 23 + 1.1),
  );
}

/// 판 그림자가 숨 쉬듯 커졌다 작아지는 정도입니다. 3.2초 주기로 0 과 1 사이를 오갑니다.
double breath(double t) => 0.5 - 0.5 * cos(2 * pi * t / 3.2);

/// 손으로 돌리는 위치가 몇 번째 틱 칸에 있는지입니다. 칸이 바뀔 때 손끝에 틱을 줍니다.
int scrubTick(double secs) => (secs / scrubTickSecs).floor();
