import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 한 줄 글자입니다. 자리에 다 들어가면 그대로 두고, 넘치면 잠깐 멈췄다가 끝까지 흘러간 뒤 되돌아옵니다.
/// 움직임 줄이기를 켠 기기에서는 흘리지 않고 말줄임으로 자릅니다.
class Marquee extends StatefulWidget {
  const Marquee(
    this.text, {
    super.key,
    required this.style,
    this.alignEnd = false,
  });

  final String text;
  final TextStyle style;
  final bool alignEnd;

  static const _speed = 28.0; // 초당 픽셀
  static const _pause = 1.6; // 양 끝에서 쉬는 초

  @override
  State<Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<Marquee> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((elapsed) {
    if (_overflow > 0) setState(() => _elapsed = elapsed);
  });
  Duration _elapsed = Duration.zero;
  double _overflow = 0;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void didUpdateWidget(Marquee old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _elapsed = Duration.zero;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// 멈춤, 가기, 멈춤, 돌아오기를 한 바퀴로 봅니다.
  double _offsetAt(double t) {
    final travel = _overflow / Marquee._speed;
    final cycle = 2 * (Marquee._pause + travel);
    final x = t % cycle;
    if (x < Marquee._pause) return 0;
    if (x < Marquee._pause + travel) {
      return Curves.easeInOut.transform((x - Marquee._pause) / travel) *
          _overflow;
    }
    if (x < 2 * Marquee._pause + travel) return _overflow;
    return (1 -
            Curves.easeInOut.transform(
              (x - 2 * Marquee._pause - travel) / travel,
            )) *
        _overflow;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final width = painter.width;
        final height = painter.height;
        painter.dispose();
        _overflow = reduceMotion ? 0 : max(0.0, width - box.maxWidth);
        final plain = Text(
          widget.text,
          style: widget.style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: widget.alignEnd ? TextAlign.end : TextAlign.start,
        );
        if (_overflow <= 0) return SizedBox(width: box.maxWidth, child: plain);
        final shift = _offsetAt(_elapsed.inMicroseconds / 1e6);
        return Semantics(
          label: widget.text,
          child: ExcludeSemantics(
            child: SizedBox(
              width: box.maxWidth,
              height: height,
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => LinearGradient(
                  colors: [
                    shift > 1 ? Colors.transparent : Colors.black,
                    Colors.black,
                    Colors.black,
                    shift < _overflow - 1 ? Colors.transparent : Colors.black,
                  ],
                  stops: const [0, .08, .92, 1],
                ).createShader(rect),
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    child: Transform.translate(
                      offset: Offset(-shift, 0),
                      child: Text(
                        widget.text,
                        style: widget.style,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
