import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/repositories/routing/transit_repository.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/transit_routes_sheet.dart';
import 'package:navigation_client/widgets/transit_itinerary_card.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/state/recent_route_points_controller.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 뒤로가기가 열려 있는 것을 한 겹씩 벗기는지에 대한 회귀 테스트.
///
/// 경로가 그려진 채 뒤로가기를 누르면 루트 라우트가 pop돼 앱이 통째로 꺼졌다.
/// 하네스(`fix()`·`drain()`·저장소 교체)는 `route_mode_test.dart`와 같다.
/// 목록이 뜨기만 하면 되므로 조회는 늘 같은 후보 둘을 돌려준다.
class _FakeTransitRepository implements TransitRepository {
  @override
  bool get isAvailable => true;

  @override
  Future<TransitRoutes> getTransitRoutes({
    required LatLng origin,
    required LatLng destination,
    int count = 0,
  }) async => TransitRoutes.ok([_itinerary(1200), _itinerary(1800)]);
}

/// 첫·마지막 구간을 **도보로** 둔다. 그래야 앞뒤 도보를 채우는 보행자 조회가
/// 아예 안 나가, 이 테스트가 네트워크에 손대지 않는다.
TransitItinerary _itinerary(int seconds) => TransitItinerary(
  totalTimeSeconds: seconds,
  totalWalkTimeSeconds: 300,
  totalDistanceMeters: 3000,
  transferCount: 0,
  fare: 1500,
  legs: [
    // 첫 점이 아래 GPS 좌표다 — 안내 시작이 "경로 근처에 있는지"를 본다.
    TransitLeg(
      mode: TransitMode.walk,
      sectionTimeSeconds: 300,
      distanceMeters: 200,
      points: const [LatLng(37.5665, 126.9800), LatLng(37.5670, 126.9805)],
    ),
    TransitLeg(
      mode: TransitMode.bus,
      sectionTimeSeconds: seconds - 600,
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

void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;
  late RecentRoutePointsController originalRecents;
  late TransitRepository originalTransitRepository;

  final repository = MockBuildingRepository();

  // 건물 밖 좌표(외곽선에서 약 185 m 동쪽). 건물 안이면 GPS가 실내 진입을
  // 발동시켜 야외 흐름이 아니라 실내 안내로 갈라진다.
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
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    originalTransitRepository = transitRepository;
    transitRepository = _FakeTransitRepository();
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

  /// 지도만 떠 있는 첫 화면을 만든다.
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

  /// 길찾기 바로 들어가 강의실까지 도보 경로를 그린다.
  Future<void> planWalkRoute(WidgetTester tester) async {
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    await tester.enterText(destinationField(), '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
  }

  testWidgets('경로가 그려져 있으면 뒤로가기가 앱을 끄지 않고 경로만 지운다', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    await tester.enterText(destinationField(), '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    expect(find.byType(EtaCard), findsOneWidget);

    await tester.binding.handlePopRoute();
    await drain(tester);

    // 화면이 살아 있고(앱이 안 꺼졌고) 경로만 벗겨졌다 — X를 누른 것과 같다.
    expect(find.byType(MapShellScreen), findsOneWidget);
    expect(find.byType(EtaCard), findsNothing);
    expect(find.byKey(const Key('route-draft-origin')), findsNothing);
    expect(find.byTooltip('길찾기'), findsOneWidget);
  });

  testWidgets('안내 중이면 뒤로가기가 안내만 끄고 경로는 남긴다', (WidgetTester tester) async {
    await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    await tester.enterText(destinationField(), '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    await tester.tap(find.text('안내 시작'));
    await drain(tester);
    expect(
      find.text('안내 종료'),
      findsOneWidget,
      reason: '테스트 전제(안내가 시작됨)가 성립하지 않았다',
    );

    await tester.binding.handlePopRoute();
    await drain(tester);

    // 벗겨진 것은 안내 한 겹뿐이다 — 경로도 길찾기 바도 그대로 있어야
    // 다른 후보를 다시 고를 수 있다.
    expect(find.byType(EtaCard), findsOneWidget);
    expect(find.text('안내 시작'), findsOneWidget);
    expect(
      find.byKey(const Key('route-planner')),
      findsOneWidget,
      reason: '길찾기 바까지 사라지면 다른 후보를 고를 문이 닫힌다',
    );
  });

  testWidgets('대중교통 안내 중 뒤로가기는 후보 목록을 다시 연다', (WidgetTester tester) async {
    await pumpShell(tester);
    await planWalkRoute(tester);
    await tester.tap(find.text('대중교통'));
    await drain(tester);
    expect(
      find.byType(TransitItineraryCard),
      findsWidgets,
      reason: '테스트 전제(후보 목록이 뜸)가 성립하지 않았다',
    );

    await tester.tap(find.byType(TransitItineraryCard).first);
    await drain(tester);
    expect(find.byType(TransitRoutesSheet), findsNothing);
    await tester.tap(find.text('안내 시작'));
    await drain(tester);
    expect(
      find.text('안내 종료'),
      findsOneWidget,
      reason: '테스트 전제(안내가 시작됨)가 성립하지 않았다',
    );

    await tester.binding.handlePopRoute();
    await drain(tester);

    // 대중교통에서 안내의 **바로 이전 상태가 목록**이다. 계획 카드는 사용자가
    // 지나온 적 없는 화면이라 거기 떨어뜨리면 한 겹을 잘못 벗긴 것이 된다.
    expect(find.byType(TransitRoutesSheet), findsOneWidget);
  });

  testWidgets('길찾기를 끝내면 보관한 대중교통 조회도 함께 비워진다', (WidgetTester tester) async {
    await pumpShell(tester);
    await planWalkRoute(tester);
    await tester.tap(find.text('대중교통'));
    await drain(tester);
    await tester.tap(find.byType(TransitItineraryCard).first);
    await drain(tester);

    // 경로째로 지운다(뒤로가기 두 번째 겹 = 상단 X와 같은 정리).
    await tester.binding.handlePopRoute();
    await drain(tester);
    expect(
      find.byTooltip('길찾기'),
      findsOneWidget,
      reason: '테스트 전제(경로가 지워짐)가 성립하지 않았다',
    );

    // 이번엔 도보로 다시 안내를 건다. 옛 조회가 남아 있으면 여기서
    // **예전 목적지의 후보 목록**이 튀어나온다.
    await planWalkRoute(tester);
    await tester.tap(find.text('안내 시작'));
    await drain(tester);
    await tester.binding.handlePopRoute();
    await drain(tester);

    expect(find.byType(TransitRoutesSheet), findsNothing);
  });
}
