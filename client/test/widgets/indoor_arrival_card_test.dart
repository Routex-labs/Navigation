import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/widgets/indoor_arrival_card.dart';

Widget _host(Widget child, {double textScale = 1.0}) => MediaQuery(
  data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
  child: MaterialApp(home: Scaffold(body: Center(child: child))),
);

void main() {
  testWidgets('도착 사실과 목적지·층을 함께 말한다', (tester) async {
    await tester.pumpWidget(
      _host(
        IndoorArrivalCard(
          destinationName: '스타벅스 리저브',
          destinationFloor: 'B2',
          onConfirm: () {},
        ),
      ),
    );

    expect(find.text('도착했습니다'), findsOneWidget);
    expect(find.text('스타벅스 리저브'), findsOneWidget);
    expect(find.text('B2'), findsOneWidget);
  });

  testWidgets('층을 모르면 층 줄을 그리지 않는다', (tester) async {
    // "· 도착"만 남은 빈 줄은 정보가 아니라 여백이다.
    await tester.pumpWidget(
      _host(IndoorArrivalCard(destinationName: '레페토', onConfirm: () {})),
    );

    expect(find.text('레페토'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
