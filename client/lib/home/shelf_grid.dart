import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/sleeve.dart';
import 'crate_parts.dart';

/// 책장 칸 하나의 가장 작은 폭입니다. 휴대폰에서는 두 칸, 넓을수록 칸이 늘어납니다.
const _minCell = 168.0;
const _gap = 18.0;
const _side = 20.0;
const _maxColumns = 6;

/// 레코드가 슬리브 위로 삐져나온 정도입니다. 표지 크기에 대한 비율입니다.
const _peek = .12;
const _peekPressed = .2;

/// 이 수만큼의 판까지 차례로 들어오고, 그 뒤의 판은 마지막 판과 함께 들어옵니다.
const _staggered = 12;

/// 폭에 맞는 칸 수입니다. 두 칸보다 적거나 여섯 칸보다 많아지지 않습니다.
int shelfColumns(double width) {
  final usable = width - _side * 2 + _gap;
  return (usable / (_minCell + _gap)).floor().clamp(2, _maxColumns);
}

/// 판을 책장 선반에 표지가 보이게 세워 둔 보기입니다. 판을 누르면 그 분류를 그 판부터 재생합니다.
class ShelfGrid extends StatefulWidget {
  const ShelfGrid({
    super.key,
    required this.api,
    required this.tracks,
    required this.playLabel,
    required this.onPlay,
  });

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
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
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
      math.min(i, _staggered) * .045,
      math.min(i, _staggered) * .045 + .46,
      curve: Curves.easeOutCubic,
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

/// 판 한 줄과 그 판들이 서 있는 선반입니다.
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
    final standing = cell * (1 + _peekPressed);
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 판 뒤의 칸막이 벽입니다. 선반 쪽으로 갈수록 그늘이 집니다.
          Positioned(
            left: -10,
            right: -10,
            top: -14,
            height: standing + 14,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00EBE9E4), Palette.sunk, Color(0xFFE2DDD3)],
                  stops: [0, .45, 1],
                ),
              ),
            ),
          ),
          // 선반은 칸 양옆으로 조금 더 길게 나와 판들을 받칩니다.
          Positioned(
            left: -10,
            right: -10,
            top: standing - 2,
            child: const ShelfPlank(),
          ),
          Row(
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
        ],
      ),
    );
  }
}

/// 옅은 원목 선반입니다. 윗면, 앞면, 그 아래로 지는 그림자로 이루어집니다.
class ShelfPlank extends StatelessWidget {
  const ShelfPlank({super.key});

  static const height = 18.0;
  static const _top = [Color(0xFFF3ECDF), Color(0xFFE5D7BF)];
  static const _front = [Color(0xFFD9C4A1), Color(0xFFC2A67C)];

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 7,
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _top,
            ),
          ),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(4),
              ),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _front,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6B5531).withValues(alpha: .22),
                  blurRadius: 14,
                  spreadRadius: -4,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// 선반에 세운 판 하나입니다. 누르는 동안 살짝 작아지며 레코드가 더 올라옵니다.
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

  void _press(bool down) {
    if (down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final quick = still ? Duration.zero : const Duration(milliseconds: 160);
    final size = widget.size;
    final disc = size * .9;
    final peek = size * (_down ? _peekPressed : _peek);
    final t = widget.track;

    final record = SizedBox(
      width: size,
      height: size * (1 + _peekPressed),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedPositioned(
            duration: still ? Duration.zero : const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            left: (size - disc) / 2,
            top: size * _peekPressed - peek,
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
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: size,
            child: Sleeve(track: t, api: widget.api, size: size, radius: 6),
          ),
        ],
      ),
    );

    return AnimatedBuilder(
      animation: widget.entrance,
      builder: (_, child) => Opacity(
        opacity: widget.entrance.value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, (1 - widget.entrance.value) * 22),
          child: child,
        ),
      ),
      child: Semantics(
        button: true,
        label: widget.label,
        excludeSemantics: true,
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
                scale: _down ? .96 : 1,
                duration: quick,
                curve: Curves.easeOut,
                alignment: Alignment.bottomCenter,
                child: record,
              ),
              SizedBox(height: ShelfPlank.height + 10),
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
              const SizedBox(height: 2),
              Text(
                t.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Palette.faint,
                  height: 1.3,
                ),
              ),
            ],
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
