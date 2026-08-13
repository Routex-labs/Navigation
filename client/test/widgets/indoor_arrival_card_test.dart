import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/widgets/indoor_arrival_card.dart';

Widget _host(Widget child, {double textScale = 1.0}) => MediaQuery(
  data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
  child: MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('목적지 이름이 제목이고 층은 그 아래에 붙는다', (tester) async {
    // 어디에 도착했는지가 먼저다. "도착했습니다"를 크게 쓰면 정작 매장 이름이
    // 두 번째 줄로 밀린다.
    await tester.pumpWidget(
      _host(
        IndoorArrivalCard(
          destinationName: '스타벅스 리저브',
          destinationFloor: 'B2',
          onConfirm: () {},
        ),
      ),
    );

    expect(find.text('스타벅스 리저브'), findsOneWidget);
    expect(find.text('B2 · 도착했습니다'), findsOneWidget);
  });

  testWidgets('층을 모르면 층 없이 도착만 말한다', (tester) async {
    await tester.pumpWidget(
      _host(IndoorArrivalCard(destinationName: '레페토', onConfirm: () {})),
    );

    expect(find.text('레페토'), findsOneWidget);
    expect(find.text('도착했습니다'), findsOneWidget);
  });

  testWidgets('띡 하고 나타나지 않고 떠오르며 들어온다', (tester) async {
    await tester.pumpWidget(
      _host(IndoorArrivalCard(destinationName: '레페토', onConfirm: () {})),
    );
    await tester.pump();
    final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
    expect(opacity.opacity, lessThan(1.0), reason: '첫 프레임부터 불투명하면 등장이 없다');

    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 1.0);
  });

  testWidgets('안내 종료를 누르면 상위에 알린다', (tester) async {
    var confirmed = false;
    await tester.pumpWidget(
      _host(
        IndoorArrivalCard(
          destinationName: '레페토',
          onConfirm: () => confirmed = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('indoor-arrival-confirm')));

    expect(confirmed, isTrue);
  });

  testWidgets('큰 글자 배율에서도 넘치지 않는다', (tester) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 280,
          child: IndoorArrivalCard(
            destinationName: '포인트 오브 뷰 성수 플래그십 스토어',
            destinationFloor: 'B2',
            onConfirm: _noop,
          ),
        ),
        textScale: 2,
      ),
    );

    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
