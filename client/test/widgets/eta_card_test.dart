import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/route_guidance.dart';
import 'package:navigation_client/widgets/eta_card.dart';

/// 안내 배너가 한 줄로 필요한 것만 말하는지에 대한 테스트.
///
/// 걸으면서 보는 화면에서 실제로 쓰는 정보는 **다음에 무엇을 할지와 몇 미터
/// 남았는지** 둘뿐이다. 그 거리는 총 남은거리가 아니라 다음 조작까지의
/// 거리여야 한다 — 두 값을 섞으면 사용자는 적힌 만큼 걷고도 모퉁이가 안 나오는
/// 화면을 본다.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  RouteGuidanceInstruction turn({double toAction = 92}) =>
      RouteGuidanceInstruction(
        action: RouteGuidanceAction.turnRight,
        primaryText: '오른쪽 통로로 이동',
        distanceToActionM: toAction,
      );

  group('안내 중 한 줄 배너', () {
    testWidgets('지시 문구와 다음 조작까지 거리를 적는다', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          EtaCard(
            // 총 남은거리는 일부러 다르게 준다. 배너가 이걸 쓰면 안 된다.
            distanceMeters: 480,
            minutes: 7,
            instruction: turn(),
          ),
        ),
      );

      expect(find.text('오른쪽 통로로 이동'), findsOneWidget);
      expect(find.text('92 m'), findsOneWidget);
      expect(
        find.textContaining('480'),
        findsNothing,
        reason: '총 남은거리를 적으면 다음 모퉁이까지의 거리와 섞인다',
      );
    });

    testWidgets('총 소요·총 남은거리 줄을 없앴다', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(EtaCard(distanceMeters: 480, minutes: 7, instruction: turn())),
      );

      expect(find.textContaining('약 7분'), findsNothing);
      expect(find.textContaining('남음'), findsNothing);
    });

    testWidgets('종료 콜백이 있으면 나갈 버튼이 있다', (WidgetTester tester) async {
      var closed = false;
      await tester.pumpWidget(
        wrap(
          EtaCard(
            distanceMeters: 480,
            minutes: 7,
            instruction: turn(),
            onClose: () => closed = true,
          ),
        ),
      );

      // 안내 중에는 지도 위 chrome이 접혀 있어 이 버튼이 유일한 탈출구다.
      await tester.tap(find.byKey(const Key('eta-card-close')));
      expect(closed, isTrue);
    });

    testWidgets('종료 콜백이 없으면 버튼도 없다', (WidgetTester tester) async {
      // 건물 입구까지 자동으로 그린 경로다. 사용자가 시작한 적이 없으니 끝낼
      // 것도 없고, 그래서 chrome도 접히지 않는다(shouldFoldGuidanceChrome).
      await tester.pumpWidget(
        wrap(EtaCard(distanceMeters: 480, minutes: 7, instruction: turn())),
      );

      expect(find.byKey(const Key('eta-card-close')), findsNothing);
    });

    testWidgets('도착 직전에는 소수점 한 자리까지 보여 준다', (WidgetTester tester) async {
      // 정수로만 반올림하면 마지막 몇 걸음 동안 "0 m"가 붙어 있어 안내가 멈춘
      // 것처럼 보인다.
      await tester.pumpWidget(
        wrap(
          EtaCard(
            distanceMeters: 4,
            minutes: 1,
            instruction: turn(toAction: 3.4),
          ),
        ),
      );

      expect(find.text('3.4 m'), findsOneWidget);
    });
  });

  group('안내가 없을 때(자동 경로)', () {
    testWidgets('예전 두 줄 표기를 그대로 쓴다', (WidgetTester tester) async {
      // 건물 입구까지 같은 경로에는 지시 문구가 없다. 그때까지 한 줄로 바꾸면
      // 화면에 남는 정보가 거리 하나뿐이라 무엇을 향한 거리인지 알 수 없다.
      await tester.pumpWidget(
        wrap(const EtaCard(distanceMeters: 480, minutes: 7, label: '건물 입구까지')),
      );

      expect(find.text('건물 입구까지'), findsOneWidget);
      // 이 줄은 RichText 스팬이라 기본 finder에 안 걸린다.
      expect(find.textContaining('약 7분', findRichText: true), findsOneWidget);
    });
  });
  group('도착 카드', () {
    RouteGuidanceInstruction arrived() => const RouteGuidanceInstruction(
      action: RouteGuidanceAction.arrived,
      primaryText: '목적지에 도착했습니다',
      distanceToActionM: 0,
    );

    testWidgets('목적지 이름과 층을 적는다', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          EtaCard(
            distanceMeters: 0,
            minutes: 1,
            instruction: arrived(),
            destinationName: '스타벅스 리저브',
            destinationFloor: 'B2',
          ),
        ),
      );

      expect(find.text('스타벅스 리저브'), findsOneWidget);
      expect(find.text('B2 · 목적지에 도착했습니다'), findsOneWidget);
    });

    testWidgets('남은 거리를 적지 않는다', (WidgetTester tester) async {
      // 도착은 다음 조작이 없는 유일한 상태다. 같은 한 줄 배너로 그리면
      // `0.0 m`만 붙은 이상한 줄이 된다.
      await tester.pumpWidget(
        wrap(
          EtaCard(
            distanceMeters: 0,
            minutes: 1,
            instruction: arrived(),
            destinationName: '스타벅스 리저브',
            destinationFloor: 'B2',
          ),
        ),
      );

      expect(find.textContaining(' m'), findsNothing);
    });

    testWidgets('층을 모르면 층 없이 적는다', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          EtaCard(
            distanceMeters: 0,
            minutes: 1,
            instruction: arrived(),
            destinationName: '스타벅스 리저브',
            destinationFloor: '',
          ),
        ),
      );

      expect(find.text('목적지에 도착했습니다'), findsOneWidget);
    });

    testWidgets('목적지를 모르면 예전 한 줄 배너로 떨어진다', (WidgetTester tester) async {
      // 야외 경로처럼 매장 정보가 없는 경우다. 이름 없는 도착 카드를 그리느니
      // 지시 문구를 그대로 보여 주는 편이 낫다.
      await tester.pumpWidget(
        wrap(EtaCard(distanceMeters: 0, minutes: 1, instruction: arrived())),
      );

      expect(find.text('목적지에 도착했습니다'), findsOneWidget);
    });

    testWidgets('끝내는 버튼은 X가 아니라 체크다', (WidgetTester tester) async {
      // 같은 동작이지만 도착에서는 취소가 아니라 확인이라, 아이콘이 다르면
      // 사용자가 "실패했나" 하고 망설이지 않는다.
      var closed = false;
      await tester.pumpWidget(
        wrap(
          EtaCard(
            distanceMeters: 0,
            minutes: 1,
            instruction: arrived(),
            destinationName: '스타벅스 리저브',
            destinationFloor: 'B2',
            onClose: () => closed = true,
          ),
        ),
      );

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      await tester.tap(find.byKey(const Key('eta-card-close')));
      expect(closed, isTrue);
    });
  });
}
