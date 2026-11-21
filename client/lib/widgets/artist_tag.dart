import 'package:flutter/material.dart';

import '../theme.dart';

/// 만든 사람 이름표입니다. 어느 화면에서나 같은 알약 모양으로 붙여 제목 아래가 늘 같아 보이게 합니다.
/// 앞의 동그라미에는 이름 첫 글자를 넣고, 이름마다 정해진 색을 씁니다.
class ArtistTag extends StatelessWidget {
  const ArtistTag(
    this.name, {
    super.key,
    this.large = false,
    this.color = Palette.secondary,
  });

  final String name;

  /// 재생 화면처럼 제목이 큰 곳에서 씁니다.
  final bool large;

  /// 글자색입니다. 바탕은 이 색을 옅게 깔아 어떤 배경 위에서도 어울리게 합니다.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final font = large ? 13.0 : 11.5;
    final dot = large ? 18.0 : 15.0;
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    return Container(
      padding: EdgeInsets.fromLTRB(3, 3, large ? 11 : 9, 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dot,
            height: dot,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Palette.sleeveOf(name),
            ),
            child: Text(
              initial,
              style: TextStyle(
                fontSize: dot * .55,
                fontWeight: FontWeight.w800,
                color: Palette.ink,
                height: 1,
              ),
            ),
          ),
          SizedBox(width: large ? 7 : 6),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: font,
                fontWeight: FontWeight.w600,
                color: color,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
