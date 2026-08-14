import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/models/route_plan_mode.dart';
import 'package:navigation_client/screens/map_shell/widgets/travel_mode_bar.dart';

/// 이동 수단 줄의 회귀 테스트.
///
/// 지키려는 증상: **걸어서 두 시간 반 걸리는 길이 기본 답으로 뜨는 것.**
/// 예전에는 목적지를 정하면 무조건 도보부터 그렸고, 10 km 떨어진 곳에
/// "약 147분 / 10649m"가 먼저 떴다. 다른 수단은 하단 카드의 버튼이나 별도
/// 화면을 거쳐야 나왔으므로 사용자는 매번 그 화면을 지나쳐야 했다.
void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required RoutePlanMode selected,
    required ValueChanged<RoutePlanMode> onSelected,
    List<RoutePlanMode> modes = RoutePlanMode.values,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TravelModeBar(
            selected: selected,
            modes: modes,
            onSelected: onSelected,
          ),
        ),
      ),
    );
  }

  testWidgets('자동차·대중교통·도보를 나란히 보여준다', (WidgetTester tester) async {
    await pumpBar(tester, selected: RoutePlanMode.walk, onSelected: (_) {});

    expect(find.text('자동차'), findsOneWidget);
    expect(find.text('대중교통'), findsOneWidget);
    expect(find.text('도보'), findsOneWidget);
  });

  testWidgets('탭하면 그 수단을 상위에 알린다', (WidgetTester tester) async {
    RoutePlanMode? picked;
    await pumpBar(
      tester,
      selected: RoutePlanMode.walk,
      onSelected: (mode) => picked = mode,
    );

    await tester.tap(find.byKey(const ValueKey('travel-mode-transit')));
    await tester.pump();

    expect(picked, RoutePlanMode.transit);
  });

  testWidgets('쓸 수 있는 수단만 그린다', (WidgetTester tester) async {
    // 카카오 키가 없으면 대중교통이 빠진다 — 눌러서 "쓸 수 없습니다"를 보는 것보다
    // 없는 편이 낫다.
    await pumpBar(
      tester,
      selected: RoutePlanMode.walk,
      onSelected: (_) {},
      modes: const [RoutePlanMode.car, RoutePlanMode.walk],
    );

    expect(find.text('대중교통'), findsNothing);
    expect(find.text('자동차'), findsOneWidget);
  });

  testWidgets('수단이 하나뿐이면 줄 자체를 감춘다', (WidgetTester tester) async {
    // 실내 탭이 이 상태다(도보만 가능). 선택지가 없는 선택 줄은 자리만 먹는다.
    await pumpBar(
      tester,
      selected: RoutePlanMode.walk,
      onSelected: (_) {},
      modes: const [RoutePlanMode.walk],
    );

    expect(find.byKey(const ValueKey('travel-mode-bar')), findsNothing);
    expect(find.text('도보'), findsNothing);
  });
}
