import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:navigation_client/widgets/map_top_bar.dart';

void main() {
  testWidgets('도착지 초안은 출발지 선택과 검색 재개를 위한 두 행을 보여준다', (tester) async {
    final events = <String>[];
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapTopBar(
            showHamburger: false,
            onHamburgerTap: () {},
            controller: controller,
            focusNode: focusNode,
            onChanged: (_) {},
            onSubmitted: (_) {},
            searchActive: false,
            onCancelSearch: () {},
            onDirectionsTap: () => events.add('directions'),
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
    await tester.tap(find.byKey(const Key('route-draft-clear')));

    expect(events, ['origin', 'destination', 'clear']);
  });

  testWidgets('검색을 다시 열면 초안이 있어도 기존 검색 입력창을 쓴다', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapTopBar(
            showHamburger: false,
            onHamburgerTap: () {},
            controller: controller,
            focusNode: focusNode,
            onChanged: (_) {},
            onSubmitted: (_) {},
            searchActive: true,
            onCancelSearch: () {},
            onDirectionsTap: () {},
            routeDestinationLabel: '다이슨',
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const Key('route-draft-origin')), findsNothing);
  });
}
