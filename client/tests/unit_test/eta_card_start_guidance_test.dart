import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/widgets/eta_card.dart';

/// "안내 시작"은 자동차 경로를 **계획 상태**로 그려 둔 동안만 뜬다.
///
/// 경로를 그리자마자 카메라를 현재 위치로 확대하면 사용자는 전체 경로를 한 번도
/// 못 보고 안내에 들어간다. 그래서 계획(경로 전체)과 안내(내 위치)를 버튼 하나로
/// 나눴고, 이 테스트가 그 버튼의 유무 규칙을 지킨다.
void main() {
  Widget host({VoidCallback? onStartGuidance, VoidCallback? onClose}) {
    return MaterialApp(
      home: Scaffold(
        body: EtaCard(
          distanceMeters: 5200,
          minutes: 14,
          label: '강남역까지',
          onClose: onClose,
          onStartGuidance: onStartGuidance,
        ),
      ),
    );
  }

  testWidgets('콜백을 주면 안내 시작 버튼이 뜬다', (tester) async {
    var started = false;
    await tester.pumpWidget(host(onStartGuidance: () => started = true));
    await tester.pump();

    expect(find.text('안내 시작'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('eta-start-guidance')));
    await tester.pump();
    expect(started, isTrue);
  });

  testWidgets('콜백이 없으면 버튼이 아예 없다 — 도보·이미 안내 중인 자동차', (tester) async {
    await tester.pumpWidget(host(onClose: () {}));
    await tester.pump();

    expect(find.text('안내 시작'), findsNothing);
    // 종료는 그대로 남아야 한다. 시작 버튼을 감추느라 같이 사라지면 안내를
    // 그만둘 방법이 화면에서 없어진다.
    expect(find.text('안내 종료'), findsOneWidget);
  });

  testWidgets('시작과 종료가 함께 뜰 때 순서는 시작 → 종료', (tester) async {
    await tester.pumpWidget(host(onStartGuidance: () {}, onClose: () {}));
    await tester.pump();

    final start = tester.getTopLeft(find.text('안내 시작')).dx;
    final close = tester.getTopLeft(find.text('안내 종료')).dx;
    // 권하는 행동이 먼저 읽히고, 되돌리기 어려운 조작이 바깥쪽에 온다.
    expect(start, lessThan(close));
  });
}
