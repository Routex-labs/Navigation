import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/repositories/routing/transit_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/transit_routes_sheet.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/transit_summary_card.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/state/recent_route_points_controller.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `대중교통` 칩이 자동차·도보와 **같은 그림**을 내는지에 대한 회귀 테스트.
///
/// 사용자가 지적한 화면은 "대중교통을 눌렀는데 지도에는 아직 자동차 경로가
/// 떠 있는" 것이었다. 조회가 끝나면 목록을 열기 전에 첫 후보를 미리 그린다.
/// 하네스(`fix()`·`drain()`·저장소 교체)는 `back_steps_out_of_route_test.dart`와 같다.
class _FakeTransitRepository implements TransitRepository {
  _FakeTransitRepository(this.answer);

  final TransitRoutes answer;

  @override
  bool get isAvailable => true;

  @override
  Future<TransitRoutes> getTransitRoutes({
    required LatLng origin,
    required LatLng destination,
    int count = 0,
  }) async => answer;
}

/// 첫·마지막 구간을 **도보로** 둔다. 그래야 목록 단계의 보행자 조회가 아예
/// 안 나가, 미리보기가 새 호출을 부르는지 여부가 로그에서 바로 보인다.
/// [fare]로 후보를 구분한다 — 미리보기가 첫 후보인지 보는 손잡이다.
TransitItinerary _itinerary(int fare) => TransitItinerary(
  totalTimeSeconds: 1200,
  totalWalkTimeSeconds: 300,
  totalDistanceMeters: 3000,
  transferCount: 0,
  fare: fare,
  legs: [
    // 첫 점이 아래 GPS 좌표다.
    TransitLeg(
      mode: TransitMode.walk,
      sectionTimeSeconds: 300,
      distanceMeters: 200,
      points: const [LatLng(37.5665, 126.9800), LatLng(37.5670, 126.9805)],
    ),
    TransitLeg(
      mode: TransitMode.bus,
      sectionTimeSeconds: 600,
      distanceMeters: 2600,
      points: const [LatLng(37.5670, 126.9805), LatLng(37.5720, 126.9900)],
      startName: '앞 정류장',
      endName: '뒤 정류장',
      stationCount: 3,
    ),
    TransitLeg(
      mode: TransitMode.walk,
      sectionTimeSeconds: 300,
      distanceMeters: 200,
      points: const [LatLng(37.5720, 126.9900), LatLng(37.5725, 126.9905)],
    ),
  ],
);

/// 좌표가 하나도 없는 후보. 그릴 선이 없다.
TransitItinerary _pointlessItinerary() => TransitItinerary(
  totalTimeSeconds: 1200,
  totalWalkTimeSeconds: 300,
  totalDistanceMeters: 3000,
  transferCount: 0,
  fare: 1500,
  legs: [
    TransitLeg(
      mode: TransitMode.bus,
      sectionTimeSeconds: 600,
      distanceMeters: 2600,
      points: const [],
      startName: '앞 정류장',
      endName: '뒤 정류장',
      stationCount: 3,
    ),
  ],
);

void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;
  late RecentRoutePointsController originalRecents;
  late TransitRepository originalTransitRepository;

  final repository = MockBuildingRepository();

  // 건물 밖 좌표. 건물 안이면 GPS가 실내 진입을 발동시켜 야외 흐름이 갈라진다.
  Position fix() => Position(
    latitude: 37.5665,
    longitude: 126.9800,
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
    originalRecents = recentRoutePointsController;
    originalTransitRepository = transitRepository;
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    recentRoutePointsController = RecentRoutePointsController();
    await recentRoutePointsController.ready;
    requestStartupPermissions = () async => {};
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    recentRoutePointsController = originalRecents;
    transitRepository = originalTransitRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  Future<void> pumpShell(WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);
    positions.add(fix());
    await drain(tester);
  }

  Finder destinationField() => find.descendant(
    of: find.byKey(const Key('route-draft-destination')),
    matching: find.byType(TextField),
  );

  /// 강의실까지 도보 경로를 그린 뒤 `대중교통`으로 갈아탄다. 갈아타기 전의
  /// 도보 경로가 있어야 "앞 수단이 남는가"를 볼 수 있다.
  Future<void> tapTransit(WidgetTester tester, TransitRoutes answer) async {
    transitRepository = _FakeTransitRepository(answer);
    await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    await tester.enterText(destinationField(), '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    expect(
      find.byType(EtaCard),
      findsOneWidget,
      reason: '테스트 전제(앞 수단인 도보 경로가 그려짐)가 성립하지 않았다',
    );
    await tester.tap(find.text('대중교통'));
    await drain(tester);
  }

  TransitItinerary previewed(WidgetTester tester) => tester
      .widget<TransitSummaryCard>(find.byType(TransitSummaryCard))
      .itinerary;

  testWidgets('목록을 열 때 첫 후보가 이미 지도에 그려져 있다', (WidgetTester tester) async {
    await tapTransit(
      tester,
      TransitRoutes.ok([_itinerary(1500), _itinerary(1600)]),
    );

    expect(find.byType(TransitRoutesSheet), findsOneWidget);
    expect(
      find.byType(TransitSummaryCard),
      findsOneWidget,
      reason: '고르기 전에도 대중교통 경로가 그려져 있어야 한다',
    );
    expect(previewed(tester).fare, 1500, reason: '미리 그리는 것은 첫(최적) 후보다');
    // 그리는 것이 곧 치우는 것이다 — 대중교통 요약 카드가 도보 ETA 카드를 밀어낸다.
    expect(
      find.byType(EtaCard),
      findsNothing,
      reason: '대중교통을 눌렀는데 앞 수단 경로가 남아 있으면 안 된다',
    );
  });

  testWidgets('목록을 아무것도 안 고르고 닫아도 미리보기는 남는다', (WidgetTester tester) async {
    await tapTransit(
      tester,
      TransitRoutes.ok([_itinerary(1500), _itinerary(1600)]),
    );
    await tester.binding.handlePopRoute();
    await drain(tester);

    expect(find.byType(TransitRoutesSheet), findsNothing);
    expect(find.byType(TransitSummaryCard), findsOneWidget);
    expect(previewed(tester).fare, 1500);
  });

  testWidgets('조회가 실패하면 앞 수단 경로를 그대로 둔다', (WidgetTester tester) async {
    await tapTransit(
      tester,
      const TransitRoutes.failure(TransitRoutesStatus.noRoute),
    );

    expect(find.byType(TransitRoutesSheet), findsNothing);
    expect(find.byType(TransitSummaryCard), findsNothing);
    // 지우고 조회했으면 여기가 빈 화면이다. 새 경로가 없을 때 남길 것은 앞 경로다.
    expect(find.byType(EtaCard), findsOneWidget);
  });

  // 후보 0개는 여기까지 오지 않는다 — 두 저장소 모두 빈 목록을 `noRoute`로
  // 바꿔 답한다(`kakao_transit_repository.dart`·`tmap_transit_repository.dart`).
  // 억지로 만들면 미리보기가 아니라 후보 시트가 먼저 터진다(탭이 2개 미만).

  testWidgets('첫 후보에 좌표가 없으면 미리 그리지 않는다', (WidgetTester tester) async {
    await tapTransit(tester, TransitRoutes.ok([_pointlessItinerary()]));

    // 목록은 뜬다 — 그릴 선이 없다는 것과 후보가 없다는 것은 다르다.
    expect(find.byType(TransitRoutesSheet), findsOneWidget);
    expect(
      find.byType(TransitSummaryCard),
      findsNothing,
      reason: '빈 선을 그리면 앞 경로만 지워지고 지도는 빈 화면이 된다',
    );
  });
}
