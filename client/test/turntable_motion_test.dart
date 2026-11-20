import 'package:flutter_test/flutter_test.dart';
import 'package:solo/player/turntable_motion.dart';

const _frame = 1 / 60;

/// 판 속도를 [secs] 동안 60fps 로 진행합니다.
double _runSpin(double speed, double target, double secs) {
  for (var t = 0.0; t < secs; t += _frame) {
    speed = spinStep(speed, target, _frame);
  }
  return speed;
}

void main() {
  group('spinStep', () {
    test('spins up gradually and reaches 33 rpm within a second', () {
      final early = _runSpin(0, normalSpeed, 0.3);
      expect(early, greaterThan(0));
      expect(early, lessThan(normalSpeed * 0.5));
      expect(_runSpin(0, normalSpeed, 0.85), normalSpeed);
    });

    test('coasts down to a stop instead of halting at once', () {
      expect(_runSpin(normalSpeed, 0, 0.5), greaterThan(0));
      expect(_runSpin(normalSpeed, 0, 1.05), 0);
    });

    test('a hand fling above normal speed eases back without overshooting', () {
      var speed = 1400.0;
      for (var i = 0; i < 600; i++) {
        speed = spinStep(speed, normalSpeed, _frame);
        expect(speed, greaterThanOrEqualTo(normalSpeed));
      }
      expect(speed, normalSpeed);
    });
  });

  group('springStep', () {
    test('settles on the target', () {
      var s = (pos: 0.0, vel: 0.0);
      for (var i = 0; i < 180; i++) {
        s = springStep(
          s.pos,
          s.vel,
          20,
          _frame,
          stiffness: 70,
          dampingRatio: 0.72,
        );
      }
      expect(s.pos, closeTo(20, 0.01));
      expect(s.vel, closeTo(0, 0.05));
    });

    test('an underdamped needle bounces past its rest before settling', () {
      var s = (pos: 1.0, vel: 0.0);
      var lowest = 1.0;
      for (var i = 0; i < 120; i++) {
        s = springStep(
          s.pos,
          s.vel,
          0,
          _frame,
          stiffness: 260,
          dampingRatio: 0.32,
        );
        if (s.pos < lowest) lowest = s.pos;
      }
      expect(lowest, lessThan(-0.1));
      expect(s.pos.abs(), lessThan(0.01));
    });
  });

  group('tonearm', () {
    test(
      'rests off the record when paused and tracks inward while playing',
      () {
        expect(armAngleFor(playing: false, progress: 0.5), armRest);
        expect(armAngleFor(playing: true, progress: 0), armStart);
        expect(armAngleFor(playing: true, progress: 1), armStart + armSpan);
        expect(armAngleFor(playing: true, progress: 2), armStart + armSpan);
        expect(
          armAngleFor(playing: true, progress: 0.6),
          greaterThan(armAngleFor(playing: true, progress: 0.3)),
        );
      },
    );

    test('lifts while carried or far from its target and lowers when near', () {
      expect(liftTarget(armGap: 0.3, dragging: false), 0);
      expect(liftTarget(armGap: -5, dragging: false), 1);
      expect(liftTarget(armGap: 0, dragging: true), 1);
    });

    test('wobble stays small but keeps moving', () {
      var lo = 0.0, hi = 0.0;
      for (var t = 0.0; t < 20; t += 0.01) {
        final w = armWobble(t, t * normalSpeed);
        lo = w < lo ? w : lo;
        hi = w > hi ? w : hi;
      }
      expect(lo, greaterThan(-0.8));
      expect(hi, lessThan(0.8));
      expect(hi - lo, greaterThan(0.5));
    });
  });

  group('deck', () {
    test('needle-drop rumble shakes a few pixels then dies away', () {
      expect(rumbleOffset(0), Offset.zero);
      expect(rumbleOffset(rumbleSecs), Offset.zero);
      var peak = 0.0;
      for (var t = 0.0; t < rumbleSecs; t += 0.002) {
        final d = rumbleOffset(t).distance;
        if (d > peak) peak = d;
      }
      expect(peak, inInclusiveRange(1.0, 3.0));
      expect(rumbleOffset(rumbleSecs * 0.9).distance, lessThan(0.2));
    });

    test('shadow breath swings between 0 and 1', () {
      expect(breath(0), closeTo(0, 1e-9));
      expect(breath(1.6), closeTo(1, 1e-9));
      for (var t = 0.0; t < 10; t += 0.1) {
        expect(breath(t), inInclusiveRange(0, 1));
      }
    });

    test('scrub ticks change cell every couple of seconds', () {
      expect(scrubTick(0), scrubTick(scrubTickSecs - 0.01));
      expect(scrubTick(scrubTickSecs), isNot(scrubTick(0)));
      expect(scrubTick(-0.5), -1);
    });
  });
}
