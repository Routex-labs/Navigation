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

  /// **흰 글자·흰 그림을 얹는 유일한 파랑.** [blue500]은 흰 글자 대비가
  /// 3.48:1이라 본문 기준(4.5:1)에 못 미치는데, 스케일이 거기서 끝나 있어
  /// 그 색이 단색 배경으로도 쓰이고 있었다. 이 칸이 그 자리를 맡는다(5.18:1).
  ///
  /// 반대로 **면을 칠할 때는 쓰지 않는다** — 도면 위에서 너무 무겁다.
  /// 근거와 12단계 대조표는 `docs/client/ui-ux-research-desk.md` 3-2절.
  static const blue600 = Color(0xFF3068D4);

  static const primary = blue500;
  static const indoor =
      blue400; // 실내 그래픽/보조 강조 — 이전 보라(0xFF6C3FE0)에서 파스텔 파랑으로 통일.
  static const success = Color(0xFF34A853);
  static const warning = Color(0xFFFBBC04);
  static const error = Color(0xFFEA4335);
  static const dest = Color(0xFFE53935);
  static const background = blue50;
  static const surface = Color(0xFFFFFFFF);
  static const text = Color(0xFF212121);
  static const muted = Color(0xFF757575);

  /// 카드·오버레이의 얇은 경계선.
  ///
  /// 그림자를 줄인 만큼 **윤곽을 이 선이 맡는다.** 밝은 도면 위의 흰 카드는
  /// 그림자가 옅어지는 순간 경계가 사라져 배경에 녹아 버린다. 네이버지도가
  /// 검색창에 그림자를 안 쓰고 테두리로만 강조하는 것과 같은 수단이다
  /// (`docs/client/naver-map-ui-ux-analysis.md` I절).
  ///
  /// 불투명 회색이 아니라 **반투명 검정**이다. 지도 배경이 층·모드마다 달라지는데
  /// 고정 회색은 어떤 배경에서는 너무 진하고 어떤 배경에서는 안 보인다.
  static const hairline = Color(0x14000000); // 검정 8%
}

/// 지도 위 UI의 **층위**. 숫자 자체보다 "무엇이 무엇보다 앞인가"가 핵심이다.
///
/// 예전에는 상단 바·검색 결과 패널·하단 바가 전부 `elevation: 6`이었다. 전부
/// 같으면 위계가 없고, 사용자는 무엇이 잠깐 뜬 레이어이고 무엇이 늘 있는
/// chrome인지 구분할 단서를 얻지 못한다.
///
/// **일괄로 낮추는 게 아니다.** 전부 낮추면 지도 위에 떠 있어야 할 오버레이가
/// 지도에 묻힌다. 낮은 층위는 그림자를 줄이는 대신 [AppColors.hairline]로 경계를
/// 만든다.
///
/// 설계 근거와 검증 기준은 `docs/client/naver-map-ui-ux-analysis.md` I절이 단일
/// 출처다.
abstract final class AppElevation {
  /// 지도에 붙어 있는 조작 — 카테고리 chip, 저장한 장소 pill, 원형 버튼.
  /// 지도의 일부처럼 읽혀야 한다.
  static const onMap = 1.0;

  /// 늘 있는 chrome — 상단 검색 바, 하단 모드 바, 카드.
  static const chrome = 3.0;

  /// 지도를 덮는 임시 레이어 — 검색 결과 패널, 층 전환 배너.
  /// **여기만 그림자가 뚜렷하다.** "지금 이게 화면의 주인공"이라는 뜻이다.
  static const overlay = 8.0;
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
      // 이걸 비워 두면 플랫폼 기본 글꼴이 쓰여 같은 화면이 기기마다 다르게 보인다.
      // 지도 심볼 라벨은 MapLibre가 서버 glyph로 따로 그리므로 여기서 정하는 것은
      // 위젯 텍스트뿐이다 — 두 쪽을 같은 글꼴로 맞추려면 서버 fontstack도 함께 바꾼다.
      fontFamily: 'Pretendard',
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
        elevation: AppElevation.chrome,
        shadowColor: Colors.black.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.hairline),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
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
        // 지도에 붙어 있는 조작이다. 상시 chrome보다 앞에 나올 이유가 없다.
        elevation: AppElevation.onMap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.indoor,
      ),
      listTileTheme: const ListTileThemeData(iconColor: AppColors.muted),
      dividerTheme: const DividerThemeData(color: AppColors.blue100),
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.text,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
        bodyLarge: TextStyle(color: AppColors.text),
        bodyMedium: TextStyle(color: AppColors.text),
        bodySmall: TextStyle(color: AppColors.muted),
      ),
    );
  }
}
