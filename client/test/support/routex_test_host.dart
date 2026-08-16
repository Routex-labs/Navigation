import 'package:flutter/material.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// 소비 앱 widget test의 공통 host.
///
/// Runtime Kit 위젯은 `RoutexColorTokens` ThemeExtension이 없으면 예외를 던지는
/// 것이 정상이다. 테스트마다 임의 fallback 토큰을 끼워 넣으면 실제 앱에서 테마
/// 설치가 빠져도 테스트만 통과해 버린다. 그래서 여기서는 Navigation이 실제로
/// 쓰는 [AppTheme.light] 다리를 그대로 태운다.
Widget appThemedHost(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: child),
  );
}

/// 공급자 계약만 확인하는 순수 Runtime Kit fixture용 host.
///
/// 앱 테마가 아니라 `RoutexTheme.light`를 쓴다. 앱 다리가 깨진 것과 공급자
/// 컴포넌트가 깨진 것을 같은 실패로 만들지 않기 위해 두 경로를 나눠 둔다.
Widget runtimeKitHost(Widget child) {
  return MaterialApp(
    theme: RoutexTheme.light,
    home: Scaffold(body: child),
  );
}
