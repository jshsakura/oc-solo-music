import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';
import 'motion.dart';

/// 빛줄기가 한 번 지나가는 시간입니다.
const _sweep = Duration(milliseconds: 1500);

/// 자리를 잡아 두는 회색 조각들 위로 옅은 빛줄기가 천천히 지나갑니다.
/// 움직임 줄이기를 켜면 빛줄기 없이 조각만 둡니다. 화면 낭독기에는 불러오는 중이라고 읽어 줍니다.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child, this.label = true});

  final Widget child;

  /// 한 화면에 여러 개를 둘 때는 하나만 읽히게 나머지는 끕니다.
  final bool label;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _sweep,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      // 나중에 뜬 조각도 먼저 뜬 조각과 같은 박자로 빛이 지나가게 시계에 맞춥니다.
      final ms = DateTime.now().millisecondsSinceEpoch;
      _c.value = (ms % _sweep.inMilliseconds) / _sweep.inMilliseconds;
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = reducedMotion(context)
        ? widget.child
        : AnimatedBuilder(
            animation: _c,
            child: widget.child,
            builder: (_, child) => ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [
                  Color(0x00FFFFFF),
                  Color(0x8CFFFFFF),
                  Color(0x00FFFFFF),
                ],
                stops: const [.35, .5, .65],
                transform: _Slide(_c.value),
              ).createShader(rect),
              child: child,
            ),
          );
    return Semantics(
      label: widget.label ? S.of(context).loading : null,
      excludeSemantics: true,
      child: IgnorePointer(child: RepaintBoundary(child: body)),
    );
  }
}

/// 빛줄기를 왼쪽 바깥에서 오른쪽 바깥까지 옮깁니다.
class _Slide extends GradientTransform {
  const _Slide(this.t);
  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2.4 - 1.2), 0, 0);
}

/// 자리를 잡아 두는 조각 하나입니다.
class Bone extends StatelessWidget {
  const Bone({
    super.key,
    this.width,
    this.height,
    this.radius = 6,
    this.circle = false,
    this.color = Palette.sunk,
  });

  final double? width;
  final double? height;
  final double radius;
  final bool circle;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : BorderRadius.circular(radius),
    ),
  );
}

/// 글 한 줄 자리입니다. 같은 글꼴의 보이지 않는 줄로 높이를 맞추므로 글이 들어와도 아래가 밀리지 않습니다.
class TextBone extends StatelessWidget {
  const TextBone({
    super.key,
    required this.style,
    required this.width,
    this.color = Palette.sunk,
  });

  final TextStyle style;
  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: AlignmentDirectional.centerStart,
    children: [
      Opacity(opacity: 0, child: Text(' ', style: style, maxLines: 1)),
      Bone(
        width: width,
        height: (style.fontSize ?? 14) * .72,
        radius: 100,
        color: color,
      ),
    ],
  );
}

/// 자리 조각에서 실제 내용으로 부드럽게 넘어갑니다. 위쪽을 맞춰 겹치므로 자리가 흔들리지 않습니다.
class LoadSwitch extends StatelessWidget {
  const LoadSwitch({
    super.key,
    required this.loading,
    required this.skeleton,
    required this.child,
    this.alignment = Alignment.topCenter,
  });

  final bool loading;
  final Widget skeleton;
  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: reducedMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 320),
    switchInCurve: Curves.easeOut,
    switchOutCurve: Curves.easeIn,
    layoutBuilder: (current, previous) =>
        Stack(alignment: alignment, children: [...previous, ?current]),
    child: KeyedSubtree(
      key: ValueKey(loading),
      child: loading ? skeleton : child,
    ),
  );
}

/// 서버의 표지 그림입니다. 받는 동안은 빛줄기가 지나가는 [placeholder] 를 두고, 다 받으면 그 위로 천천히 떠오릅니다.
/// 이미 받아 둔 그림은 바로 보여 줍니다.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.url,
    required this.headers,
    required this.fallback,
    this.placeholder = const Bone(radius: 0),
    this.shimmer = true,
  });

  final String url;
  final Map<String, String> headers;

  /// 그림을 못 받았을 때 둘 것입니다.
  final Widget fallback;

  /// 받는 동안 그림 자리에 둘 것입니다.
  final Widget placeholder;

  /// 받는 동안 [placeholder] 위로 빛줄기를 지나가게 할지입니다.
  final bool shimmer;

  @override
  Widget build(BuildContext context) {
    final still = reducedMotion(context);
    return Image.network(
      url,
      headers: headers,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
      frameBuilder: (context, child, frame, sync) {
        if (sync) return child;
        final waiting = frame == null;
        return Stack(
          fit: StackFit.expand,
          children: [
            waiting && shimmer
                ? Skeleton(label: false, child: placeholder)
                : placeholder,
            AnimatedOpacity(
              key: const ValueKey('cover'),
              opacity: waiting ? 0 : 1,
              duration: still
                  ? Duration.zero
                  : const Duration(milliseconds: 380),
              curve: Curves.easeOut,
              child: child,
            ),
          ],
        );
      },
    );
  }
}
