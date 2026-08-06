import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:navigation_client/widgets/map_top_bar.dart';

void main() {
  testWidgets('도착지 초안은 출발지 선택과 검색 재개를 위한 두 행을 보여준다', (
    tester,
  ) async {
    final events = <String>[];
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapTopBar(
            onMenuTap: () {},
            controller: controller,
            focusNode: focusNode,
            onChanged: (_) {},
            onSubmitted: (_) {},
            searchActive: false,
            onCancelSearch: () {},
            onDirectionsTap: () => events.add('directions'),
            onSearchRequested: () => events.add('search'),
            routeDestinationLabel: '다이슨',
            onRouteOriginTap: () => events.add('origin'),
            onRouteDestinationTap: () => events.add('destination'),
            onClearRouteDraft: () => events.add('clear'),
          ),
        ),
      ),
    );

    expect(find.text('출발지를 선택하세요'), findsOneWidget);
    expect(find.text('다이슨'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byKey(const Key('route-draft-origin')));
    await tester.tap(find.byKey(const Key('route-draft-destination')));
    await tester.tap(find.byKey(const Key('route-draft-search')));
    await tester.tap(find.byKey(const Key('route-draft-clear')));

    expect(events, ['origin', 'destination', 'search', 'clear']);
  });

  testWidgets('검색을 다시 열면 초안이 있어도 기존 검색 입력창을 쓴다', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapTopBar(
            onMenuTap: () {},
            controller: controller,
            focusNode: focusNode,
            onChanged: (_) {},
            onSubmitted: (_) {},
            searchActive: true,
            onCancelSearch: () {},
            onDirectionsTap: () {},
            onSearchRequested: () {},
            routeDestinationLabel: '다이슨',
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const Key('route-draft-origin')), findsNothing);
  });

  // 이 자리가 앱 안 모든 검색창 지우기 X의 기준 패턴이다. 여기서 규칙이
  // 흔들리면 길찾기 시트·카테고리 매장 목록도 따라 어긋나므로 함께 고정한다.
  testWidgets('검색창 X는 글자가 있을 때만 나타나고 결과 상태까지 되돌린다', (tester) async {
    final changes = <String>[];
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapTopBar(
            onMenuTap: () {},
            controller: controller,
            focusNode: focusNode,
            onChanged: changes.add,
            onSubmitted: (_) {},
            searchActive: true,
            onCancelSearch: () {},
            onDirectionsTap: () {},
            onSearchRequested: () {},
          ),
        ),
      ),
    );

    // 글자가 없을 때 그 자리는 길찾기 버튼이 쓴다 — X가 빈자리를 차지하지 않는다.
    expect(find.byKey(const Key('map-top-bar-clear')), findsNothing);
    expect(find.byKey(const Key('map-top-bar-directions')), findsOneWidget);

    await tester.enterText(find.byType(TextField), '다이슨');
    await tester.pump();
    expect(find.byKey(const Key('map-top-bar-clear')), findsOneWidget);
    expect(find.byKey(const Key('map-top-bar-directions')), findsNothing);

    await tester.tap(find.byKey(const Key('map-top-bar-clear')));
    await tester.pump();

    expect(controller.text, '');
    // 글자만 지우면 상위의 검색 결과가 그대로 남는다. 빈 문자열을 흘려 그
    // 입력이 걸어 둔 결과까지 되돌리는 것이 이 X의 계약이다.
    expect(changes.last, '');
    expect(find.byKey(const Key('map-top-bar-clear')), findsNothing);
  });
}
