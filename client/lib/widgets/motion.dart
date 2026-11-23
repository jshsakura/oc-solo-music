import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme.dart';
import 'motion_math.dart';

/// 화면 곳곳에서 같이 쓰는 움직임 부품입니다. 기기에서 움직임 줄이기를 켜면 전부 끝 상태로 바로 갑니다.

bool reducedMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// 누르는 동안 살짝 들어가고, 떼면 탄력 있게 돌아옵니다.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapUp,
    this.scale = .88,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 마우스 오른쪽 클릭입니다. 누른 곳의 화면 좌표를 줍니다.
  final GestureTapUpCallback? onSecondaryTapUp;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (v != _down) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onSecondaryTapUp: widget.onSecondaryTapUp,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: reducedMotion(context)
            ? Duration.zero
            : Duration(milliseconds: _down ? 80 : 650),
        curve: _down ? Curves.easeOut : Curves.elasticOut,
        child: widget.child,
      ),
    ),
  );
}

/// 처음 붙을 때 아래에서 떠오르며 나타납니다. [since] 를 주면 그 시점부터 차례를 셉니다.
/// 목록이 다 그려진 뒤 스크롤로 새로 보이는 줄은 움직이지 않고 바로 보입니다.
class Appear extends StatefulWidget {
  const Appear({
    super.key,
    required this.index,
    required this.child,
    this.since,
    this.rise = 44,
  });

  final int index;
  final DateTime? since;
  final double rise;
  final Widget child;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  late final Animation<double> _eased = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutBack,
  );
  Timer? _wait;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final since = widget.since;
    final delay = reducedMotion(context)
        ? null
        : staggerDelay(
            widget.index,
            since == null ? Duration.zero : DateTime.now().difference(since),
          );
    if (delay == null) {
      _c.value = 1;
    } else if (delay == Duration.zero) {
      _c.forward();
    } else {
      _wait = Timer(delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _eased,
    builder: (_, child) => _c.isCompleted
        ? child!
        : Opacity(
            opacity: (_c.value * 2).clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, widget.rise * (1 - _eased.value)),
              child: Transform.scale(
                scale: .86 + .14 * _eased.value,
                child: child,
              ),
            ),
          ),
    child: widget.child,
  );
}

/// [on] 이 꺼짐에서 켜짐으로 바뀌면 아이를 톡 튀기고 둘레로 조각을 터뜨립니다.
class PopBurst extends StatefulWidget {
  const PopBurst({
    super.key,
    required this.on,
    required this.child,
    this.color = Palette.bad,
    this.sparks = 8,
    this.reach = 18,
  });

  final bool on;
  final Widget child;
  final Color color;
  final int sparks;
  final double reach;

  @override
  State<PopBurst> createState() => _PopBurstState();
}

class _PopBurstState extends State<PopBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
    value: 1,
  );

  @override
  void didUpdateWidget(PopBurst old) {
    super.didUpdateWidget(old);
    if (widget.on && !old.on && !reducedMotion(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) => CustomPaint(
      foregroundPainter: _c.value >= 1
          ? null
          : SparkPainter(
              t: _c.value,
              count: widget.sparks,
              reach: widget.reach,
              colors: [widget.color, Palette.butter],
              dot: 2.6,
            ),
      child: Transform.scale(scale: popScale(_c.value), child: child),
    ),
    child: widget.child,
  );
}

/// 가운데에서 조각을 퍼뜨려 그립니다. 하트 터짐과 짝짓기 축하 종이가 같이 씁니다.
class SparkPainter extends CustomPainter {
  SparkPainter({
    required this.t,
    required this.count,
    required this.reach,
    required this.colors,
    this.dot = 3,
    this.gravity = 0,
    this.confetti = false,
    this.seed = 0,
  });

  final double t;
  final int count;
  final double reach;
  final List<Color> colors;
  final double dot;
  final double gravity;
  final bool confetti;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final s = sparkAt(
        i,
        count,
        t,
        reach: reach,
        gravity: gravity,
        seed: seed,
      );
      if (s.opacity <= 0) continue;
      paint.color = colors[i % colors.length].withValues(alpha: s.opacity);
      final at = center + s.pos;
      if (confetti) {
        canvas
          ..save()
          ..translate(at.dx, at.dy)
          ..rotate(s.turn);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: dot * 2.2 * s.size + 2,
              height: dot * s.size + 1,
            ),
            const Radius.circular(1.5),
          ),
          paint,
        );
        canvas.restore();
      } else {
        canvas.drawCircle(at, dot * s.size, paint);
      }
    }
  }

  @override
  bool shouldRepaint(SparkPainter old) => old.t != t;
}

/// 지금 나오는 곡 옆에 들썩이는 막대입니다. 멈추면 낮게 가라앉고 시계도 멈춥니다.
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({
    super.key,
    required this.playing,
    this.color = Palette.ink,
    this.height = 12,
    this.bars = 3,
  });

  final bool playing;
  final Color color;
  final double height;
  final int bars;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  final _t = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker(
    (e) => _t.value = e.inMicroseconds / 1e6,
  );

  void _sync() {
    final run = widget.playing && !reducedMotion(context);
    if (run && !_ticker.isActive) _ticker.start();
    if (!run && _ticker.isActive) {
      _ticker.stop();
      _t.value = -1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size(widget.bars * 4.0 - 1.5, widget.height),
      painter: _BarsPainter(_t, widget.bars, widget.color),
    ),
  );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.t, this.bars, this.color) : super(repaint: t);

  final ValueNotifier<double> t;
  final int bars;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var i = 0; i < bars; i++) {
      final level = t.value < 0 ? 0.25 : eqLevel(i, t.value);
      final h = max(2.0, size.height * level);
      canvas.drawRRect(
        RRect.fromLTRBR(
          i * 4.0,
          size.height - h,
          i * 4.0 + 2.5,
          size.height,
          const Radius.circular(1.25),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.bars != bars || old.color != color;
}

/// [active] 동안 아이 둘레로 둥근 네모 고리가 천천히 퍼져 나갑니다. 기다리는 중임을 알립니다.
class PulseRings extends StatefulWidget {
  const PulseRings({
    super.key,
    required this.active,
    required this.child,
    this.spread = 22,
    this.radius = 20,
    this.color = Palette.butter,
  });

  final bool active;
  final Widget child;
  final double spread;
  final double radius;
  final Color color;

  @override
  State<PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<PulseRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  void _sync() {
    final run = widget.active && !reducedMotion(context);
    if (run && !_c.isAnimating) _c.repeat();
    if (!run && _c.isAnimating) _c.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PulseRings old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: widget.active
        ? _RingsPainter(_c, widget.spread, widget.radius, widget.color)
        : null,
    child: widget.child,
  );
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.anim, this.spread, this.radius, this.color)
    : super(repaint: anim);

  final Animation<double> anim;
  final double spread;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final lag in [0.0, 0.5]) {
      final r = pulseRing(anim.value + lag);
      if (r.opacity <= 0) continue;
      paint.color = color.withValues(alpha: r.opacity);
      final grow = spread * r.grow;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.inflate(grow),
          Radius.circular(radius + grow),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.color != color || old.spread != spread;
}

/// 한 번 터지고 끝나는 축하 종이입니다. 붙는 순간 터지고 다 떨어지면 그리지 않습니다.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, this.reach = 150, this.pieces = 28});

  final double reach;
  final int pieces;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    if (reducedMotion(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          size: Size.infinite,
          painter: _c.value >= 1
              ? null
              : SparkPainter(
                  t: _c.value,
                  count: widget.pieces,
                  reach: widget.reach,
                  gravity: 90,
                  confetti: true,
                  dot: 5,
                  seed: 7,
                  colors: const [
                    Palette.butter,
                    Palette.good,
                    Color(0xFFB9C8F0),
                    Color(0xFFF4B6C2),
                    Palette.ink,
                  ],
                ),
        ),
      ),
    ),
  );
}
