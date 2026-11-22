import 'package:flutter/material.dart';

import 'motion.dart';

/// 탭을 바꾸면 새 화면이 고른 쪽에서 살짝 밀려 들어오며 나타납니다.
/// 화면 자체는 IndexedStack 이 계속 쥐고 있어 상태가 그대로 남습니다.
class TabSwap extends StatefulWidget {
  const TabSwap({
    super.key,
    required this.active,
    required this.from,
    required this.child,
  });

  final bool active;
  final int from;
  final Widget child;

  @override
  State<TabSwap> createState() => _TabSwapState();
}

class _TabSwapState extends State<TabSwap> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
    value: 1,
  );
  // 살짝 지나쳤다가 제자리에 서는 탄력 있는 곡선입니다.
  late final Animation<double> _eased = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutBack,
  );

  @override
  void didUpdateWidget(TabSwap old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !reducedMotion(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _eased,
    builder: (_, child) {
      // 애니메이션이 끝나도 감싸는 모양을 그대로 둡니다. 끝났다고 화면만 꺼내 돌려주면 위젯 트리 모양이
      // 바뀌어 화면이 통째로 새로 만들어지고, 탭을 열 때마다 목록을 두 번 받고 두 번 그렸습니다.
      final v = _c.isCompleted ? 1.0 : _eased.value;
      return Opacity(
        opacity: (_c.value * 2.2).clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(110.0 * widget.from * (1 - v), 0),
          child: Transform.scale(scale: .9 + .1 * v, child: child),
        ),
      );
    },
    child: widget.child,
  );
}
