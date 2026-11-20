import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

/// 판 표지입니다. 서버에 표지가 있으면 그 그림을, 없으면 색 바탕에 첫 글자를 씁니다.
class Sleeve extends StatelessWidget {
  const Sleeve({
    super.key,
    required this.track,
    required this.api,
    this.size = 60,
    this.radius = 7,
  });

  final Track track;
  final Api api;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: Palette.sleeveOf(track.id),
      child: Center(child: Text(track.letter, style: letterStyle(size * 0.42))),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24161A1A),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: track.hasCover
          ? Image.network(
              api.coverUri(track.id).toString(),
              headers: api.headers,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            )
          : fallback,
    );
  }
}
