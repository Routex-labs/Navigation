import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/state/recent_route_points_controller.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 뒤로가기가 열려 있는 것을 한 겹씩 벗기는지에 대한 회귀 테스트.
///
/// 경로가 그려진 채 뒤로가기를 누르면 루트 라우트가 pop돼 앱이 통째로 꺼졌다.
/// 하네스(`fix()`·`drain()`·저장소 교체)는 `route_mode_test.dart`와 같다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;
  late RecentRoutePointsController originalRecents;

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
    recentRoutePointsController = RecentRoutePointsController();
    await recentRoutePointsController.ready;
    requestStartupPermissions = () async => {};
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    recentRoutePointsController = originalRecents;
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
}
