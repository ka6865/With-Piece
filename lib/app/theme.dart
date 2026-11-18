import 'package:flutter/material.dart';

// 아이보리·피치·민트 포인트(커플 디자인 설계 4.1). seed로 나머지 역할을 채우고
// 지도와 글자에 쓰는 역할은 대비를 계산한 값으로 덮어쓴다(theme_test.dart)
// 지도: primaryContainer 채운 조각, onPrimaryContainer 채운 조각 테두리,
// surfaceContainerHighest 빈 조각, tertiary 생활권
const _peach = Color(0xFFFF8A65);

final lightScheme = ColorScheme.fromSeed(seedColor: _peach).copyWith(
  primary: const Color(0xFFBF4A26),
  onPrimary: Colors.white,
  primaryContainer: const Color(0xFFFFB38F),
  onPrimaryContainer: const Color(0xFF7A2E14),
  secondary: _peach,
  secondaryContainer: const Color(0xFFFFE5D6),
  onSecondaryContainer: const Color(0xFF6B2A12),
  tertiary: const Color(0xFF1C7262),
  onTertiary: Colors.white,
  surface: const Color(0xFFFFFBF4),
  onSurface: const Color(0xFF2F3330),
  onSurfaceVariant: const Color(0xFF5F6661),
  surfaceContainerLowest: Colors.white,
  surfaceContainerHighest: const Color(0xFFE9EEEA),
  outline: const Color(0xFF7A817C),
  outlineVariant: const Color(0xFFDDE2DE),
);

final darkScheme =
    ColorScheme.fromSeed(
      seedColor: _peach,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFFFFB38F),
      onPrimary: const Color(0xFF4A1C0C),
      primaryContainer: const Color(0xFF9A4528),
      onPrimaryContainer: const Color(0xFFFFDCCB),
      secondary: _peach,
      secondaryContainer: const Color(0xFF5C2A18),
      onSecondaryContainer: const Color(0xFFFFDCCB),
      tertiary: const Color(0xFF5FCBB4),
      onTertiary: const Color(0xFF00382E),
      surface: const Color(0xFF1C1A18),
      onSurface: const Color(0xFFEEE7E2),
      onSurfaceVariant: const Color(0xFFC5BDB7),
      surfaceContainerLowest: const Color(0xFF262320),
      surfaceContainerHighest: const Color(0xFF3A3734),
      outline: const Color(0xFF958C86),
      outlineVariant: const Color(0xFF4A4542),
    );

ThemeData _theme(ColorScheme scheme) => ThemeData(
  colorScheme: scheme,
  scaffoldBackgroundColor: scheme.surface,
  cardTheme: CardThemeData(
    color: scheme.surfaceContainerLowest,
    elevation: 1,
    shadowColor: Colors.black26,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
);

final lightTheme = _theme(lightScheme);
final darkTheme = _theme(darkScheme);
