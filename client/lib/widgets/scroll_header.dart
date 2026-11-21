import 'package:flutter/material.dart';

import '../theme.dart';

/// 머리말과 그 아래 스크롤되는 내용을 묶습니다. 내용이 머리말 밑으로 말려 들어가면 머리말 아래에
/// 경계선과 옅은 그림자를 띄워, 표지가 잘린 게 아니라 머리말에 가려진 것임을 보여 줍니다.
class HeaderedBody extends StatefulWidget {
  const HeaderedBody({super.key, required this.header, required this.body});

  final Widget header;
  final Widget body;

  @override
  State<HeaderedBody> createState() => _HeaderedBodyState();
}

class _HeaderedBodyState extends State<HeaderedBody> {
  bool _under = false;

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final under = n.metrics.pixels > 1;
    if (under != _under) setState(() => _under = under);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    const quick = Duration(milliseconds: 200);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: quick,
          decoration: BoxDecoration(
            color: Palette.ground,
            border: Border(
              bottom: BorderSide(color: _under ? Palette.line : Palette.ground),
            ),
          ),
          child: widget.header,
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: widget.body,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 14,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _under ? 1 : 0,
                    duration: quick,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x1F16161A), Color(0x0016161A)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
