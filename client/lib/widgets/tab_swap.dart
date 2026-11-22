import 'package:flutter/material.dart';

import 'motion.dart';

/// 탭을 바꾸면 새 화면이 고른 쪽에서 살짝 밀려 들어와 앞 화면을 덮습니다.
/// 화면은 바탕까지 칠해져 있어 투명도 없이 밀기만 하므로, 큰 화면을 반투명하게 겹쳐 그리느라
/// 버벅이지 않습니다. 다 들어오면 [onSettled] 를 불러 앞 화면을 치우게 합니다.
class TabSwap extends StatefulWidget {
  const TabSwap({
    super.key,
    required this.active,
    required this.from,
    required this.child,
    this.onSettled,
  });

  final bool active;
  final int from;
  final Widget child;
  final VoidCallback? onSettled;

  @override
  State<TabSwap> createState() => _TabSwapState();
}

class _TabSwapState extends State<TabSwap> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  )..addStatusListener(_status);

  late final Animation<double> _eased = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );

  void _status(AnimationStatus s) {
    if (s == AnimationStatus.completed) widget.onSettled?.call();
  }

  @override
  void didUpdateWidget(TabSwap old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      if (reducedMotion(context)) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => widget.onSettled?.call(),
        );
      } else {
        _c.forward(from: 0);
      }
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
    // 애니메이션이 끝나도 감싸는 모양을 그대로 둡니다. 모양이 바뀌면 화면이 통째로 새로 만들어집니다.
    builder: (_, child) => FractionalTranslation(
      translation: Offset(.18 * widget.from * (1 - _eased.value), 0),
      child: child,
    ),
    child: widget.child,
  );
}
