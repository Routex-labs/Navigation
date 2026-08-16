import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../support/routex_test_host.dart';

/// 테마 다리의 합격 기준은 "Runtime Kit이 그려진다"가 아니다.
///
/// 전역 테마를 `RoutexTheme.light`로 갈아 끼우면 아직 옮기지 않은 카드·입력창·
/// 버튼까지 한꺼번에 바뀌어, 이후 포팅에서 생긴 변화와 구분할 수 없게 된다.
/// 그래서 여기서 지키는 것은 **더해진 것이 ThemeExtension 하나뿐**이라는 사실이다.
/// 절차와 실패 기준은 `docs/navigation-app-porting-guide.md` 5절이 단일 출처다.
void main() {
  group('테마 다리 — 더하는 것은 ThemeExtension 하나뿐', () {
    test('나머지 ThemeData 필드는 그대로 둔다', () {
      final base = ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        scaffoldBackgroundColor: AppColors.background,
      );

      final bridged = AppTheme.withRoutexTokens(base);

      // 더해진 extension을 도로 걷어 내면 원본과 같아야 한다. ThemeData의 ==는
      // 모든 필드를 비교하므로, 다리가 색·모양·글자 중 하나라도 건드렸다면
      // 여기서 걸린다.
      expect(bridged.copyWith(extensions: base.extensions.values), base);
    });

    test('이미 있던 extension을 덮어쓰지 않는다', () {
      final base = ThemeData(extensions: const [_Probe(7)]);

      final bridged = AppTheme.withRoutexTokens(base);

      expect(bridged.extension<_Probe>()?.value, 7);
      expect(bridged.extension<RoutexColorTokens>(), RoutexColorTokens.light);
    });

    test('앱 테마에 Runtime Kit 토큰이 설치돼 있다', () {
      expect(
        AppTheme.light.extension<RoutexColorTokens>(),
        RoutexColorTokens.light,
      );
    });
  });

  group('테마 다리 — 포팅하지 않은 화면의 계약', () {
    test('앱이 정한 Material 값이 그대로 남는다', () {
      final theme = AppTheme.light;

      expect(theme.textTheme.bodyMedium?.fontFamily, 'Pretendard');
      expect(theme.scaffoldBackgroundColor, AppColors.background);
      expect(theme.cardTheme.elevation, AppElevation.chrome);
      expect(theme.dividerTheme.color, AppColors.blue100);
    });

    // `RoutexTheme.light`는 focus·divider·disabled를 semantic 토큰으로 덮는다.
    // 그 값이 전역으로 새면 아직 옮기지 않은 Material 컨트롤의 focus 표시와
    // 구분선이 함께 바뀐다. 앱 색 구성표로 만든 기본값과 같은지로 확인한다.
    test('Runtime Kit의 semantic 값이 전역으로 새지 않는다', () {
      final theme = AppTheme.light;
      final materialDefault = ThemeData(
        useMaterial3: true,
        colorScheme: theme.colorScheme,
      );

      expect(theme.focusColor, materialDefault.focusColor);
      expect(theme.dividerColor, materialDefault.dividerColor);
      expect(theme.disabledColor, materialDefault.disabledColor);
    });
  });

  group('테마 다리 — Runtime Kit 렌더링', () {
    testWidgets('앱 테마 위에서 토큰 누락 없이 그려진다', (tester) async {
      await tester.pumpWidget(appThemedHost(const RoutexBadge(label: '영업 중')));

      expect(find.text('영업 중'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 토큰이 없을 때 조용히 기본색으로 떨어지면, 테마 설치를 빠뜨린 화면이
    // 검증을 통과해 버린다. 실패하는 것이 정상이다.
    testWidgets('토큰이 없는 테마에서는 실패한다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const Scaffold(body: RoutexBadge(label: '영업 중')),
        ),
      );

      expect(tester.takeException(), isA<FlutterError>());
    });

    testWidgets('공급자 테마 경로도 따로 살아 있다', (tester) async {
      await tester.pumpWidget(runtimeKitHost(const RoutexBadge(label: '영업 중')));

      expect(find.text('영업 중'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// 앱이 이미 가진 extension을 흉내 내는 표식.
@immutable
class _Probe extends ThemeExtension<_Probe> {
  const _Probe(this.value);

  final int value;

  @override
  _Probe copyWith({int? value}) => _Probe(value ?? this.value);

  @override
  _Probe lerp(_Probe? other, double t) => other ?? this;
}
