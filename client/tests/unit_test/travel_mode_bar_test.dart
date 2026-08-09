import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/widgets/travel_mode_bar.dart';

/// 이동 수단 줄의 회귀 테스트.
///
/// 지키려는 증상: **걸어서 두 시간 반 걸리는 길이 기본 답으로 뜨는 것.**
/// 예전에는 목적지를 정하면 무조건 도보부터 그렸고, 10 km 떨어진 곳에
/// "약 147분 / 10649m"가 먼저 떴다. 대중교통은 하단 카드의 버튼을 눌러야
/// 나왔으므로 사용자는 매번 그 화면을 지나쳐야 했다.
void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required TravelMode selected,
    required ValueChanged<TravelMode> onSelected,
    bool transitEnabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TravelModeBar(
            selected: selected,
            onSelected: onSelected,
            transitEnabled: transitEnabled,
          ),
        ),
      ),
    );
  }

  testWidgets('도보와 대중교통을 나란히 보여준다', (WidgetTester tester) async {
    await pumpBar(tester, selected: TravelMode.walk, onSelected: (_) {});

    expect(find.text('도보'), findsOneWidget);
    expect(find.text('대중교통'), findsOneWidget);
  });

  testWidgets('탭하면 그 수단을 상위에 알린다', (WidgetTester tester) async {
    TravelMode? picked;
    await pumpBar(
      tester,
      selected: TravelMode.walk,
      onSelected: (mode) => picked = mode,
    );

    await tester.tap(find.byKey(const ValueKey('travel-mode-transit')));
    await tester.pump();

    expect(picked, TravelMode.transit);
  });

  testWidgets('대중교통을 쓸 수 없으면 줄 자체를 감춘다', (WidgetTester tester) async {
    // 남는 선택지가 도보 하나뿐이라 고를 것이 없다. 선택지가 없는 선택 줄은
    // 자리만 먹고, 눌러서 "쓸 수 없습니다"를 보는 것보다 없는 편이 낫다.
    await pumpBar(
      tester,
      selected: TravelMode.walk,
      onSelected: (_) {},
      transitEnabled: false,
    );

    expect(find.byKey(const ValueKey('travel-mode-bar')), findsNothing);
    expect(find.text('도보'), findsNothing);
  });
}
