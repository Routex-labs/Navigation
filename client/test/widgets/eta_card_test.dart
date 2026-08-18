import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/guidance/route_guidance.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// Runtime Kit의 계획 카드·안내 배너에 앱 경로 값이 올바르게 연결되는지 확인한다.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: child)),
  );

  RouteGuidanceInstruction turn({double toAction = 92}) =>
      RouteGuidanceInstruction(
        action: RouteGuidanceAction.turnRight,
        primaryText: '오른쪽 통로로 이동',
        distanceToActionM: toAction,
      );

  group('안내 중 상단 배너', () {
    testWidgets('다음 행동과 그 행동까지의 거리를 적는다', (tester) async {
      await tester.pumpWidget(wrap(GuidanceBanner(instruction: turn())));

      expect(find.text('오른쪽 통로로 이동'), findsOneWidget);
      expect(find.text('92m'), findsOneWidget);
    });

    testWidgets('도착 직전에는 소수점 한 자리까지 보여 준다', (tester) async {
      await tester.pumpWidget(
        wrap(GuidanceBanner(instruction: turn(toAction: 3.4))),
      );

      expect(find.text('3.4m'), findsOneWidget);
    });

    testWidgets('1 km가 넘으면 km로 적는다', (tester) async {
      await tester.pumpWidget(
        wrap(GuidanceBanner(instruction: turn(toAction: 1200))),
      );

      expect(find.text('1.2km'), findsOneWidget);
    });

    testWidgets('경로 이탈은 조작 지시 대신 재탐색 상태를 말한다', (tester) async {
      await tester.pumpWidget(
        wrap(
          const GuidanceBanner(
            instruction: RouteGuidanceInstruction(
              action: RouteGuidanceAction.wrongWay,
              primaryText: '반대 방향',
              distanceToActionM: 0,
            ),
          ),
        ),
      );

      expect(find.text('경로를 벗어났습니다'), findsOneWidget);
      expect(find.text('새 경로를 자동으로 찾고 있습니다'), findsOneWidget);
    });
  });

  group('안내 전 계획 카드', () {
    testWidgets('무엇을 향하는지와 소요·거리를 함께 적는다', (tester) async {
      await tester.pumpWidget(
        wrap(const EtaCard(distanceMeters: 480, minutes: 7, label: '건물 입구까지')),
      );

      expect(find.text('건물 입구까지'), findsOneWidget);
      expect(find.textContaining('7분', findRichText: true), findsOneWidget);
      expect(find.textContaining('480m', findRichText: true), findsOneWidget);
      expect(find.text('안내 종료'), findsNothing);
    });

    testWidgets('routeOptions을 건네면 요약 위에 그린다', (tester) async {
      await tester.pumpWidget(
        wrap(
          const EtaCard(
            distanceMeters: 3900,
            minutes: 8,
            label: '목적지까지',
            routeOptions: Text('옵션 영역'),
          ),
        ),
      );

      expect(find.text('옵션 영역'), findsOneWidget);
    });

    testWidgets('extraMetric을 건네면 소요·거리 옆에 함께 적는다', (tester) async {
      await tester.pumpWidget(
        wrap(
          EtaCard(
            distanceMeters: 3900,
            minutes: 8,
            label: '목적지까지',
            extraMetric: const RoutexTripMetric(value: '무료', label: '통행료'),
          ),
        ),
      );

      expect(find.textContaining('무료', findRichText: true), findsOneWidget);
      expect(find.textContaining('통행료', findRichText: true), findsOneWidget);
    });
  });

  testWidgets('안내 중에는 남은 값과 종료 동작을 보여 준다', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      wrap(
        EtaCard(
          distanceMeters: 150,
          minutes: 2,
          guidanceStarted: true,
          onClose: () => closed = true,
        ),
      ),
    );

    expect(find.text('2분'), findsOneWidget);
    expect(find.text('150m'), findsOneWidget);
    await tester.tap(find.text('안내 종료'));
    expect(closed, isTrue);
  });
}
