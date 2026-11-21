import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/artist_tag.dart';
import '../widgets/sleeve.dart';
import 'crate_parts.dart';

/// 넓은 화면의 홈입니다. 표지를 주크박스처럼 펼쳐 두고 휠, 화살표, 끌기로 돌립니다.
/// 판은 모두 정면을 보고 아치 모양으로 겹쳐 섭니다. 가운데 판이 가장 크고 레코드가 위로 빠져나와 돕니다.
/// 가운데 판을 누르면 재생하고, 옆 판을 누르면 그 판을 가운데로 데려옵니다.
class Jukebox extends StatefulWidget {
  const Jukebox({
    super.key,
    required this.api,
    required this.tracks,
    required this.hint,
    required this.playLabel,
    required this.onPlay,
  });

  final Api api;
  final List<Track> tracks;
  final String hint;
  final String Function(String title) playLabel;
  final ValueChanged<int> onPlay;

  @override
  State<Jukebox> createState() => _JukeboxState();
}

class _JukeboxState extends State<Jukebox> with TickerProviderStateMixin {
  late final AnimationController _pos = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();
  final _focus = FocusNode();
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 260,
    damping: 24,
  );

  /// 끌기 한 칸에 해당하는 거리입니다.
  static const _dragPerItem = 160.0;
  DateTime _lastWheel = DateTime(0);

  int get _count => widget.tracks.length;
  int get _front => _count == 0 ? 0 : _pos.value.round().clamp(0, _count - 1);
  bool get _still => MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still ? _spin.stop() : (_spin.isAnimating ? null : _spin.repeat());
  }

  @override
  void didUpdateWidget(Jukebox old) {
    super.didUpdateWidget(old);
    if (_count > 0 && _pos.value > _count - 1) _pos.value = _count - 1.0;
  }

  @override
  void dispose() {
    _pos.dispose();
    _spin.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    if (_count == 0) return;
    final target = i.clamp(0, _count - 1).toDouble();
    if (target.round() != _front) HapticFeedback.selectionClick();
    if (_still) {
      _pos.value = target;
      return;
    }
    _pos.animateWith(
      SpringSimulation(_spring, _pos.value, target, _pos.velocity),
    );
  }

  void _step(int by) => _goTo(_front + by);

  void _wheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final now = DateTime.now();
    // 휠 한 번 굴림에 여러 이벤트가 몰려 오므로 짧은 간격으로 한 칸씩만 넘깁니다.
    if (now.difference(_lastWheel) < const Duration(milliseconds: 90)) return;
    final d = e.scrollDelta.dx.abs() > e.scrollDelta.dy.abs()
        ? e.scrollDelta.dx
        : e.scrollDelta.dy;
    if (d.abs() < 2) return;
    _lastWheel = now;
    _step(d > 0 ? 1 : -1);
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        _step(1);
      case LogicalKeyboardKey.arrowLeft:
        _step(-1);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.space:
        widget.onPlay(_front);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // 키 큰 화면에서도 빈 데가 남지 않게 높이에 맞춰 크게 잡습니다.
      final cover = min(
        box.maxHeight * .44,
        box.maxWidth * .38,
      ).clamp(170.0, 440.0);
      return Focus(
        key: const Key('home-jukebox'),
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _key,
        child: Listener(
          onPointerSignal: _wheel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) {
              _pos.stop();
              _focus.requestFocus();
            },
            onHorizontalDragUpdate: (d) =>
                _pos.value -= d.delta.dx / _dragPerItem,
            onHorizontalDragEnd: (d) {
              final fling = -d.velocity.pixelsPerSecond.dx / _dragPerItem;
              _goTo((_pos.value + fling * .18).round());
            },
            // 옆으로 펼친 판이 오른쪽 재생 칸 위로 넘어가지 않게 홈 칸 안에서 자릅니다.
            child: ClipRect(
              child: AnimatedBuilder(
                animation: Listenable.merge([_pos, _spin]),
                builder: (context, _) => _stage(box, cover),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _stage(BoxConstraints box, double cover) {
    final p = _pos.value;
    final mid = Offset(box.maxWidth / 2, box.maxHeight * .4);
    // 가까운 판이 위에 오도록 먼 판부터 그립니다.
    final order = [
      for (var i = 0; i < _count; i++)
        if ((i - p).abs() < 4.6) i,
    ]..sort((a, b) => (b - p).abs().compareTo((a - p).abs()));
    final front = _count == 0 ? null : widget.tracks[_front];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final i in order) _item(i, i - p, mid, cover),
        if (front != null)
          Positioned(
            left: 0,
            right: 0,
            // 바로 옆 판이 아치를 따라 내려간 만큼 더 아래에 제목을 둡니다.
            top: mid.dy + cover / 2 + cover * .1 + 22,
            child: _caption(front),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 18,
          child: Text(
            widget.hint,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Palette.faint),
          ),
        ),
      ],
    );
  }

  Widget _item(int i, double d, Offset mid, double cover) {
    final a = d.abs();
    final side = d.sign;
    final near = min(a, 1.0);
    final t = widget.tracks[i];
    final center = a < .5;
    // 모든 판이 정면을 보고 아치를 따라 겹쳐 섭니다. 가운데에서 멀수록 작아지고 아래로 내려가며
    // 아치 모양대로 살짝 기웁니다.
    final x = side * (near * cover * .66 + max(0.0, a - 1) * cover * .44);
    final y = cover * .09 * a * a;
    final scale = 1 - .15 * min(a, 3.0);
    final tilt = (d * .07).clamp(-.24, .24);
    // 가운데 판은 레코드가 위로 빠져나와 돕니다.
    final out = (1 - min(a * 2, 1.0)) * cover * .3;
    final fade = (1 - max(0.0, a - 3) / 1.5).clamp(0.0, 1.0);
    return Positioned(
      left: mid.dx - cover / 2,
      top: mid.dy - cover / 2,
      width: cover,
      height: cover,
      child: Transform(
        alignment: Alignment.bottomCenter,
        transform: Matrix4.identity()
          ..translateByDouble(x, y, 0, 1)
          ..rotateZ(tilt)
          ..scaleByDouble(scale, scale, 1, 1),
        child: Opacity(
          opacity: fade,
          child: Semantics(
            button: true,
            label: widget.playLabel(t.title),
            excludeSemantics: true,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => center ? widget.onPlay(i) : _goTo(i),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (out > 1)
                      Positioned(
                        left: cover * .06,
                        top: cover * .06 - out,
                        width: cover * .88,
                        height: cover * .88,
                        child: Transform.rotate(
                          angle: _spin.value * 2 * pi,
                          child: const FittedBox(
                            child: SizedBox.square(
                              dimension: 240,
                              child: RecordDisc(),
                            ),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Color.fromRGBO(
                                22,
                                22,
                                26,
                                .14 + .16 * (1 - near),
                              ),
                              blurRadius: 18 + 18 * (1 - near),
                              offset: Offset(0, 10 + 10 * (1 - near)),
                            ),
                          ],
                        ),
                        child: Sleeve(
                          track: t,
                          api: widget.api,
                          size: cover,
                          radius: 8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _caption(Track t) => AnimatedSwitcher(
    duration: _still ? Duration.zero : const Duration(milliseconds: 260),
    transitionBuilder: (child, a) => FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .3),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
        child: child,
      ),
    ),
    child: Column(
      key: ValueKey(t.id),
      children: [
        Text(
          t.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Palette.ink,
            letterSpacing: -.3,
          ),
        ),
        const SizedBox(height: 8),
        ArtistTag(t.artist, large: true),
      ],
    ),
  );
}
