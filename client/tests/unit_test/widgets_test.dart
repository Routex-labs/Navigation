import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/models/poi_search_result.dart';
import 'package:navigation_client/repositories/destination_repository.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:navigation_client/widgets/location_marker.dart';
import 'package:navigation_client/widgets/rag_chat_panel.dart';
import 'package:navigation_client/widgets/status_badge.dart';
import 'package:navigation_client/widgets/uncertainty_circle.dart';

void main() {
  testWidgets('LocationMarker uses the outdoor mode color by default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LocationMarker(mode: LocationMode.outdoor),
      ),
    );

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.navigation);
    expect(icon.color, AppColors.primary);
  });

  testWidgets('LocationMarker colorOverride wins over the mode color', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LocationMarker(
          mode: LocationMode.outdoor,
          colorOverride: Colors.amber,
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, Colors.amber);
  });

  testWidgets('UncertaintyCircle renders with the requested diameter', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: UncertaintyCircle(diameter: 40, color: Colors.purple),
      ),
    );

    final box = tester.widget<SizedBox>(find.byType(SizedBox));
    expect(box.width, 40);
    expect(box.height, 40);
  });

  testWidgets('StatusBadge shows the given label', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StatusBadge(label: 'GPS 신호 약함'),
      ),
    );

    expect(find.text('GPS 신호 약함'), findsOneWidget);
  });

  testWidgets('EtaCard shows the distance and minutes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: EtaCard(distanceMeters: 150, minutes: 2),
      ),
    );

    expect(find.text('목적지까지'), findsOneWidget);
    expect(find.textContaining('약 2분', findRichText: true), findsOneWidget);
    expect(find.textContaining('150m', findRichText: true), findsOneWidget);
  });

  group('RagChatPanel', () {
    // 전역을 선언 시점에 읽으면 lazy 초기화가 테스트 존 밖에서 일어나
    // HttpDestinationRepository의 http.Client 생성이 터진다. setUp 안에서 잡는다.
    late DestinationRepository originalRepository;

    setUp(() => originalRepository = destinationRepository);
    tearDown(() => destinationRepository = originalRepository);

    Future<void> pumpPanel(WidgetTester tester) => tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RagChatPanel(buildingId: 'thehyundai-seoul')),
      ),
    );

    testWidgets('질의 전에는 안내 문구만 보여준다', (WidgetTester tester) async {
      destinationRepository = _FakeDestinationRepository();
      await pumpPanel(tester);

      expect(find.text('AI 매장 찾기'), findsOneWidget);
      expect(find.textContaining('의미가 가장 가까운 매장'), findsOneWidget);
    });

    testWidgets('찾은 매장의 이름과 층을 답으로 보여준다', (WidgetTester tester) async {
      destinationRepository = _FakeDestinationRepository(
        result: const PoiSearchResult(
          name: '스시코우지',
          floor: 'B1',
          point: LatLng(37.52, 126.92),
          nodeId: 'FL-1:ND-1',
        ),
      );
      await pumpPanel(tester);

      await tester.enterText(find.byType(TextField), '밥 먹을 곳');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      // 사용자 질의와 결과가 모두 남는다.
      expect(find.text('밥 먹을 곳'), findsOneWidget);
      expect(find.textContaining('스시코우지'), findsOneWidget);
      expect(find.textContaining('B1'), findsOneWidget);
    });

    testWidgets('응답을 기다리는 동안 진행 표시를 띄운다', (WidgetTester tester) async {
      // 2차 의미 검색은 임베딩 모델 로드로 수 초 걸릴 수 있어, 그 동안 UI가
      // 멈춘 것처럼 보이면 안 된다.
      final repository = _FakeDestinationRepository(
        result: const PoiSearchResult(
          name: '스시코우지',
          floor: 'B1',
          point: LatLng(37.52, 126.92),
          nodeId: 'FL-1:ND-1',
        ),
        delay: const Duration(seconds: 3),
      );
      destinationRepository = repository;
      await pumpPanel(tester);

      await tester.enterText(find.byType(TextField), '밥 먹을 곳');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(find.text('찾는 중…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 4));
      expect(find.text('찾는 중…'), findsNothing);
      expect(find.textContaining('스시코우지'), findsOneWidget);
    });

    testWidgets('no_match면 못 찾았다고 안내한다', (WidgetTester tester) async {
      destinationRepository = _FakeDestinationRepository();
      await pumpPanel(tester);

      await tester.enterText(find.byType(TextField), 'asdfqwerzxcv');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.textContaining('찾지 못했어요'), findsOneWidget);
    });

    testWidgets('ok_no_route면 경로 안내가 어렵다고 덧붙인다', (WidgetTester tester) async {
      // nodeId가 null이면 온디바이스 다익스트라의 도착점이 없다.
      destinationRepository = _FakeDestinationRepository(
        result: const PoiSearchResult(
          name: '팝업스토어',
          floor: '5F',
          point: LatLng(37.52, 126.92),
        ),
      );
      await pumpPanel(tester);

      await tester.enterText(find.byType(TextField), '팝업');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.textContaining('경로 안내는 어려워요'), findsOneWidget);
    });

    testWidgets('서버 장애에도 패널이 살아 있고 안내만 바뀐다', (WidgetTester tester) async {
      destinationRepository = _FakeDestinationRepository(fail: true);
      await pumpPanel(tester);

      await tester.enterText(find.byType(TextField), '밥 먹을 곳');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.textContaining('잠시 후 다시 시도'), findsOneWidget);
      // 다음 질의를 계속 받을 수 있어야 한다.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('공백만 입력하면 백엔드를 호출하지 않는다', (WidgetTester tester) async {
      // 백엔드가 공백 질의를 422로 막으므로 아예 보내지 않는다.
      final repository = _FakeDestinationRepository();
      destinationRepository = repository;
      await pumpPanel(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(repository.aiQueries, isEmpty);
    });
  });
}

/// [RagChatPanel]이 쓰는 것은 searchDestinationsAi 하나뿐이라 그 경로만 흉내낸다.
class _FakeDestinationRepository implements DestinationRepository {
  _FakeDestinationRepository({this.result, this.fail = false, this.delay});

  final PoiSearchResult? result;
  final bool fail;
  final Duration? delay;
  final aiQueries = <String>[];

  @override
  Future<List<PoiSearchResult>> searchDestinationsAi(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) async {
    aiQueries.add(query);
    if (delay != null) await Future<void>.delayed(delay!);
    if (fail) throw Exception('boom');
    return result == null ? const [] : [result!];
  }

  @override
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) async => const [];
}
