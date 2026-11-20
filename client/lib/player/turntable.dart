import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../l10n.dart';

/// 턴테이블 한 판입니다. 판을 돌리면 앞뒤로 옮기고, 튕기면 빨리 돌고, 톡 치면 재생과 멈춤이 바뀝니다.
/// 바늘을 판 위로 끌어 내리면 그 자리부터 재생합니다. 설계 좌표 350x342 로 그리고 바깥에서 크기를 맞춥니다.
class Turntable extends StatefulWidget {
  const Turntable({super.key, required this.ctl, required this.onHint});

  final PlayerController ctl;
  final ValueChanged<String> onHint;

  static const size = Size(350, 342);

  @override
  State<Turntable> createState() => TurntableState();
}

class TurntableState extends State<Turntable> with TickerProviderStateMixin {
  static const _normalSpeed = 200.0; // 도/초
  static const _discLeft = 14.0, _discTop = 34.0, _disc = 272.0;
  static const _pivot = Offset(310, 34);
  static const _armRest = 0.0,
      _armStart = 20.0,
      _armSpan = 18.0,
      _armMax = 40.0;

  late final Ticker _ticker = createTicker(_tick);
  late final AnimationController _swap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  Duration _last = Duration.zero;

  double _rot = 0, _speed = 0, _arm = 0;
  bool _armDragging = false;
  double? _lastAngle;
  double _moved = 0;
  final List<(double, int)> _samples = [];

  double _swapFrom = 0, _swapTo = 0;
  Curve _swapCurve = Curves.linear;
  bool _swapping = false;

  PlayerController get _c => widget.ctl;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _swap.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = min(0.05, (now - _last).inMicroseconds / 1e6);
    _last = now;
    if (_lastAngle == null) {
      final target = _c.playing ? _normalSpeed : 0.0;
      final ease = _speed.abs() > _normalSpeed ? 1.2 : 3.0;
      _speed += (target - _speed) * min(1.0, dt * ease);
      _rot = (_rot + _speed * dt) % 360;
    }
    if (!_armDragging) {
      final target = _c.playing ? _armStart + _armSpan * _c.progress : _armRest;
      _arm += (target - _arm) * min(1.0, dt * 8);
    }
    setState(() {});
  }

  /// 판을 갈아 끼웁니다. 지금 판이 반대쪽으로 날아가고 새 판이 들어와 앉습니다.
  Future<void> swap(int dir) async {
    if (_swapping || _c.queue.isEmpty) return;
    _swapping = true;
    HapticFeedback.selectionClick();
    _swapFrom = 0;
    _swapTo = -dir * 380;
    _swapCurve = Curves.easeInCubic;
    await _swap.forward(from: 0);
    await _c.skip(dir);
    _swapFrom = dir * 380;
    _swapTo = 0;
    _swapCurve = Curves.easeOutBack;
    await _swap.forward(from: 0);
    _swapping = false;
  }

  double get _swapX =>
      lerpDouble(_swapFrom, _swapTo, _swapCurve.transform(_swap.value))!;

  double _angleAt(Offset local) =>
      atan2(local.dy - _disc / 2, local.dx - _disc / 2) * 180 / pi;

  void _discStart(DragStartDetails d) {
    _lastAngle = _angleAt(d.localPosition);
    _moved = 0;
    _samples.clear();
    _c.scrubTo(_c.shownSecs);
  }

  void _discUpdate(DragUpdateDetails d) {
    final angle = _angleAt(d.localPosition);
    var delta = angle - _lastAngle!;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    _lastAngle = angle;
    _moved += delta.abs();
    _rot = (_rot + delta) % 360;
    final now = DateTime.now().millisecondsSinceEpoch;
    _samples
      ..add((delta, now))
      ..removeWhere((s) => now - s.$2 > 100);
    _c.scrubTo(_c.shownSecs + delta / _normalSpeed * 1.5);
    widget.onHint(
      delta < 0 ? S.of(context).rewinding : S.of(context).forwarding,
    );
  }

  void _discEnd(DragEndDetails _) {
    final span = _samples.fold<double>(0, (a, s) => a + s.$1);
    _speed = (span * 10).clamp(-900.0, 1400.0);
    _lastAngle = null;
    final target = _c.scrubbing;
    _c.scrubTo(null);
    if (target != null && _moved >= 3) _c.seekSecs(target);
    widget.onHint(
      _speed > 400
          ? S.of(context).spunFast
          : (_c.playing ? S.of(context).playing : S.of(context).tapToPlay),
    );
  }

  double _armAngleAt(Offset local) {
    final p = local + const Offset(250, 0) - _pivot;
    return (atan2(-p.dx, p.dy) * 180 / pi).clamp(0.0, _armMax);
  }

  void _armUpdate(Offset local) {
    _armDragging = true;
    _arm = _armAngleAt(local);
    final onRecord = _arm >= _armStart;
    if (onRecord) {
      _c.scrubTo(min(1.0, (_arm - _armStart) / _armSpan) * _c.durationSecs);
    }
    widget.onHint(
      onRecord ? S.of(context).playFromHere : S.of(context).offRecord,
    );
  }

  void _armEnd() {
    _armDragging = false;
    final target = _c.scrubbing;
    _c.scrubTo(null);
    if (_arm >= _armStart && target != null) {
      HapticFeedback.lightImpact();
      _c.seekSecs(target).then((_) => _c.play());
      widget.onHint(S.of(context).playing);
    } else {
      _c.pause();
      widget.onHint(S.of(context).armLifted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = _c.current;
    final sx = _swapX;
    return Container(
      width: Turntable.size.width,
      height: Turntable.size.height,
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F16161A),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          Positioned(
            left: _discLeft,
            top: _discTop,
            width: _disc,
            height: _disc,
            child: Transform.translate(
              offset: Offset(sx, 0),
              child: Transform.rotate(
                angle: sx / 8 * pi / 180,
                child: GestureDetector(
                  onTap: () {
                    _c.toggle();
                    widget.onHint(
                      _c.playing ? S.of(context).playing : S.of(context).paused,
                    );
                  },
                  onPanStart: _discStart,
                  onPanUpdate: _discUpdate,
                  onPanEnd: _discEnd,
                  child: _Disc(rotation: _rot, track: track, api: _c.api),
                ),
              ),
            ),
          ),
          Positioned(
            left: _pivot.dx - 30,
            top: _pivot.dy,
            width: 60,
            height: 220,
            child: IgnorePointer(
              child: Transform.rotate(
                angle: _arm * pi / 180,
                alignment: Alignment.topCenter,
                child: const _Arm(),
              ),
            ),
          ),
          Positioned(
            left: _pivot.dx - 18,
            top: _pivot.dy - 18,
            child: const _Pivot(),
          ),
          Positioned(
            left: 250,
            top: 0,
            width: 100,
            height: 330,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (d) => _armUpdate(d.localPosition),
              onPanUpdate: (d) => _armUpdate(d.localPosition),
              onPanEnd: (_) => _armEnd(),
              onPanCancel: _armEnd,
            ),
          ),
        ],
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({required this.rotation, required this.track, required this.api});

  final double rotation;
  final Track? track;
  final Api api;

  @override
  Widget build(BuildContext context) {
    final t = track;
    final label = t == null
        ? const ColoredBox(color: Palette.butter)
        : t.hasCover
        ? Image.network(
            api.coverUri(t.id).toString(),
            headers: api.headers,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _Letter(t),
          )
        : _Letter(t);
    return DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Palette.ink,
        boxShadow: [
          BoxShadow(
            color: Color(0x38161A1A),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: rotation * pi / 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Positioned.fill(child: CustomPaint(painter: _Grooves())),
                SizedBox.square(dimension: 92, child: ClipOval(child: label)),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Palette.ground,
            ),
          ),
        ],
      ),
    );
  }
}

class _Letter extends StatelessWidget {
  const _Letter(this.track);
  final Track track;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Palette.butter,
    child: Center(child: Text(track.letter, style: letterStyle(40))),
  );
}

class _Grooves extends CustomPainter {
  const _Grooves();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x12FFFFFF);
    for (final inset in [22.0, 44.0, 66.0]) {
      canvas.drawCircle(center, size.width / 2 - inset, groove);
    }
    canvas.drawCircle(
      Offset(center.dx, 24),
      2,
      Paint()..color = const Color(0x59FFFFFF),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Arm extends StatelessWidget {
  const _Arm();

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned(
        left: 28,
        top: 0,
        width: 4,
        height: 196,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFC9C7C0),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
      Positioned(
        left: 22,
        top: 188,
        width: 16,
        height: 26,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Palette.ink,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    ],
  );
}

class _Pivot extends StatelessWidget {
  const _Pivot();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Palette.sunk,
        border: Border.all(color: Palette.line2),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Palette.butter,
        ),
      ),
    ),
  );
}
