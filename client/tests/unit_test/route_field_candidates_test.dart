import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/domain/dijkstra.dart';
import 'package:navigation_client/domain/store_suggestions.dart';
import 'package:navigation_client/models/store_index_entry.dart';
import 'package:navigation_client/repositories/building_repository.dart';
import 'package:navigation_client/repositories/destination_repository.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/widgets/directions_candidate.dart';
import 'package:navigation_client/widgets/route_field_results.dart';
import 'package:navigation_client/widgets/route_plan_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 상단 길찾기 바의 **후보 목록**이 무엇을 보여 주는지 고정하는 테스트.
///
/// 이 규칙들은 한동안 길찾기 시트가 들고 있었다(`directions_sheet.dart`).
/// 길찾기가 상단 바 두 칸으로 돌아오면서 그 시트를 걷어냈으므로, 시트가 지키던
/// 계약을 여기서 이어받는다 — 규칙이 화면을 옮겼을 뿐 없어진 것이 아니다.
void main() {
  group('후보 목록이 보여 주는 것', () {
    const point = LatLng(37.5, 127.0);

    Future<void> pumpResults(
      WidgetTester tester, {
      List<DirectionsCandidate> results = const [],
      List<StoreSuggestion> suggestions = const [],
      Map<String, NodeReach>? reachByNodeId,
      RoutePlanField field = RoutePlanField.destination,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteFieldResults(
              field: field,
              results: results,
              suggestions: suggestions,
              onSuggestionPicked: (_) {},
              reachByNodeId: reachByNodeId,
              searching: false,
              onPicked: (_) {},
              onPickOnMap: () {},
              showPickOnMap: false,
              onCurrentLocation: () {},
            ),
          ),
        ),
      );
    }

    testWidgets('거리를 알면 후보 줄에 "몇 m · 도보 몇 분"이 붙는다', (tester) async {
      await pumpResults(
        tester,
        results: const [
          DirectionsCandidate(
            title: 'MLB',
            subtitle: 'B2',
            point: point,
            nodeId: 'n-1',
            floor: 'B2',
          ),
        ],
        reachByNodeId: const {
          'n-1': NodeReach(distanceM: 120, costM: 120),
        },
      );

      expect(find.textContaining('120m'), findsOneWidget);
    });

    testWidgets('거리를 모르면 그 줄을 아예 그리지 않는다', (tester) async {
      // 줄마다 "거리 알 수 없음"을 반복하면 목록이 읽히지 않는다. 상단 검색
      // 결과와 같은 규칙이다.
      await pumpResults(
        tester,
        results: const [
          DirectionsCandidate(
            title: 'MLB',
            subtitle: 'B2',
            point: point,
            nodeId: 'n-1',
            floor: 'B2',
          ),
        ],
      );

      expect(find.textContaining('도보'), findsNothing);
      expect(find.text('B2'), findsOneWidget);
    });

    testWidgets('노드가 없는 실내 후보는 경로 안내 불가라고 미리 알린다', (tester) async {
      // 고를 수는 있게 둔다 — 위치는 지도에 보여줄 수 있다. 대신 눌러도 경로가
      // 안 나오는 이유를 목록에서 먼저 읽을 수 있어야 한다.
      await pumpResults(
        tester,
        results: const [
          DirectionsCandidate(
            title: '창고',
            subtitle: 'B2',
            point: point,
            floor: 'B2',
          ),
        ],
      );

      expect(find.textContaining('경로 안내 불가'), findsOneWidget);
    });

    testWidgets('추천 이유가 있으면 층 대신 그 문장을 보여준다', (tester) async {
      // 의미 검색이 준 후보다. "왜 이 매장이 나왔는지"가 층 라벨보다 중요하다.
      await pumpResults(
        tester,
        results: const [
          DirectionsCandidate(
            title: '한식당',
            subtitle: '5F',
            point: point,
            nodeId: 'n-2',
            floor: '5F',
            reason: '따뜻한 국물 요리를 파는 곳이에요',
          ),
        ],
      );

      expect(find.text('따뜻한 국물 요리를 파는 곳이에요'), findsOneWidget);
      expect(find.text('5F'), findsNothing);
    });

    testWidgets('온디바이스 후보는 서버 결과보다 위에 붙는다', (tester) async {
      // 서버를 기다리지 않고 0ms에 나오는 값이라, 사용자가 치는 동안 이 자리가
      // 먼저 찬다.
      const entry = StoreIndexEntry(
        id: 'store-1',
        name: '스타벅스',
        floorId: 'B2',
        floorName: 'B2',
        entranceNodeId: 'n-3',
      );
      await pumpResults(
        tester,
        suggestions: const [
          (kind: SuggestionKind.prefix, stores: [entry]),
        ],
        results: const [
          DirectionsCandidate(
            title: '서버가 찾은 곳',
            subtitle: '1F',
            point: point,
            nodeId: 'n-4',
            floor: '1F',
          ),
        ],
      );

      final suggestionY = tester
          .getTopLeft(find.byKey(const Key('route-field-suggestion-store-1')))
          .dy;
      final serverY = tester.getTopLeft(find.text('서버가 찾은 곳')).dy;
      expect(suggestionY, lessThan(serverY));
    });
  });

  group('출발↔도착 교체', () {
    late BuildingRepository originalBuildingRepository;
    late DestinationRepository originalDestinationRepository;
    final repository = MockBuildingRepository();

    /// 데모 건물 외곽선 한가운데 + 신뢰할 수 있는 신호. 이 좌표 한 건이면 자동
    /// 실내 진입이 발동해 "건물 안을 보고 있는" 상태가 된다.
    Position insideBuilding() => Position(
      latitude: 37.5665,
      longitude: 126.9780,
      timestamp: DateTime(2024, 1, 1),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

    Future<void> drain(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    setUp(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await debugModeController.reload();
      originalBuildingRepository = buildingRepository;
      originalDestinationRepository = destinationRepository;
      buildingRepository = repository;
      destinationRepository = MockDestinationRepository(repository);
      requestStartupPermissions = () async => {};
      await repository.getAllBuildings();
    });

    tearDown(() {
      buildingRepository = originalBuildingRepository;
      destinationRepository = originalDestinationRepository;
      requestStartupPermissions = defaultRequestStartupPermissions;
      watchPosition = defaultWatchPosition;
    });

    Future<void> openRouteMode(WidgetTester tester) async {
      // 기본 800x600에서는 거리 줄이 붙은 후보가 몇 줄 안 들어가 뒤쪽 행이 화면
      // 밖으로 밀린다. 여기서 보려는 것은 레이아웃이 아니라 버튼의 상태다.
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final positions = StreamController<Position>.broadcast();
      addTearDown(positions.close);
      watchPosition = () => positions.stream;

      await tester.pumpWidget(const MaterialApp(home: MapShellScreen()));
      await drain(tester);
      positions.add(insideBuilding());
      await drain(tester);

      await tester.tap(find.byTooltip('길찾기'));
      await drain(tester);
    }

    testWidgets('출발지가 현재 위치면 누를 수 없다', (WidgetTester tester) async {
      await openRouteMode(tester);

      // 교체하면 지금 출발지가 도착지가 되는데, "현재 위치"는 그럴 후보 객체가
      // 아예 없다 — 출발지 칸에서만 null이라는 뜻으로 표현되는 특수값이다.
      // 못 누르는 상태에서도 **버튼은 남긴다.** 사라지면 사용자는 기능이 없다고
      // 결론짓고 다시 찾지 않는다.
      final swap = find.byKey(const Key('route-draft-swap'));
      expect(swap, findsOneWidget);
      expect(tester.widget<IconButton>(swap).onPressed, isNull);
    });

    testWidgets('출발지를 고르면 열린다', (WidgetTester tester) async {
      await openRouteMode(tester);

      final originField = find.descendant(
        of: find.byKey(const Key('route-draft-origin')),
        matching: find.byType(TextField),
      );
      await tester.tap(originField);
      await drain(tester);
      await tester.enterText(originField, '강의실');
      await drain(tester);
      await tester.tap(find.text('강의실 101').first);
      await drain(tester);

      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('route-draft-swap')))
            .onPressed,
        isNotNull,
        reason: '출발지가 실제 후보면 도착지 자리로 옮길 수 있다',
      );
    });
  });
}
