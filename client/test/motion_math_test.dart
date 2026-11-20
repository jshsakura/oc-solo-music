import 'package:flutter_test/flutter_test.dart';
import 'package:solo/widgets/motion_math.dart';

void main() {
  group('staggerDelay', () {
    test('rows of a fresh list wait their turn one after another', () {
      expect(staggerDelay(0, Duration.zero), Duration.zero);
      expect(staggerDelay(3, Duration.zero), staggerStep * 3);
      expect(
        staggerDelay(4, Duration.zero)!,
        greaterThan(staggerDelay(3, Duration.zero)!),
      );
    });

    test('long lists stop adding delay after the cap', () {
      expect(
        staggerDelay(staggerMaxRows + 40, Duration.zero),
        staggerStep * staggerMaxRows,
      );
    });

    test('time already spent counts toward the wait', () {
      expect(
        staggerDelay(4, const Duration(milliseconds: 100)),
        staggerStep * 4 - const Duration(milliseconds: 100),
      );
      expect(staggerDelay(1, const Duration(milliseconds: 300)), Duration.zero);
    });

    test('rows that show up after the window appear at once', () {
      expect(staggerDelay(0, staggerWindow), isNull);
      expect(staggerDelay(5, const Duration(seconds: 3)), isNull);
    });
  });

  group('popScale', () {
    test('starts and ends at rest', () {
      expect(popScale(0), 1);
      expect(popScale(1), 1);
      expect(popScale(-1), 1);
      expect(popScale(2), 1);
    });

    test('swells noticeably then settles without collapsing', () {
      var peak = 1.0, low = 1.0;
      for (var t = 0.0; t <= 1; t += 0.005) {
        final v = popScale(t);
        peak = v > peak ? v : peak;
        low = v < low ? v : low;
      }
      expect(peak, inInclusiveRange(1.15, 1.4));
      expect(low, greaterThan(0.85));
      expect((popScale(0.97) - 1).abs(), lessThan(0.01));
    });
  });

  group('sparkAt', () {
    test('every spark starts at the centre and ends invisible', () {
      for (var i = 0; i < 8; i++) {
        final s0 = sparkAt(i, 8, 0, reach: 20);
        expect(s0.pos.distance, closeTo(0, 1e-9));
        expect(s0.opacity, 1);
        expect(sparkAt(i, 8, 1, reach: 20).opacity, 0);
      }
    });

    test('sparks fly out in different directions within reach', () {
      final ends = [for (var i = 0; i < 8; i++) sparkAt(i, 8, 1, reach: 20)];
      for (final s in ends) {
        expect(s.pos.distance, inInclusiveRange(20 * 0.7 - 1e-9, 20 + 1e-9));
      }
      final right = ends.where((s) => s.pos.dx > 0).length;
      expect(right, inInclusiveRange(2, 6));
    });

    test('gravity pulls confetti down and the burst is repeatable', () {
      final light = sparkAt(2, 10, 1, reach: 50, seed: 3);
      final heavy = sparkAt(2, 10, 1, reach: 50, gravity: 90, seed: 3);
      expect(heavy.pos.dy - light.pos.dy, closeTo(90, 1e-9));
      expect(
        sparkAt(5, 10, .4, reach: 50, seed: 3).pos,
        sparkAt(5, 10, .4, reach: 50, seed: 3).pos,
      );
    });
  });

  test('equalizer bars stay in range and keep moving apart', () {
    var lo = 1.0, hi = 0.0;
    var differ = false;
    for (var t = 0.0; t < 5; t += 0.01) {
      for (var b = 0; b < 3; b++) {
        final v = eqLevel(b, t);
        lo = v < lo ? v : lo;
        hi = v > hi ? v : hi;
      }
      if ((eqLevel(0, t) - eqLevel(2, t)).abs() > 0.2) differ = true;
    }
    expect(lo, greaterThanOrEqualTo(0.18 - 1e-9));
    expect(hi, lessThanOrEqualTo(1 + 1e-9));
    expect(hi - lo, greaterThan(0.6));
    expect(differ, isTrue);
  });

  test('pulse ring grows outward while fading and loops', () {
    final start = pulseRing(0), mid = pulseRing(.5), late = pulseRing(.95);
    expect(start.grow, 0);
    expect(mid.grow, greaterThan(start.grow));
    expect(late.grow, greaterThan(mid.grow));
    expect(late.opacity, lessThan(mid.opacity));
    expect(pulseRing(1.25).grow, closeTo(pulseRing(.25).grow, 1e-9));
  });
}
