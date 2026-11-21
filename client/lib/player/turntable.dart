import 'dart:async';

import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../l10n.dart';
import '../widgets/skeleton.dart';
import 'turntable_motion.dart';

/// 턴테이블 한 판입니다. 판을 돌리면 앞뒤로 옮기고, 튕기면 빨리 돌고, 톡 치면 재생과 멈춤이 바뀝니다.
/// 바늘을 판 위로 끌어 내리면 그 자리부터 재생합니다. 설계 좌표 350x342 로 그리고 바깥에서 크기를 맞춥니다.
///
/// 움직임은 티커 하나가 [_frame] 을 두드려 그 값을 보는 조각만 다시 그립니다. 화면 전체를 매 프레임
/// 다시 짓지 않고, 모두 멈추면 티커도 쉽니다.
class Turntable extends StatefulWidget {
  const Turntable({
    super.key,
    required this.ctl,
    required this.onHint,
    this.stage,
  });

  final PlayerController ctl;
  final ValueChanged<String> onHint;

  /// 판을 갈 때 판이 날아다닐 무대입니다. 넓은 화면에서는 오른쪽 재생 칸, 폰에서는 화면 전체가 됩니다.
  final GlobalKey? stage;

  static const size = Size(350, 342);

  @override
  State<Turntable> createState() => TurntableState();
}

class TurntableState extends State<Turntable> with TickerProviderStateMixin {
  static const _discLeft = 14.0, _discTop = 34.0, _disc = 272.0;
  static const _pivot = Offset(310, 34);

  late final Ticker _ticker = createTicker(_tick);
  late final AnimationController _swap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  final _frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;
  double _clock = 0;
  bool _reduce = false;

  double _rot = 0, _speed = 0;
  double _arm = armRest, _armVel = 0;
  double _lift = 0, _liftVel = 0;
  double _rumbleT = rumbleSecs;
  bool _down = false;
  bool _armDragging = false;
  bool _snapped = false;
  double _holdArm = armRest, _holdUntil = 0;

  double? _lastAngle;
  double _moved = 0;
  int? _tickCell;
  final List<(double, int)> _samples = [];

  String? _trackId;
  bool _wasPlaying = false;

  bool _swapping = false;

  /// 판을 갈아 끼우는 동안 바늘을 받침으로 치워 둡니다.
  bool _armAway = false;

  /// 판을 갈아 끼우는 동안 데크 밖(화면 전체)을 날아다니는 판입니다. 그동안 데크 위의 판은 숨깁니다.
  final _discKey = GlobalKey();
  OverlayEntry? _flying;
  Rect _stage = Rect.zero;
  bool _discHidden = false;

  PlayerController get _c => widget.ctl;

  @override
  void initState() {
    super.initState();
    // 화면에 다시 들어왔을 때 이미 재생 중이면 바늘과 판이 제자리에 있는 채로 시작합니다.
    _wasPlaying = _c.playing;
    _trackId = _c.current?.id;
    _arm = armAngleFor(playing: _wasPlaying, progress: _c.progress);
    _down = _wasPlaying;
    _speed = _wasPlaying ? normalSpeed : 0;
    _c.addListener(_onCtl);
  }

  @override
  void didUpdateWidget(Turntable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ctl != widget.ctl) {
      oldWidget.ctl.removeListener(_onCtl);
      widget.ctl.addListener(_onCtl);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onCtl);
    _ticker.dispose();
    _flying?.remove();
    _swap.dispose();
    _frame.dispose();
    super.dispose();
  }

  /// 곡이 바뀌면 묵직하게, 멈추면(바늘이 들리면) 가볍게 손끝을 칩니다.
  void _onCtl() {
    final id = _c.current?.id;
    if (id != _trackId) {
      if (_trackId != null && id != null) HapticFeedback.heavyImpact();
      _trackId = id;
    }
    final playing = _c.playing;
    if (_wasPlaying && !playing) HapticFeedback.lightImpact();
    _wasPlaying = playing;
    _wake();
  }

  void _wake() {
    if (_ticker.isActive) return;
    _last = Duration.zero;
    _ticker.start();
  }

  double get _armTarget => _armAway
      ? armRest
      : !_c.playing && _clock < _holdUntil
      ? _holdArm
      : armAngleFor(playing: _c.playing, progress: _c.progress);

  void _tick(Duration elapsed) {
    final dt = min(0.05, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    _clock += dt;
    final target = _armTarget;
    if (_reduce) {
      if (_lastAngle == null) _speed = 0;
      if (!_armDragging) _arm = target;
      _armVel = _lift = _liftVel = 0;
      _rumbleT = rumbleSecs;
    } else {
      if (_lastAngle == null) {
        _speed = spinStep(_speed, _c.playing ? normalSpeed : 0, dt);
        _rot = (_rot + _speed * dt) % 360;
      }
      if (!_armDragging) {
        final a = springStep(
          _arm,
          _armVel,
          target,
          dt,
          stiffness: 70,
          dampingRatio: 0.72,
        );
        _arm = a.pos;
        _armVel = a.vel;
      }
      final l = springStep(
        _lift,
        _liftVel,
        liftTarget(armGap: _arm - target, dragging: _armDragging),
        dt,
        stiffness: 260,
        dampingRatio: 0.32,
      );
      _lift = l.pos;
      _liftVel = l.vel;
      _rumbleT += dt;
    }
    _touchdown();
    _frame.value++;
    if (_reduce || _settled(target)) _ticker.stop();
  }

  /// 바늘이 판 위에 내려앉는 순간 손끝을 치고 판을 짧게 떨게 합니다.
  void _touchdown() {
    final down = !_armDragging && _lift < 0.25 && _arm >= armStart - 0.5;
    if (down && !_down) {
      HapticFeedback.mediumImpact();
      if (!_reduce) _rumbleT = 0;
    }
    _down = down;
  }

  bool _settled(double target) {
    if (_c.playing || _armDragging || _lastAngle != null) return false;
    final still =
        _speed == 0 &&
        (_arm - target).abs() < 0.01 &&
        _armVel.abs() < 0.01 &&
        _lift.abs() < 0.002 &&
        _liftVel.abs() < 0.01 &&
        _rumbleT >= rumbleSecs &&
        _clock >= _holdUntil &&
        !_swap.isAnimating;
    if (still) {
      _arm = target;
      _armVel = _lift = _liftVel = 0;
    }
    return still;
  }

  /// 손끝 틱입니다. 위치가 [scrubTickSecs] 칸을 넘을 때마다 한 번 칩니다.
  void _scrubTick(double secs) {
    final cell = scrubTick(secs);
    if (_tickCell != null && cell != _tickCell) HapticFeedback.selectionClick();
    _tickCell = cell;
  }

  /// 판을 갈아 끼웁니다. 지금 판이 들려 올라 화면 끝까지 날아가고,
  /// 새 판이 반대쪽 화면 끝에서 날아와 플래터에 툭 내려앉습니다.
  Future<void> swap(int dir) async {
    if (_swapping || _c.queue.isEmpty) return;
    final box = _discKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (_reduce || box == null || overlay == null || !box.attached) {
      await _c.skip(dir);
      return;
    }
    _swapping = true;
    final home = box.localToGlobal(Offset.zero) & box.size;
    final stageBox =
        widget.stage?.currentContext?.findRenderObject() as RenderBox?;
    final stage = stageBox != null && stageBox.attached
        ? stageBox.localToGlobal(Offset.zero) & stageBox.size
        : Offset.zero & MediaQuery.sizeOf(context);
    // 다음 곡이면 지금 판이 왼쪽으로, 이전 곡이면 오른쪽으로 무대 밖까지 나갑니다.
    final outX = dir > 0 ? stage.left - home.width - 40 : stage.right + 40;
    final inX = dir > 0 ? stage.right + 40 : stage.left - home.width - 40;
    _stage = stage;
    final wasPlaying = _c.playing;
    var skipped = false;
    try {
      // 바늘을 먼저 들어 받침으로 치우고, 판을 바꾼 뒤 다시 올립니다.
      _c.pause();
      _armAway = true;
      _wake();
      HapticFeedback.lightImpact();
      await Future<void>.delayed(const Duration(milliseconds: 380));
      if (!mounted) return;
      await _fly(overlay, home, toX: outX, leaving: true, dir: dir);
      skipped = true;
      await _c.skip(dir, play: false);
      if (!mounted) return;
      await _fly(overlay, home, toX: inX, leaving: false, dir: dir);
    } finally {
      // 애니메이션이 어떻게 끝나든 곡은 반드시 넘기고 판과 바늘을 제자리로 돌립니다.
      _flying?.remove();
      _flying = null;
      if (!skipped) unawaited(_c.skip(dir, play: false));
      _swapping = false;
      _armAway = false;
      if (mounted) {
        setState(() => _discHidden = false);
        _rumbleT = 0;
        _wake();
      }
      if (wasPlaying) _c.play();
    }
  }

  /// 판 하나를 화면 위로 날립니다. leaving 이면 제자리에서 toX 로, 아니면 toX 에서 제자리로 옵니다.
  Future<void> _fly(
    OverlayState overlay,
    Rect home, {
    required double toX,
    required bool leaving,
    required int dir,
  }) async {
    final track = _c.current;
    _swap.duration = Duration(milliseconds: leaving ? 520 : 760);
    _flying?.remove();
    final stage = _stage;
    _flying = OverlayEntry(
      // 무대 밖은 잘라서, 넓은 화면에서도 판이 재생 칸을 벗어나 다른 화면 위로 지나가지 않습니다.
      builder: (context) => Positioned.fromRect(
        rect: stage,
        child: ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              AnimatedBuilder(
                animation: _swap,
                builder: (context, child) {
                  final t = _swap.value;
                  final e = leaving
                      ? Curves.easeInCubic.transform(t)
                      : Curves.easeOutBack.transform(t);
                  // 나갈 때는 0→1, 들어올 때는 1→0 으로 제자리에서 멀어진 정도입니다.
                  final away = leaving ? e : 1 - e;
                  final x = lerpDouble(home.left, toX, away)!;
                  // 손으로 들어 올린 판처럼 가운데서 위로 둥글게 떴다가 내려옵니다.
                  final y = home.top - 150 * sin(pi * away.clamp(0.0, 1.0));
                  final lift = leaving
                      ? Curves.easeOut.transform((t * 3).clamp(0.0, 1.0))
                      : 1 -
                            Curves.easeIn.transform(
                              ((t - 0.7) / 0.3).clamp(0.0, 1.0),
                            );
                  final scale = 1 + 0.18 * lift;
                  // 한 바퀴 반을 돌며 날아갑니다.
                  final spin = -dir * 540 * away * pi / 180;
                  return Positioned(
                    left: x - stage.left,
                    top: y - stage.top,
                    width: home.width,
                    height: home.height,
                    child: IgnorePointer(
                      child: Transform.rotate(
                        angle: spin,
                        child: Transform.scale(
                          scale: scale,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0x3316161A),
                                  blurRadius: 10 + 26 * lift,
                                  offset: Offset(0, 4 + 18 * lift),
                                ),
                              ],
                            ),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: _Disc(motion: this, track: track, api: _c.api),
              ),
            ],
          ),
        ),
      ),
    );
    overlay.insert(_flying!);
    if (!_discHidden) setState(() => _discHidden = true);
    // 화면이 멈춰 틱이 오지 않아도 곡 넘기기가 묶이지 않도록 시간을 정해 둡니다.
    await _swap
        .forward(from: 0)
        .orCancel
        .timeout(_swap.duration! * 3)
        .catchError((Object _) {});
    _flying?.remove();
    _flying = null;
  }

  double _angleAt(Offset local) =>
      atan2(local.dy - _disc / 2, local.dx - _disc / 2) * 180 / pi;

  void _discStart(DragStartDetails d) {
    _lastAngle = _angleAt(d.localPosition);
    _moved = 0;
    _tickCell = null;
    _samples.clear();
    _c.scrubTo(_c.shownSecs);
    _wake();
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
    _c.scrubTo(_c.shownSecs + delta / normalSpeed * 1.5);
    _scrubTick(_c.shownSecs);
    widget.onHint(
      delta < 0 ? S.of(context).rewinding : S.of(context).forwarding,
    );
  }

  void _discEnd(DragEndDetails _) {
    // 손을 뗀 순간의 빠르기를 그대로 이어받아 판이 관성으로 더 돌다 제 속도로 돌아옵니다.
    final span = _samples.fold<double>(0, (a, s) => a + s.$1);
    _speed = (span * 10).clamp(-900.0, 1400.0);
    _lastAngle = null;
    _tickCell = null;
    final target = _c.scrubbing;
    _c.scrubTo(null);
    if (target != null && _moved >= 3) _c.seekSecs(target);
    _wake();
    widget.onHint(
      _speed > 400
          ? S.of(context).spunFast
          : (_c.playing ? S.of(context).playing : S.of(context).tapToPlay),
    );
  }

  double _armAngleAt(Offset local) {
    final p = local + const Offset(250, 0) - _pivot;
    return (atan2(-p.dx, p.dy) * 180 / pi).clamp(0.0, armMax);
  }

  void _armUpdate(Offset local) {
    if (!_armDragging) setState(() => _armDragging = true);
    final raw = _armAngleAt(local);
    final at = armDropFraction(raw);
    final snapped = at == 0;
    // 처음 근처에 들고 오면 바늘이 바깥 홈에 딸깍 붙습니다.
    _arm = snapped ? armStart : raw;
    _armVel = 0;
    if (at != null) {
      final secs = at * _c.durationSecs;
      _c.scrubTo(secs);
      if (snapped && !_snapped) {
        HapticFeedback.mediumImpact();
      } else if (!snapped) {
        _scrubTick(secs);
      }
    } else {
      _tickCell = null;
    }
    _snapped = snapped;
    _wake();
    final s = S.of(context);
    widget.onHint(
      snapped ? s.playFromStart : (at != null ? s.playFromHere : s.offRecord),
    );
  }

  void _armEnd() {
    if (_armDragging) setState(() => _armDragging = false);
    _snapped = false;
    _tickCell = null;
    final target = _c.scrubbing;
    _c.scrubTo(null);
    _wake();
    if (_arm >= armStart && target != null) {
      // 재생이 붙기 전에 바늘이 받침으로 끌려가지 않도록 잠시 놓은 자리를 지킵니다.
      _holdArm = _arm;
      _holdUntil = _clock + 1.5;
      _c.seekSecs(target).then((_) => _c.play());
      widget.onHint(S.of(context).playing);
    } else {
      _holdUntil = 0;
      _c.pause();
      widget.onHint(S.of(context).armLifted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce != _reduce) {
      _reduce = reduce;
      _wake();
    }
    final track = _c.current;
    final deck = Container(
      width: Turntable.size.width,
      height: Turntable.size.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_Deck.top, _Deck.bottom],
        ),
        border: Border.all(color: _Deck.edge),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2916161A),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          // 오른쪽 아래의 전원 불빛과 회전수 표시입니다. 돌 때 불빛이 켜집니다.
          Positioned(right: 22, bottom: 18, child: _PowerLamp(on: _c.playing)),
          Positioned(
            left: _discLeft,
            top: _discTop,
            width: _disc,
            height: _disc,
            child: Opacity(
              key: _discKey,
              opacity: _discHidden ? 0 : 1,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
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
                  child: _Disc(motion: this, track: track, api: _c.api),
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
              child: ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (context, _, _) {
                  final wobble = _reduce || !_c.playing
                      ? 0.0
                      : armWobble(_clock, _rot) * (1 - _lift).clamp(0.0, 1.0);
                  return Transform.rotate(
                    angle: (_arm + wobble) * pi / 180,
                    alignment: Alignment.topCenter,
                    child: CustomPaint(painter: _ArmPainter(_lift)),
                  );
                },
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _armDragging ? 1 : 0,
                duration: Duration(milliseconds: _armDragging ? 140 : 360),
                child: ValueListenableBuilder<int>(
                  valueListenable: _frame,
                  builder: (context, _, _) => CustomPaint(
                    painter: _DropGuide(
                      pivot: _pivot,
                      arm: _arm,
                      snapped: _snapped,
                      startLabel: '${S.of(context).guideStart} 0:00',
                      endLabel:
                          '${S.of(context).guideEnd} ${formatTime(_c.durationSecs)}',
                      nowLabel: formatTime(_c.shownSecs),
                    ),
                  ),
                ),
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
    return RepaintBoundary(
      child: ValueListenableBuilder<int>(
        valueListenable: _frame,
        builder: (context, _, child) =>
            Transform.translate(offset: rumbleOffset(_rumbleT), child: child),
        child: deck,
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({required this.motion, required this.track, required this.api});

  final TurntableState motion;
  final Track? track;
  final Api api;

  @override
  Widget build(BuildContext context) {
    final t = track;
    final label = RepaintBoundary(
      child: SizedBox.square(
        dimension: 92,
        child: ClipOval(
          child: t == null
              ? const ColoredBox(color: Palette.butter)
              : t.hasCover
              ? CoverImage(
                  url: api.coverUri(t.id).toString(),
                  headers: api.headers,
                  fallback: _Letter(t),
                  // 도는 판 위라 빛줄기 대신 슬리브 색을 깔아 두고 표지가 그 위로 떠오릅니다.
                  placeholder: ColoredBox(color: Palette.sleeveOf(t.id)),
                  shimmer: false,
                )
              : _Letter(t),
        ),
      ),
    );
    const grooves = RepaintBoundary(
      child: SizedBox.expand(child: CustomPaint(painter: _Grooves())),
    );
    const spindle = SizedBox.square(
      dimension: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Palette.ground,
        ),
      ),
    );
    return ValueListenableBuilder<int>(
      valueListenable: motion._frame,
      builder: (context, _, _) {
        final m = motion;
        final spin = (m._speed.abs() / normalSpeed).clamp(0.0, 1.0);
        final b = m._reduce ? 0.0 : breath(m._clock) * spin;
        final turn = m._rot * pi / 180;
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF111113),
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(22, 26, 26, 0.22 - 0.05 * b),
                blurRadius: 22 + 8 * b,
                offset: Offset(0, 8 + 3 * b),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(angle: turn, child: grooves),
              Positioned.fill(
                child: CustomPaint(
                  painter: _Sheen(
                    strength: 0.55 + 0.45 * spin,
                    drift: m._reduce ? 0 : 0.18 * sin(m._clock * 0.7),
                  ),
                ),
              ),
              Transform.rotate(angle: turn, child: label),
              spindle,
            ],
          ),
        );
      },
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

/// 판의 홈입니다. 한 번 그려 두고 돌리기만 합니다. 아주 가는 홈을 촘촘히 긋고,
/// 곡 사이의 빈 띠 몇 줄과 끊긴 반사 호를 섞어 판이 도는 게 보이게 합니다.
class _Grooves extends CustomPainter {
  const _Grooves();

  static const _labelEdge = 50.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.width / 2;
    // 가장자리 테두리와 소리골이 시작하기 전의 매끈한 띠입니다.
    canvas.drawCircle(
      center,
      outer - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x14FFFFFF),
    );
    final fine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    var i = 0;
    for (var r = outer - 8; r > _labelEdge + 8; r -= 1.7, i++) {
      fine.color = Color.fromRGBO(255, 255, 255, i.isEven ? 0.055 : 0.028);
      canvas.drawCircle(center, r, fine);
    }
    // 곡 사이 빈 띠입니다. 홈이 없어 조금 더 검고 매끈합니다.
    final gap = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = const Color(0xFF0C0C0E);
    for (final inset in const [30.0, 52.0, 71.0]) {
      canvas.drawCircle(center, outer - inset, gap);
    }
    // 소리골이 끝나고 라벨까지 이어지는 매끈한 띠입니다.
    canvas.drawCircle(
      center,
      _labelEdge + 5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = const Color(0xFF0E0E10),
    );
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x24FFFFFF);
    for (final (inset, from, sweep) in const [
      (18.0, 0.4, 0.7),
      (40.0, 2.6, 0.5),
      (61.0, 4.4, 0.8),
      (80.0, 1.5, 0.5),
    ]) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: outer - inset),
        from,
        sweep,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 판 위의 빛입니다. 조명은 제자리라 돌지 않고, 판이 돌면 조금 밝아지며 천천히 일렁입니다.
class _Sheen extends CustomPainter {
  const _Sheen({required this.strength, required this.drift});

  final double strength;
  final double drift;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.width / 2 - 4;
    final light = Color.fromRGBO(255, 255, 255, 0.10 * strength);
    const clear = Color(0x00FFFFFF);
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: center, radius: outer))
      ..addOval(Rect.fromCircle(center: center, radius: 50));
    final paint = Paint()
      ..shader = SweepGradient(
        transform: GradientRotation(-pi * 0.75 + drift),
        colors: [clear, light, clear, clear, light, clear, clear],
        stops: const [0.0, 0.07, 0.16, 0.5, 0.57, 0.66, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: outer));
    canvas.drawPath(ring, paint);
  }

  @override
  bool shouldRepaint(_Sheen old) =>
      old.strength != strength || old.drift != drift;
}

/// 톤암입니다. 은색 봉이 중간에서 한 번 꺾여 흰 헤드로 이어집니다.
/// 들릴수록 그림자가 멀어지고 헤드가 조금 커 보여서 떠 있는 게 느껴집니다.
/// 바늘 끝은 (30, 207) 에 있어야 바늘 안내선과 맞습니다.
class _ArmPainter extends CustomPainter {
  const _ArmPainter(this.lift);

  final double lift;

  static const _tip = Offset(30, 207);
  // 봉은 거의 곧게 내려오다 끝에서만 J자로 휘고, 흰 헤드가 휜 방향을 그대로 잇습니다.
  static const _end = Offset(40.5, 184.7);
  static const _headTurn = 0.441; // 헤드가 붙는 기울기(라디안)입니다.
  static const _headScale = 0.95;
  static final _rod = Path()
    ..moveTo(30, 0)
    ..lineTo(47.8, 130.4)
    ..quadraticBezierTo(51.7, 160.7, _end.dx, _end.dy);
  // 헤드는 봉 끝(_end)에서 아래로 26만큼 뻗고, 그 끝이 바늘 끝(_tip)입니다.
  static final _head = RRect.fromRectAndRadius(
    const Rect.fromLTWH(-7, -2, 14, 26),
    const Radius.circular(4),
  );
  static final _stylus = RRect.fromRectAndRadius(
    const Rect.fromLTWH(-4.5, 24, 9, 4),
    const Radius.circular(1.5),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final up = lift.clamp(-0.2, 1.2);
    final away = Offset(2 + 6 * max(0.0, up), 3 + 7 * max(0.0, up));
    final shadow = Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    final rod = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(_rod.shift(away), rod.withShadow(shadow, 4))
      ..drawPath(_rod, rod.withColor(const Color(0xFFB9BCC2), 4))
      ..drawPath(_rod, rod.withColor(const Color(0xFFECEDEF), 1.4));
    // 들어 올리면 헤드가 살짝 커 보입니다. 바늘 끝을 축으로 키워 끝 자리는 그대로 둡니다.
    final grow = 1 + 0.08 * up;
    void headAt(Offset shift, void Function() draw) {
      canvas
        ..save()
        ..translate(_tip.dx + shift.dx, _tip.dy + shift.dy)
        ..scale(grow)
        ..translate(_end.dx - _tip.dx, _end.dy - _tip.dy)
        ..rotate(_headTurn)
        ..scale(_headScale);
      draw();
      canvas.restore();
    }

    headAt(away, () => canvas.drawRRect(_head, shadow));
    headAt(Offset.zero, () {
      canvas
        ..drawRRect(_stylus, Paint()..color = const Color(0xFFB9BCC2))
        ..drawRRect(_head, Paint()..color = const Color(0xFFF4F3EF))
        ..drawRRect(
          _head.deflate(0.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFFCFCDC6),
        );
    });
  }

  @override
  bool shouldRepaint(_ArmPainter old) => old.lift != lift;
}

extension on Paint {
  Paint withColor(Color c, double width) => Paint()
    ..style = style
    ..strokeCap = strokeCap
    ..strokeJoin = strokeJoin
    ..strokeWidth = width
    ..color = c;

  Paint withShadow(Paint shadow, double width) => Paint()
    ..style = style
    ..strokeCap = strokeCap
    ..strokeJoin = strokeJoin
    ..strokeWidth = width
    ..color = shadow.color
    ..maskFilter = shadow.maskFilter;
}

class _Pivot extends StatelessWidget {
  const _Pivot();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF55565D),
        boxShadow: [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Container(
        width: 14,
        height: 14,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: Alignment(-0.3, -0.3),
            colors: [Color(0xFFFFFFFF), Color(0xFFC9CACE)],
          ),
        ),
      ),
    ),
  );
}

/// 턴테이블 몸체 색입니다. 판보다 한 톤 밝은 짙은 회색입니다.
abstract final class _Deck {
  static const top = Color(0xFF2E2E34);
  static const bottom = Color(0xFF26262B);
  static const edge = Color(0xFF3A3A41);
}

/// 전원 불빛과 회전수 칸입니다.
class _PowerLamp extends StatelessWidget {
  const _PowerLamp({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? Palette.butter : const Color(0xFF6B5A2E),
            boxShadow: [
              if (on)
                BoxShadow(
                  color: Palette.butter.withValues(alpha: .6),
                  blurRadius: 8,
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 34,
          height: 12,
          decoration: BoxDecoration(
            color: const Color(0xFF3C3C44),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    ),
  );
}

/// 바늘을 들고 있는 동안 판 위에 바늘 끝이 지나는 길을 그립니다.
/// 처음(바깥 홈)과 끝(안쪽 홈)에 표시를 두고, 지금 자리의 시간을 바늘 끝 옆에 띄웁니다.
class _DropGuide extends CustomPainter {
  _DropGuide({
    required this.pivot,
    required this.arm,
    required this.snapped,
    required this.startLabel,
    required this.endLabel,
    required this.nowLabel,
  });

  final Offset pivot;
  final double arm;
  final bool snapped;
  final String startLabel, endLabel, nowLabel;

  static const _rad = pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: pivot, radius: armTipReach);
    // 각도 θ 의 바늘 끝은 축에서 (θ + 90)도 방향에 있습니다.
    final from = (armStart + 90) * _rad;
    final onRecord = arm >= armStart;
    canvas.drawArc(
      rect,
      from,
      armSpan * _rad,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 12
        ..color = Palette.butter.withValues(alpha: 0.28),
    );
    if (onRecord && !snapped) {
      canvas.drawArc(
        rect,
        from,
        min(arm - armStart, armSpan) * _rad,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 5
          ..color = Palette.butter,
      );
    }

    final start = armTip(pivot, armStart);
    final end = armTip(pivot, armStart + armSpan);
    if (snapped) {
      canvas.drawCircle(
        start,
        16,
        Paint()..color = Palette.butter.withValues(alpha: 0.45),
      );
    }
    canvas
      ..drawCircle(start, snapped ? 9 : 7, Paint()..color = Palette.butter)
      ..drawCircle(
        start,
        snapped ? 9 : 7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Palette.ink,
      )
      ..drawCircle(end, 5.5, Paint()..color = Palette.surface)
      ..drawCircle(end, 3.5, Paint()..color = Palette.ink);

    _pill(
      canvas,
      startLabel,
      start + const Offset(14, 10),
      Palette.butter,
      Palette.ink,
      bold: snapped,
    );
    _pill(
      canvas,
      endLabel,
      end + const Offset(-12, 12),
      Palette.surface,
      Palette.ink,
      alignRight: true,
    );
    if (onRecord && !snapped) {
      _pill(
        canvas,
        nowLabel,
        armTip(pivot, arm) + const Offset(-14, -30),
        Palette.ink,
        Palette.butter,
        alignRight: true,
        bold: true,
      );
    }
  }

  void _pill(
    Canvas canvas,
    String text,
    Offset at,
    Color bg,
    Color fg, {
    bool alignRight = false,
    bool bold = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: fg,
          fontSize: 11.5,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = Rect.fromLTWH(
      alignRight ? at.dx - tp.width - 16 : at.dx,
      at.dy,
      tp.width + 16,
      tp.height + 8,
    );
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          box.shift(const Offset(0, 1.5)),
          const Radius.circular(100),
        ),
        Paint()..color = const Color(0x2616161A),
      )
      ..drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(100)),
        Paint()..color = bg,
      );
    tp.paint(canvas, box.topLeft + const Offset(8, 4));
  }

  @override
  bool shouldRepaint(_DropGuide old) =>
      old.arm != arm ||
      old.snapped != snapped ||
      old.nowLabel != nowLabel ||
      old.startLabel != startLabel ||
      old.endLabel != endLabel;
}
