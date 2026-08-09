import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:navigation_client/widgets/map_top_bar.dart';

/// 상단 바의 **두 얼굴**을 고정하는 테스트.
///
/// 평소에는 검색창 한 줄이고, 길찾기 중에는 출발/도착 두 칸이다. 한때 길찾기는
/// 전체 화면이었고 이 바에는 값만 적힌 요약 행이 떴는데, 그러면 목적지를 고치려고
/// 누른 자리와 실제로 치는 자리가 서로 다른 화면에 있었다.
void main() {
  ({
    TextEditingController search,
    TextEditingController origin,
    TextEditingController destination,
    FocusNode focus,
  })
  makeControllers(WidgetTester tester) {
    final search = TextEditingController();
    final origin = TextEditingController();
    final destination = TextEditingController();
    final focus = FocusNode();
    addTearDown(search.dispose);
    addTearDown(origin.dispose);
    addTearDown(destination.dispose);
    addTearDown(focus.dispose);
    return (
      search: search,
      origin: origin,
      destination: destination,
      focus: focus,
    );
  }

  testWidgets('길찾기 중에는 출발/도착 두 칸을 그 자리에서 친다', (tester) async {
    final c = makeControllers(tester);
    c.destination.text = '다이슨';
    final events = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapTopBar(
            showHamburger: false,
            onHamburgerTap: () {},
            controller: c.search,
            focusNode: c.focus,
            onChanged: (_) {},
            onSubmitted: (_) {},
            searchActive: false,
            onCancelSearch: () {},
            onDirectionsTap: () => events.add('directions'),
            routeMode: true,
            originController: c.origin,
            destinationController: c.destination,
            onOriginChanged: (value) => events.add('origin:$value'),
            onDestinationChanged: (value) => events.add('destination:$value'),
            onClearRouteDraft: () => events.add('clear'),
          ),
        ),
      ),
    );

    // 값은 진짜 입력창 안에 있다. 예전처럼 라벨로 그리면 눌러도 커서가 안 잡힌다.
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('다이슨'), findsOneWidget);
    // 출발지가 비어 있으면 "현재 위치"가 안내문으로만 뜬다 — 글자로 채우면
    // 사용자가 다른 곳을 치기 전에 먼저 지워야 한다.
    expect(find.text('현재 위치'), findsOneWidget);
    expect(c.origin.text, isEmpty);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('route-draft-destination')),
        matching: find.byType(TextField),
      ),
      '이솝',
    );
    await tester.tap(find.byKey(const Key('route-draft-clear')));

    expect(events, ['destination:이솝', 'clear']);
  });

  testWidgets('길찾기 중이 아니면 검색창 한 줄이다', (tester) async {
    final c = makeControllers(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapTopBar(
            showHamburger: false,
            onHamburgerTap: () {},
            controller: c.search,
            focusNode: c.focus,
            onChanged: (_) {},
            onSubmitted: (_) {},
            searchActive: true,
            onCancelSearch: () {},
            onDirectionsTap: () {},
            originController: c.origin,
            destinationController: c.destination,
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const Key('route-draft-origin')), findsNothing);
  });
}
