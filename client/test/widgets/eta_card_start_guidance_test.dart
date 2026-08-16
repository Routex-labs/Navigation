import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/eta_card.dart';

/// "안내 시작"은 자동차 경로를 **계획 상태**로 그려 둔 동안만 뜬다.
///
/// 경로를 그리자마자 카메라를 현재 위치로 확대하면 사용자는 전체 경로를 한 번도
/// 못 보고 안내에 들어간다. 그래서 계획(경로 전체)과 안내(내 위치)를 버튼 하나로
/// 나눴고, 이 테스트가 그 버튼의 유무 규칙을 지킨다.
void main() {
  Widget host({VoidCallback? onStartGuidance, VoidCallback? onClose}) {
    return MaterialApp(theme: AppTheme.light, home: Scaffold(
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

  testWidgets('계획 상태에서는 안내 시작만 뜬다', (tester) async {
    var started = false;
    await tester.pumpWidget(
      host(onStartGuidance: () => started = true, onClose: () {}),
    );
    await tester.pump();

    expect(find.text('안내 시작'), findsOneWidget);
    // 아직 출발도 안 했는데 "종료"가 함께 있으면, 무엇이 이미 시작됐는지부터
    // 헷갈린다. 계획을 접는 길은 상단 길찾기 바에 있다.
    expect(find.text('안내 종료'), findsNothing);

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

  testWidgets('안내를 시작하면 종료만 남는다', (tester) async {
    // 안내가 시작되면 호출부가 onStartGuidance를 null로 내린다
    // (OutdoorMapBodyState._offerStartGuidance). 그 상태를 그대로 그린다.
    await tester.pumpWidget(host(onClose: () {}));
    await tester.pump();

    expect(find.text('안내 시작'), findsNothing);
    expect(find.text('안내 종료'), findsOneWidget);
  });
}
