import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets/sleeve.dart';
import '../l10n.dart';

/// 이전 곡과 다음 곡입니다. 글자 없이 판만 화면 양 끝에 반쯤 걸쳐 둡니다.
/// 누르면 그 판으로 갈고, 줄 어디서든 좌우로 밀어도 갈립니다. 판을 꾹 누르고 있으면 제목이 말풍선으로 뜹니다.
class CrateRow extends StatefulWidget {
  const CrateRow({
    super.key,
    required this.ctl,
    required this.onPrev,
    required this.onNext,
    required this.edge,
    this.compact = false,
    this.roomy = false,
  });

  final PlayerController ctl;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  /// 부모가 둔 좌우 여백입니다. 판을 그만큼 바깥으로 밀어 화면 끝에 걸치게 합니다.
  final double edge;

  /// 위아래가 짧은 화면에서는 판을 줄입니다.
  final bool compact;

  /// 넓은 화면입니다. 판을 끝에 반쯤 숨기지 않고 크게 다 보이며 제목도 함께 씁니다.
  final bool roomy;

  @override
  State<CrateRow> createState() => _CrateRowState();
}

class _CrateRowState extends State<CrateRow> {
  static const _swipeToSkip = 56.0;
  double _drag = 0;
  bool _dragging = false;
  String? _peekTitle;
  bool _peekLeft = true;

  void _dragStart() => setState(() => _dragging = true);

  void _dragBy(double dx) => setState(() => _drag += dx);

  void _endDrag() {
    final d = _drag;
    setState(() {
      _drag = 0;
      _dragging = false;
    });
    if (d <= -_swipeToSkip) widget.onNext();
    if (d >= _swipeToSkip) widget.onPrev();
  }

  void _peek(Track? t, {required bool left}) {
    if (t != null) HapticFeedback.selectionClick();
    setState(() {
      _peekTitle = t?.title;
      _peekLeft = left;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.ctl;
    if (widget.roomy) return _roomy(context, c);
    final size = widget.compact ? 52.0 : 64.0;
    final height = size + 22;
    if (c.queue.length < 2) return SizedBox(height: height);
    final prev = c.peek(-1);
    final pull = _drag.clamp(-90.0, 90.0);
    final ease = _dragging ? Duration.zero : const Duration(milliseconds: 380);
    // 밀수록 그쪽 판이 화면 안으로 끌려 나옵니다.
    final prevIn = max(0.0, pull) * .6, nextIn = max(0.0, -pull) * .6;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => setState(() => _dragging = true),
      onHorizontalDragUpdate: (d) => setState(() => _drag += d.delta.dx),
      onHorizontalDragEnd: (_) => _endDrag(),
      onHorizontalDragCancel: _endDrag,
      child: SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedPositioned(
              duration: ease,
              curve: Curves.easeOutBack,
              left: -widget.edge - size * .45 + prevIn,
              top: 10,
              child: _Pick(
                label: S.of(context).prevTrack,
                onTap: widget.onPrev,
                onPeek: (on) => _peek(on ? prev : null, left: true),
                child: _PrevSleeve(track: prev, api: c.api, size: size),
              ),
            ),
            AnimatedPositioned(
              duration: ease,
              curve: Curves.easeOutBack,
              right: -widget.edge - size * .4 + nextIn,
              top: 8,
              child: _Pick(
                label: S.of(context).nextTrack,
                onTap: widget.onNext,
                onPeek: (on) => _peek(on ? c.peek(1) : null, left: false),
                child: _NextStack(ctl: c, size: size),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _peekTitle == null && pull.abs() < 8 ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const _SwipeHint(),
                  ),
                ),
              ),
            ),
            if (_peekTitle != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: _peekLeft
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: _Bubble(
                      text: _peekTitle!,
                      alignLeft: _peekLeft,
                      inset: size * .75,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

extension on _CrateRowState {
  /// 넓은 화면에서는 이전 곡과 다음 곡을 카드 둘로 나란히 놓고 표지와 제목을 다 보입니다.
  Widget _roomy(BuildContext context, PlayerController c) {
    const art = 60.0;
    const height = art + 24;
    if (c.queue.length < 2) return const SizedBox(height: height);
    final s = S.of(context);
    final pull = _drag.clamp(-60.0, 60.0);
    final ease = _dragging ? Duration.zero : const Duration(milliseconds: 380);
    Widget card({required bool left}) {
      final t = c.peek(left ? -1 : 1);
      final words = Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: left
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (left)
                  const Icon(
                    Icons.skip_previous_rounded,
                    size: 14,
                    color: Palette.faint,
                  ),
                Text(
                  left ? s.prevTrack : s.nextTrack,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Palette.faint,
                  ),
                ),
                if (!left)
                  const Icon(
                    Icons.skip_next_rounded,
                    size: 14,
                    color: Palette.faint,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              t.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: left ? TextAlign.start : TextAlign.end,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Palette.ink,
                height: 1.3,
              ),
            ),
          ],
        ),
      );
      final cover = Sleeve(track: t, api: c.api, size: art);
      return Expanded(
        child: AnimatedSlide(
          duration: ease,
          curve: Curves.easeOutBack,
          offset: Offset(pull / 600, 0),
          child: _Pick(
            label: left ? s.prevTrack : s.nextTrack,
            onTap: left ? widget.onPrev : widget.onNext,
            onPeek: (_) {},
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xB3FFFFFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Palette.line),
              ),
              child: Row(
                children: left
                    ? [cover, const SizedBox(width: 12), words]
                    : [words, const SizedBox(width: 12), cover],
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _dragStart(),
      onHorizontalDragUpdate: (d) => _dragBy(d.delta.dx),
      onHorizontalDragEnd: (_) => _endDrag(),
      onHorizontalDragCancel: _endDrag,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            card(left: true),
            const SizedBox(width: 10),
            card(left: false),
          ],
        ),
      ),
    );
  }
}

/// 누르면 고르고, 꾹 누르고 있으면 제목을 보여줍니다. 눌린 동안 살짝 들어갑니다.
class _Pick extends StatefulWidget {
  const _Pick({
    required this.label,
    required this.onTap,
    required this.onPeek,
    required this.child,
  });

  final String label;
  final VoidCallback onTap;
  final ValueChanged<bool> onPeek;
  final Widget child;

  @override
  State<_Pick> createState() => _PickState();
}

class _PickState extends State<_Pick> {
  bool _down = false;

  void _set(bool v) => setState(() => _down = v);

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    child: GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPressStart: (_) {
        _set(true);
        widget.onPeek(true);
      },
      onLongPressEnd: (_) {
        _set(false);
        widget.onPeek(false);
      },
      child: AnimatedScale(
        scale: _down ? .92 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    ),
  );
}

class _PrevSleeve extends StatelessWidget {
  const _PrevSleeve({
    required this.track,
    required this.api,
    required this.size,
  });

  final Track track;
  final Api api;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size * 1.35,
    height: size,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: size * .38,
          top: size * .06,
          child: _MiniDisc(color: Palette.sleeveOf(track.id), size: size * .88),
        ),
        Transform.rotate(
          angle: .08,
          child: Sleeve(track: track, api: api, size: size),
        ),
      ],
    ),
  );
}

class _NextStack extends StatelessWidget {
  const _NextStack({required this.ctl, required this.size});

  final PlayerController ctl;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size + 28,
    height: size + 8,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        for (final k in [3, 2, 1])
          Positioned(
            left: (k - 1) * 12.0,
            top: (k - 1) * 3.0,
            child: Opacity(
              opacity: 1 - (k - 1) * .2,
              child: Transform.rotate(
                angle: -(k - 1) * .09,
                child: Sleeve(track: ctl.peek(k), api: ctl.api, size: size),
              ),
            ),
          ),
      ],
    ),
  );
}

class _MiniDisc extends StatelessWidget {
  const _MiniDisc({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [color, color, Palette.ink, Palette.ink],
        stops: const [0, .26, .27, 1],
      ),
    ),
  );
}

/// 가운데 빈 자리에 좌우로 밀 수 있다는 것만 작게 알립니다.
class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.chevron_left_rounded, size: 18, color: Palette.line2),
      for (var i = 0; i < 3; i++)
        Container(
          width: 4,
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Palette.line2,
          ),
        ),
      const Icon(Icons.chevron_right_rounded, size: 18, color: Palette.line2),
    ],
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.alignLeft,
    required this.inset,
  });

  final String text;
  final bool alignLeft;
  final double inset;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 220),
    margin: EdgeInsets.only(
      left: alignLeft ? inset : 0,
      right: alignLeft ? 0 : inset,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Palette.ink,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33161A1A),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: alignLeft ? TextAlign.start : TextAlign.end,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: Palette.ground,
      ),
    ),
  );
}
