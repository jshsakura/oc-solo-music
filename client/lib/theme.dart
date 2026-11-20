import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 쿠킹호일 웹의 밝은 팔레트를 그대로 씁니다.
abstract final class Palette {
  static const ground = Color(0xFFF2F1EE);
  static const surface = Color(0xFFFFFFFF);
  static const sunk = Color(0xFFEBE9E4);
  static const line = Color(0xFFE2E0DA);
  static const line2 = Color(0xFFD3D0C8);
  static const ink = Color(0xFF16161A);
  static const secondary = Color(0xFF55555E);
  static const faint = Color(0xFF8D8C93);
  static const off = Color(0xFFA5A4A0);
  static const butter = Color(0xFFFFC23D);
  static const bad = Color(0xFFCC3E34);
  static const good = Color(0xFF1E8E5A);

  static const _sleeves = [
    Color(0xFFB9C8F0),
    Color(0xFFFFC23D),
    Color(0xFF9FD3C7),
    Color(0xFFF4B6C2),
    Color(0xFFCDBDF2),
    Color(0xFFD6E9A8),
    Color(0xFFF6C9A0),
  ];

  /// 같은 곡은 어느 기기에서든 같은 슬리브 색이 되도록 id 로 고릅니다.
  static Color sleeveOf(String id) =>
      _sleeves[id.codeUnits.fold<int>(0, (a, b) => a + b) % _sleeves.length];
}

String formatTime(double seconds) {
  final s = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// 일본어 화면은 가나와 한자가 있는 IBM Plex Sans JP 를, 나머지는 KR 을 씁니다.
ThemeData buildTheme([String language = 'ko']) {
  final base = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: Palette.ground,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Palette.butter,
      surface: Palette.surface,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
  return base.copyWith(
    textTheme:
        (language == 'ja'
                ? GoogleFonts.ibmPlexSansJpTextTheme(base.textTheme)
                : GoogleFonts.ibmPlexSansKrTextTheme(base.textTheme))
            .apply(bodyColor: Palette.ink, displayColor: Palette.ink),
  );
}

/// 판 라벨과 표지의 큰 첫 글자입니다. 쿠킹호일의 글자 타일과 같은 글꼴입니다.
TextStyle letterStyle(double size) => GoogleFonts.baloo2(
  fontSize: size,
  fontWeight: FontWeight.w800,
  height: 1,
  color: Palette.ink,
);
