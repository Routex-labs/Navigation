import 'package:flutter/material.dart';

/// 앱 전역 디자인 토큰. 실내 지도(MapLibre) 렌더링과 경로선/마커에서도
/// 같은 값을 참조해 Material UI와 지도 위 그래픽의 색이 어긋나지 않게 한다.
abstract final class AppColors {
  // 파스텔 파랑 스케일. 밝은 배경/칩부터 강조 버튼까지 UI 전반에서 공용으로 참조한다.
  static const blue50 = Color(0xFFEEF4FE);
  static const blue100 = Color(0xFFD6E4FC);
  static const blue200 = Color(0xFFB8D0F9);
  static const blue300 = Color(0xFF8EB4F5);
  static const blue400 = Color(0xFF6C9BF2);
  static const blue500 = Color(0xFF4A87F1);

  static const primary = blue500;
  static const indoor = blue400; // 실내 그래픽/보조 강조 — 이전 보라(0xFF6C3FE0)에서 파스텔 파랑으로 통일.
  static const success = Color(0xFF34A853);
  static const warning = Color(0xFFFBBC04);
  static const error = Color(0xFFEA4335);
  static const dest = Color(0xFFE53935);
  static const background = blue50;
  static const surface = Color(0xFFFFFFFF);
  static const text = Color(0xFF212121);
  static const muted = Color(0xFF757575);
}

abstract final class AppTheme {
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      secondary: AppColors.indoor,
      error: AppColors.error,
      surface: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.muted,
          textStyle: const TextStyle(fontSize: 13),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.blue50,
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.primary,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.indoor,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.muted,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.blue100),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontWeight: FontWeight.w800, color: AppColors.text),
        titleMedium: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text),
        bodyLarge: TextStyle(color: AppColors.text),
        bodyMedium: TextStyle(color: AppColors.text),
        bodySmall: TextStyle(color: AppColors.muted),
      ),
    );
  }
}
