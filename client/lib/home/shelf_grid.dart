import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../widgets/artist_tag.dart';
import '../theme.dart';
import '../widgets/skeleton.dart';
import '../widgets/sleeve.dart';
import 'crate_parts.dart';

/// 책장 칸 하나의 가장 작은 폭입니다. 휴대폰에서는 두 칸, 넓을수록 칸이 늘어납니다.
const _minCell = 168.0;
const _gap = 18.0;
const _side = 20.0;
const _maxColumns = 6;

/// 손을 올리거나 누르면 레코드가 슬리브 위로 이만큼 빠져나옵니다. 표지 크기에 대한 비율입니다.
const _peekHover = .14;

/// 이 수만큼의 판까지 차례로 들어오고, 그 뒤의 판은 마지막 판과 함께 들어옵니다.
const _staggered = 12;

/// 폭에 맞는 칸 수입니다. 두 칸보다 적거나 여섯 칸보다 많아지지 않습니다.
int shelfColumns(double width) {
  final usable = width - _side * 2 + _gap;
  return (usable / (_minCell + _gap)).floor().clamp(2, _maxColumns);
}

/// 표지를 격자로 늘어놓은 보기입니다. 판을 누르면 그 분류를 그 판부터 재생합니다.
class ShelfGrid extends StatefulWidget {
  const ShelfGrid({
    super.key,
    required this.api,
    required this.tracks,
    required this.playLabel,
    required this.onPlay,
    this.animateIn = true,
  });

  /// 보기를 바꿔 격자로 들어올 때만 판이 솟아오릅니다. 처음 열 때는 같은 모양의 빈 자리 위로
  /// 표지만 떠올라, 빈 격자와 판이 두 번 그려지는 것처럼 보이지 않습니다.
  final bool animateIn;
  final Api api;
  final List<Track> tracks;
  final String Function(String title) playLabel;
  final ValueChanged<int> onPlay;

  @override
  State<ShelfGrid> createState() => _ShelfGridState();
}

class _ShelfGridState extends State<ShelfGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) || !widget.animateIn) {
      _enter.value = 1;
    } else if (_enter.status == AnimationStatus.dismissed) {
      _enter.forward();
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  Animation<double> _entrance(int i) => CurvedAnimation(
    parent: _enter,
    curve: Interval(
      math.min(i, _staggered) * .04,
      math.min(i, _staggered) * .04 + .5,
      curve: Curves.easeOutBack,
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = shelfColumns(box.maxWidth);
      final cell = (box.maxWidth - _side * 2 - _gap * (columns - 1)) / columns;
      final rows = (widget.tracks.length / columns).ceil();
      return ListView.builder(
        key: const Key('home-shelf'),
        padding: const EdgeInsets.fromLTRB(_side, 14, _side, 40),
        itemCount: rows,
        itemBuilder: (_, row) => _ShelfRow(
          cell: cell,
          columns: columns,
          children: [
            for (
              var i = row * columns;
              i < math.min(widget.tracks.length, (row + 1) * columns);
              i++
            )
              _ShelfRecord(
                key: ValueKey(widget.tracks[i].id),
                track: widget.tracks[i],
                api: widget.api,
                size: cell,
                label: widget.playLabel(widget.tracks[i].title),
                entrance: _entrance(i),
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onPlay(i);
                },
              ),
          ],
        ),
      );
    },
  );
}

/// 곡 목록을 받는 동안의 책장입니다. 같은 칸과 선반에 빈 표지와 글 막대를 세워 둡니다.
class ShelfSkeleton extends StatelessWidget {
  const ShelfSkeleton({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = shelfColumns(box.maxWidth);
      final cell = (box.maxWidth - _side * 2 - _gap * (columns - 1)) / columns;
      // 화면 높이를 다 채울 만큼만 줄을 세웁니다.
      final rowHeight = cell + 72;
      final rows = box.maxHeight.isFinite
          ? (box.maxHeight / rowHeight).ceil().clamp(1, 6)
          : 3;
      return Skeleton(
        key: const Key('home-shelf-skeleton'),
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(_side, 14, _side, 40),
          itemCount: rows,
          itemBuilder: (_, row) => _ShelfRow(
            cell: cell,
            columns: columns,
            children: [
              for (var c = 0; c < columns; c++) _RecordBone(size: cell),
            ],
          ),
        ),
      );
    },
  );
}

/// 선반에 세운 판 하나의 자리입니다. [_ShelfRecord] 와 크기가 같습니다.
class _RecordBone extends StatelessWidget {
  const _RecordBone({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Bone(width: size, height: size),
      const SizedBox(height: 10),
      TextBone(
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        width: size * .72,
      ),
      const SizedBox(height: 2),
      TextBone(
        style: const TextStyle(fontSize: 12, height: 1.3),
        width: size * .44,
      ),
    ],
  );
}

/// 격자의 한 줄입니다.
class _ShelfRow extends StatelessWidget {
  const _ShelfRow({
    required this.cell,
    required this.columns,
    required this.children,
  });

  final double cell;
  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var c = 0; c < columns; c++) ...[
            if (c > 0) const SizedBox(width: _gap),
            SizedBox(
              width: cell,
              child: c < children.length ? children[c] : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// 격자의 판 하나입니다. 손을 올리면 표지는 그대로 두고 레코드만 위로 빠져나옵니다.
class _ShelfRecord extends StatefulWidget {
  const _ShelfRecord({
    super.key,
    required this.track,
    required this.api,
    required this.size,
    required this.label,
    required this.entrance,
    required this.onTap,
  });

  final Track track;
  final Api api;
  final double size;
  final String label;
  final Animation<double> entrance;
  final VoidCallback onTap;

  @override
  State<_ShelfRecord> createState() => _ShelfRecordState();
}

class _ShelfRecordState extends State<_ShelfRecord> {
  bool _down = false;
  bool _hover = false;

  void _press(bool down) {
    if (down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final size = widget.size;
    final disc = size * .9;
    final lifted = _hover || _down;
    final peek = lifted ? size * _peekHover : 0.0;
    final t = widget.track;

    final record = SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedPositioned(
            duration: still ? Duration.zero : const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            left: (size - disc) / 2,
            top: (size - disc) / 2 - peek,
            width: disc,
            height: disc,
            // 판 상자의 레코드를 같은 비율로 줄여 씁니다.
            child: const FittedBox(
              child: SizedBox.square(
                dimension: 240,
                child: Stack(
                  fit: StackFit.expand,
                  children: [RecordDisc(), _Sheen()],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedContainer(
              duration: still
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x1416161A),
                    blurRadius: 8,
                    spreadRadius: -2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Sleeve(track: t, api: widget.api, size: size, radius: 6),
            ),
          ),
        ],
      ),
    );

    return AnimatedBuilder(
      animation: widget.entrance,
      // 아래에서 튀어 오르며 커지고, 살짝 비틀린 채 들어와 바로 섭니다.
      builder: (_, child) {
        final v = widget.entrance.value;
        return Opacity(
          opacity: v.clamp(0, 1),
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.identity()
              ..translateByDouble(0, (1 - v) * 56, 0, 1)
              ..rotateZ((1 - v) * .12)
              ..scaleByDouble(.7 + .3 * v, .7 + .3 * v, 1, 1),
            child: child,
          ),
        );
      },
      child: Semantics(
        button: true,
        label: widget.label,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _press(true),
            onTapUp: (_) => _press(false),
            onTapCancel: () => _press(false),
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedScale(
                  scale: _down ? .94 : 1,
                  duration: still
                      ? Duration.zero
                      : Duration(milliseconds: _down ? 90 : 520),
                  curve: _down ? Curves.easeOut : Curves.elasticOut,
                  child: record,
                ),
                const SizedBox(height: 10),
                Text(
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Palette.ink,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 5),
                ArtistTag(t.artist),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 레코드 표면에 비치는 두 줄기 빛입니다.
class _Sheen extends StatelessWidget {
  const _Sheen();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            Color(0x00FFFFFF),
            Color(0x2EFFFFFF),
            Color(0x00FFFFFF),
            Color(0x00FFFFFF),
            Color(0x2EFFFFFF),
            Color(0x00FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [0, .1, .22, .5, .6, .72, 1],
          transform: GradientRotation(-.5),
        ),
      ),
    ),
  );
}
