import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../support/routex_test_host.dart';

/// 테마 다리의 합격 기준은 "Runtime Kit이 그려진다"가 아니다.
///
/// 지키는 것이 둘이다. **더해진 것이 ThemeExtension 하나뿐**이라는 사실과,
/// 전역 전환이 아직 남겨 둔 **차이의 목록**이다. 뒤엣것이 비는 날 전환한다.
/// 판정 근거와 순서는 `docs/client/theme-handover.md`가 단일 출처다.
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

  group('테마 다리 — 전역 전환 게이트', () {
    // 단계 8이 묻는 것은 "전환할 수 있나"이고, 답은 **남은 차이의 목록**이다.
    // 목록이 비는 날 `AppTheme.light`를 `RoutexTheme.light`로 갈아 끼운다.
    //
    // 포팅이 진행돼 앱이 override 하나를 지우면 이 테스트가 실패한다. 그때
    // 목록에서도 지운다 — 그래서 전환 조건이 문서가 아니라 여기에 산다.
    // 각 항목의 소비처는 `docs/client/theme-handover.md`가 단일 출처다.
    test('앱 테마가 Runtime Kit 테마와 다른 지점은 이 목록뿐이다', () {
      const expected = {
        // AppColors.primary(하늘)와 Kit actionPrimary(진파랑)는 다른 색이다.
        // 앱이 AppColors.primary를 직접 읽는 자리가 남아 있는 한, 여기만 Kit
        // 값으로 바꾸면 한 화면에 두 파랑이 선다.
        'colorScheme.primary',
        'colorScheme.secondary',
        'colorScheme.error',
        'colorScheme.outline',
        'colorScheme.outlineVariant',
        'scaffoldBackgroundColor',
        'dividerColor',
        'focusColor',
        'disabledColor',
        // 아직 앱이 그리는 Material 위젯이 읽는 값들.
        'textTheme.bodyMedium',
        'textTheme.titleMedium',
        'appBarTheme',
        'cardTheme',
        'filledButtonTheme',
        'textButtonTheme',
        'inputDecorationTheme',
        'listTileTheme',
        'dividerTheme',
        'progressIndicatorTheme',
      };

      expect(_differencesFromRuntimeKit(), expected);
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

/// 전환하면 화면이 달라지는 축만 골라 두 테마를 견준다.
///
/// `ThemeData`를 통째로 비교하면 화면에 닿지 않는 필드까지 세어 목록이 잡음이
/// 된다. 여기 있는 이름은 전부 **아직 앱이 그리는 Material 위젯이 읽는 값**이다.
Set<String> _differencesFromRuntimeKit() {
  final app = AppTheme.light;
  final kit = RoutexTheme.light;

  final probes = <String, (Object?, Object?)>{
    'colorScheme.primary': (app.colorScheme.primary, kit.colorScheme.primary),
    'colorScheme.secondary': (
      app.colorScheme.secondary,
      kit.colorScheme.secondary,
    ),
    'colorScheme.surface': (app.colorScheme.surface, kit.colorScheme.surface),
    'colorScheme.error': (app.colorScheme.error, kit.colorScheme.error),
    'colorScheme.outline': (app.colorScheme.outline, kit.colorScheme.outline),
    'colorScheme.outlineVariant': (
      app.colorScheme.outlineVariant,
      kit.colorScheme.outlineVariant,
    ),
    'scaffoldBackgroundColor': (
      app.scaffoldBackgroundColor,
      kit.scaffoldBackgroundColor,
    ),
    'dividerColor': (app.dividerColor, kit.dividerColor),
    'focusColor': (app.focusColor, kit.focusColor),
    'disabledColor': (app.disabledColor, kit.disabledColor),
    'textTheme.bodyMedium': (
      app.textTheme.bodyMedium,
      kit.textTheme.bodyMedium,
    ),
    'textTheme.titleMedium': (
      app.textTheme.titleMedium,
      kit.textTheme.titleMedium,
    ),
    'appBarTheme': (app.appBarTheme, kit.appBarTheme),
    'cardTheme': (app.cardTheme, kit.cardTheme),
    'filledButtonTheme': (app.filledButtonTheme, kit.filledButtonTheme),
    'textButtonTheme': (app.textButtonTheme, kit.textButtonTheme),
    'inputDecorationTheme': (
      app.inputDecorationTheme,
      kit.inputDecorationTheme,
    ),
    'listTileTheme': (app.listTileTheme, kit.listTileTheme),
    'dividerTheme': (app.dividerTheme, kit.dividerTheme),
    'progressIndicatorTheme': (
      app.progressIndicatorTheme,
      kit.progressIndicatorTheme,
    ),
  };

  return {
    for (final probe in probes.entries)
      if (probe.value.$1 != probe.value.$2) probe.key,
  };
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
