import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/models/directions_route.dart';
import 'package:navigation_client/models/transit_route.dart';
import 'package:navigation_client/repositories/transit_repository.dart';
import 'package:navigation_client/screens/route_planner/route_planner_view.dart';
import 'package:navigation_client/widgets/directions_candidate.dart';
import 'package:navigation_client/widgets/route_planner/route_plan_mode.dart';
import 'package:navigation_client/widgets/route_planner/route_planner_header.dart';
import 'package:navigation_client/widgets/sheet_grab_handle.dart';

/// 길찾기 **화면**의 회귀 테스트.
///
/// 예전에는 길찾기가 아래에서 올라오는 시트였다. 시트가 지도를 덮으니 경로를
/// 보려면 시트를 닫아야 했고, 닫으면 방금 넣은 출발/도착이 어디로 갔는지 알 수
/// 없었다. 이동 수단은 시트를 닫은 뒤 지도 위 다른 줄에서 골라야 했다.
///
/// 여기서 고정하려는 것은 그 셋이 한 화면에 모여 있다는 사실과, 대중교통에서만
/// 갈라지는 흐름(목록 → 상세 → 다시 목록)이다.
void main() {
  const store = DirectionsCandidate(
    title: 'MLB',
    subtitle: 'B2',
    point: LatLng(37.52, 126.92),
    nodeId: 'FL-2:ND-9',
    floor: 'B2',
  );
  const outdoorPlace = DirectionsCandidate(
    title: '한성대학교',
    subtitle: '서울 성북구',
    point: LatLng(37.582, 127.010),
  );
  const otherFloorStore = DirectionsCandidate(
    title: '스타벅스',
    subtitle: '4F',
    point: LatLng(37.521, 126.921),
    nodeId: 'FL-8:ND-3',
    floor: '4F',
  );

  late _FakeMap map;
  late TransitRepository originalTransitRepository;

  setUp(() {
    map = _FakeMap();
    originalTransitRepository = transitRepository;
  });

  tearDown(() {
    transitRepository = originalTransitRepository;
  });

  /// 프레임을 넉넉히 진행시킨다. 검색·경로 계산이 모두 Future라, 한 번만
  /// pump하면 목록이 아직 비어 있는 화면을 검사하게 된다.
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<_Recorder> pumpPlanner(
    WidgetTester tester, {
    DirectionsCandidate? origin,
    DirectionsCandidate? destination,
    RoutePlanMode? mode,
    RoutePlanField? field,
    List<DirectionsCandidate> results = const [],
    bool transitEnabled = true,
    bool indoorOnly = false,
  }) async {
    final recorder = _Recorder();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoutePlannerView(
            map: map,
            search: (query) async {
              recorder.queries.add(query);
              return results;
            },
            initialOrigin: origin,
            initialDestination: destination,
            initialMode: mode,
            initialField: field,
            transitEnabled: transitEnabled,
            indoorOnly: indoorOnly,
            onClose: () => recorder.closed = true,
            onEndpointsChanged: (o, d) {
              recorder.origin = o;
              recorder.destination = d;
              recorder.endpointCalls++;
            },
            onPickOnMap: (target) => recorder.pickTarget = target,
            onIndoorWalkRoute: (o, d) => recorder.indoorWalkDestination = d,
            onModeChanged: (m) => recorder.mode = m,
          ),
        ),
      ),
    );
    await drain(tester);
    return recorder;
  }

  testWidgets('수단 세 가지가 맨 위에, 출발/도착 칸이 그 아래에 있다', (
    WidgetTester tester,
  ) async {
    await pumpPlanner(tester);

    for (final mode in RoutePlanMode.values) {
      expect(
        find.byKey(ValueKey('route-plan-mode-${mode.name}')),
        findsOneWidget,
      );
    }
    // 순서가 화면의 전제다. 수단이 입력 아래로 내려가면 "어떻게 갈지 먼저
    // 고른다"는 이 화면의 흐름이 뒤집힌다.
    final carBottom = tester
        .getRect(find.byKey(const ValueKey('route-plan-mode-car')))
        .bottom;
    expect(
      tester.getRect(find.byKey(const Key('route-planner-origin-field'))).top,
      greaterThanOrEqualTo(carBottom),
    );
  });

  testWidgets('대중교통을 쓸 수 없으면 그 탭을 아예 감춘다', (WidgetTester tester) async {
    // 눌러서 "쓸 수 없습니다"를 보는 것보다 없는 편이 낫다.
    await pumpPlanner(tester, transitEnabled: false);

    expect(
      find.byKey(const ValueKey('route-plan-mode-transit')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('route-plan-mode-car')), findsOneWidget);
  });

  testWidgets('도착지를 고르면 그 자리에서 경로가 그려지고 요약 카드가 뜬다', (
    WidgetTester tester,
  ) async {
    final recorder = await pumpPlanner(
      tester,
      mode: RoutePlanMode.walk,
      results: const [outdoorPlace],
    );

    await tester.tap(find.text('한성대학교'));
    await drain(tester);

    // 예전 시트는 여기서 닫히고 지도로 돌아갔다. 이제는 화면이 그대로 있고
    // 결과만 아래에 붙는다 — 수단을 바꿔 비교하는 것이 이 화면의 목적이다.
    expect(recorder.closed, isFalse);
    expect(map.road, isNotNull, reason: '지도에 경로를 그리지 않았다');
    expect(find.byKey(const Key('route-planner-start')), findsOneWidget);
    expect(recorder.destination?.title, '한성대학교');
  });

  testWidgets('수단을 바꾸면 그리던 경로를 걷고 다시 계산한다', (WidgetTester tester) async {
    final recorder = await pumpPlanner(
      tester,
      destination: outdoorPlace,
      mode: RoutePlanMode.walk,
    );
    expect(map.road, isNotNull);
    final clearsBefore = map.clears;

    await tester.tap(find.byKey(const ValueKey('route-plan-mode-car')));
    await drain(tester);

    // 안 지우면 새 경로가 나올 때까지 옛 선이 남아, 지도와 카드가 서로 다른
    // 수단을 말하는 순간이 생긴다.
    expect(map.clears, greaterThan(clearsBefore));
    expect(map.road, isNotNull);
    expect(recorder.mode, RoutePlanMode.car);
  });

  testWidgets('도보로 건물 안 매장을 고르면 실내 안내로 넘긴다', (WidgetTester tester) async {
    // 그 안내는 문을 경유해 매장까지 이어지는 한 몸이라, 이 화면이 도로 경로
    // 하나로 그리면 건물 외벽에서 끝난다.
    final recorder = await pumpPlanner(
      tester,
      destination: store,
      mode: RoutePlanMode.walk,
    );

    expect(recorder.indoorWalkDestination?.title, 'MLB');
    expect(map.road, isNull);
  });

  testWidgets('실내 지도 탭에서는 도보만 남기고 실내 안내로 넘긴다', (WidgetTester tester) async {
    // 건물 안 두 지점 사이의 안내는 층 그래프로 풀어 실내 지도에 그려야 한다.
    // 이 화면이 쓰는 도로 경로는 야외 지도에만 그려지므로, 실내 탭에서 그리면
    // 보이지도 않는 지도에 선을 긋고 카드에는 건물을 관통하는 직선이 적힌다.
    final recorder = await pumpPlanner(
      tester,
      destination: outdoorPlace,
      indoorOnly: true,
    );

    expect(find.byKey(const ValueKey('route-plan-mode-car')), findsNothing);
    expect(find.byKey(const ValueKey('route-plan-mode-transit')), findsNothing);
    expect(find.byKey(const ValueKey('route-plan-mode-walk')), findsOneWidget);
    expect(recorder.indoorWalkDestination?.title, '한성대학교');
    expect(map.road, isNull);
  });

  testWidgets('다른 층 매장도 후보 목록에 그대로 뜬다', (WidgetTester tester) async {
    // 예전에는 현재 층으로 좁혀 검색하고 토글로 넓히게 했다. 길찾기를 여는
    // 이유 자체가 대개 "지금 층에 없는 곳으로 가려고"라 기본값이 반대였다.
    final recorder = await pumpPlanner(
      tester,
      results: const [store, otherFloorStore],
    );

    expect(recorder.queries, isNotEmpty, reason: '화면이 열리며 검색을 위임해야 한다');
    expect(find.text('스타벅스'), findsOneWidget);
    expect(find.text('MLB'), findsOneWidget);
    // 어느 층 매장인지는 각 줄이 알려줘야 한다. 층 표시가 없으면 사용자는 지금
    // 층 매장인 줄 알고 고른다.
    expect(find.text('4F'), findsOneWidget);
    expect(find.text('B2'), findsOneWidget);
    // 층 범위 토글이 다른 문구로 되살아나지 않았는지 함께 고정한다.
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('"지도에서 선택"은 지금 고치는 칸을 상위에 알린다', (WidgetTester tester) async {
    final recorder = await pumpPlanner(tester);

    // 도착지 칸이 열린 채로 시작한다.
    expect(find.text('지도에서 매장을 눌러 도착지로 지정합니다'), findsOneWidget);
    await tester.tap(find.byKey(const Key('route-planner-pick-on-map')));
    await drain(tester);
    expect(recorder.pickTarget, DirectionsMapPickTarget.destination);

    // 출발지 칸으로 옮기면 같은 자리에서 대상만 바뀐다. 두 칸의 조작 방법이
    // 다르면 사용자는 한쪽에만 있는 기능을 없는 것으로 여긴다.
    await tester.tap(find.byKey(const Key('route-planner-origin-field')));
    await drain(tester);
    expect(find.text('지도에서 매장을 눌러 출발지로 지정합니다'), findsOneWidget);
    await tester.tap(find.byKey(const Key('route-planner-pick-on-map')));
    await drain(tester);
    expect(recorder.pickTarget, DirectionsMapPickTarget.origin);
  });

  testWidgets('출발지 칸에서만 맨 위에 "현재 위치"가 붙는다', (WidgetTester tester) async {
    await pumpPlanner(tester, results: const [outdoorPlace]);

    expect(
      find.byKey(const Key('route-planner-current-location')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('route-planner-origin-field')));
    await drain(tester);

    // 따로 고르지 않으면 현재 위치가 출발지이므로, 되돌아올 길이 목록 안에
    // 있어야 한다.
    expect(
      find.byKey(const Key('route-planner-current-location')),
      findsOneWidget,
    );
  });

  group('대중교통', () {
    setUp(() {
      transitRepository = _FakeTransitRepository(
        TransitRoutes.ok([_itinerary(2400), _itinerary(3000)]),
      );
    });

    testWidgets('목록을 먼저 보여 주고 고르기 전에는 지도에 그리지 않는다', (
      WidgetTester tester,
    ) async {
      await pumpPlanner(
        tester,
        destination: outdoorPlace,
        mode: RoutePlanMode.transit,
      );

      expect(find.text('40분'), findsOneWidget);
      expect(find.text('50분'), findsOneWidget);
      expect(map.transit, isNull, reason: '고르기도 전에 경로를 그렸다');
    });

    testWidgets('하나를 고르면 지도에 그리고 끌 수 있는 상세 시트를 연다', (
      WidgetTester tester,
    ) async {
      await pumpPlanner(
        tester,
        destination: outdoorPlace,
        mode: RoutePlanMode.transit,
      );

      await tester.tap(find.text('40분'));
      await drain(tester);

      expect(map.transit, isNotNull);
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      // 손잡이가 없으면 고정 높이 카드처럼 보여, 잘린 구간 목록을 끌어 올릴 수
      // 있다는 걸 사용자가 모른다.
      expect(find.byType(SheetGrabHandle), findsOneWidget);
    });

    testWidgets('상세의 X는 지도를 걷고 목록으로 되돌아간다', (WidgetTester tester) async {
      // 지도로 닫아 버리면 다른 후보를 보려고 처음부터 다시 조회하게 된다.
      await pumpPlanner(
        tester,
        destination: outdoorPlace,
        mode: RoutePlanMode.transit,
      );
      await tester.tap(find.text('40분'));
      await drain(tester);

      await tester.tap(find.byKey(const Key('transit-detail-back')));
      await drain(tester);

      expect(map.transit, isNull, reason: '되돌아왔는데 경로선이 지도에 남았다');
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.text('40분'), findsOneWidget);
      expect(find.text('50분'), findsOneWidget);
    });

    testWidgets('너무 가까우면 도보로 넘어갈 길을 준다', (WidgetTester tester) async {
      // 사용자가 원한 것은 "저기까지 가는 방법"이지 "대중교통 그 자체"가 아니다.
      transitRepository = _FakeTransitRepository(
        const TransitRoutes.failure(TransitRoutesStatus.tooClose),
      );
      await pumpPlanner(
        tester,
        destination: outdoorPlace,
        mode: RoutePlanMode.transit,
      );

      expect(find.byKey(const Key('route-planner-error')), findsOneWidget);
      await tester.tap(find.text('도보로 보기'));
      await drain(tester);

      expect(map.road, isNotNull);
    });
  });
}

/// 두 정거장짜리 가짜 여정. 총 시간만 바꿔 목록의 두 줄을 구분한다.
TransitItinerary _itinerary(int totalSeconds) => TransitItinerary(
  totalTimeSeconds: totalSeconds,
  totalWalkTimeSeconds: 300,
  totalDistanceMeters: 12000,
  transferCount: 0,
  fare: 1500,
  legs: const [
    TransitLeg(
      mode: TransitMode.walk,
      sectionTimeSeconds: 300,
      distanceMeters: 319,
      points: [LatLng(37.5, 127.0), LatLng(37.51, 127.01)],
      startName: '출발지',
      endName: '뉴고려병원',
    ),
    TransitLeg(
      mode: TransitMode.bus,
      sectionTimeSeconds: 3180,
      distanceMeters: 11000,
      points: [LatLng(37.51, 127.01), LatLng(37.58, 127.01)],
      routeName: '직행:8600',
      startName: '뉴고려병원',
      endName: '여의도환승센터',
      stationCount: 13,
    ),
  ],
);

class _Recorder {
  final queries = <String>[];
  bool closed = false;
  int endpointCalls = 0;
  DirectionsCandidate? origin;
  DirectionsCandidate? destination;
  DirectionsCandidate? indoorWalkDestination;
  DirectionsMapPickTarget? pickTarget;
  RoutePlanMode? mode;
}

class _FakeMap implements RoutePlannerMap {
  LatLng? origin = const LatLng(37.5, 127.0);
  DirectionsRoute? road;
  TransitItinerary? transit;
  int clears = 0;

  @override
  LatLng? get currentOriginPoint => origin;

  @override
  LatLng resolveRoadEndpoint(LatLng point) => point;

  @override
  Future<void> showRoadRoute(
    DirectionsRoute route, {
    required LatLng origin,
    required LatLng destination,
    required String label,
  }) async {
    road = route;
  }

  @override
  Future<void> showTransitItinerary(
    TransitItinerary itinerary, {
    required LatLng origin,
    required LatLng destination,
    required String label,
  }) async {
    transit = itinerary;
  }

  @override
  void clearPlannedRoute() {
    clears++;
    road = null;
    transit = null;
  }
}

class _FakeTransitRepository implements TransitRepository {
  _FakeTransitRepository(this.routes);

  final TransitRoutes routes;

  @override
  bool get isAvailable => true;

  @override
  Future<TransitRoutes> getTransitRoutes({
    required LatLng origin,
    required LatLng destination,
    int count = 0,
  }) async => routes;
}
