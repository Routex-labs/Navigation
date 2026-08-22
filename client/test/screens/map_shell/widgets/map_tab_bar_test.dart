import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/map_shell/widgets/chrome/map_tab_bar.dart';
import 'package:navigation_client/theme/app_theme.dart';

/// 이 검사가 지키는 것 — **고른 탭이 색 하나로만 갈리지 않는가.**
///
/// 색만으로 가르면 색을 구분하기 어려운 사람에게는 아무 표시도 없는 줄이 된다.
/// 굵기와 채운 아이콘이 함께 바뀌어야 하고, 그 사실은 화면을 봐서는 통과처럼
/// 보이므로 여기서 못 박는다.
void main() {
  Widget host({
    MapTab selected = MapTab.map,
    ValueChanged<MapTab>? onSelected,
  }) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: MapTabBar(selected: selected, onSelected: onSelected ?? (_) {}),
      ),
    ),
  );

  testWidgets('탭이 넷 다 서고 이름이 함께 붙는다', (tester) async {
    await tester.pumpWidget(host());

    for (final tab in MapTab.values) {
      expect(find.byKey(Key('map-tab-${tab.name}')), findsOneWidget);
      expect(find.text(tab.label), findsOneWidget);
    }
  });

  testWidgets('고른 탭은 색·굵기·아이콘 셋으로 갈린다', (tester) async {
    await tester.pumpWidget(host(selected: MapTab.events));

    final chosen = tester.widget<Text>(find.text('이벤트'));
    final other = tester.widget<Text>(find.text('지도'));
    expect(chosen.style?.fontWeight, FontWeight.w700);
    expect(other.style?.fontWeight, FontWeight.w500);
    expect(chosen.style?.color, isNot(other.style?.color));
    // 채운 아이콘으로 바뀐다 — 굵기가 안 보이는 작은 글자를 아이콘이 받쳐 준다.
    expect(find.byIcon(MapTab.events.activeIcon), findsOneWidget);
    expect(find.byIcon(MapTab.map.icon), findsOneWidget);
  });

  testWidgets('누른 탭을 그대로 넘긴다', (tester) async {
    final picked = <MapTab>[];
    await tester.pumpWidget(host(onSelected: picked.add));

    await tester.tap(find.byKey(const Key('map-tab-saved')));
    await tester.tap(find.byKey(const Key('map-tab-directions')));

    expect(picked, [MapTab.saved, MapTab.directions]);
  });

  testWidgets('안전영역만큼 아래를 비우고, 줄 자체 높이는 고정이다', (tester) async {
    // 홈 인디케이터가 있는 기기다. 줄이 그 위로 올라가야 마지막 탭이 눌린다.
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());

    expect(
      tester.getSize(find.byType(MapTabBar)).height,
      kMapTabBarHeight + 48,
    );
  });
}
