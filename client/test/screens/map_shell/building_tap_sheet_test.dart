import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/floor_selector.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 야외 지도에서 건물을 눌렀을 때 **정보 시트가 먼저 뜨는지**에 대한 테스트.
///
/// 예전에는 건물 탭이 곧 실내 진입이었다. 건물을 눌러 본 사용자가 "그 건물이
/// 무엇인지" 대신 도면부터 봤고, 그 건물에 무엇이 있는지 볼 자리가 없었다.
///
/// **진입을 없앤 것이 아니라 옮긴 것이다.** 시트 안의 "실내 지도 보기"가 그
/// 조작을 이어받는다 — 이 짝이 깨지면 매장을 고르지 않고는 도면에 들어갈 길이
/// 사라진다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

  /// 목업 건물 외곽선(위도 37.5663~37.5667, 경도 126.9777~126.9783)의 한가운데.
  const insideBuilding = LatLng(37.5665, 126.9780);

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

  Future<void> tapBuilding(WidgetTester tester) async {
    final state = tester.state<OutdoorMapBodyState>(
      find.byType(OutdoorMapBody),
    );
    // 화면 좌표를 함께 준다. 기본값 (0,0)은 상단 바 아래라
    // [_isTapOnMapOverlay]가 먼저 삼켜, 검증하려는 분기까지 오지 않는다.
    // ignore: invalid_use_of_visible_for_testing_member
    await state.handleMapClickForTest(
      insideBuilding,
      screenPoint: const Offset(200, 400),
    );
    await drain(tester);
  }

  testWidgets('건물을 누르면 도면이 아니라 건물 정보 시트가 먼저 뜬다', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MapShellScreen()));
    await drain(tester);
    expect(
      find.byType(FloorSelector),
      findsNothing,
      reason: '테스트 전제(시작은 야외)가 성립하지 않았다',
    );

    await tapBuilding(tester);

    expect(find.byKey(const ValueKey('building-info-actions')), findsOneWidget);
    expect(
      find.byType(FloorSelector),
      findsNothing,
      reason: '시트를 앞에 세운 뜻이 없어진다 — 도면이 이미 떠 있으면 시트는 그 위 장식일 뿐이다',
    );
  });

  testWidgets('길찾기 버튼은 출발·도착 둘뿐이다', (WidgetTester tester) async {
    // 매장 시트·야외 장소 시트와 같은 규칙이다. 수단은 길찾기에 들어간 뒤
    // 상단 줄에서 고른다.
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MapShellScreen()));
    await drain(tester);
    await tapBuilding(tester);

    expect(find.text('출발'), findsOneWidget);
    expect(find.text('도착'), findsOneWidget);
    expect(find.text('대중교통'), findsNothing);
  });

  testWidgets('"실내 지도 보기"를 누르면 그때 도면으로 들어간다', (WidgetTester tester) async {
    // 건물 탭이 곧 진입이던 조작을 이 줄이 이어받는다. 없으면 매장을 고르지
    // 않고는 도면에 들어갈 길이 사라진다.
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MapShellScreen()));
    await drain(tester);
    await tapBuilding(tester);

    await tester.tap(find.byKey(const ValueKey('building-info-enter-indoor')));
    await drain(tester);

    expect(find.byType(FloorSelector), findsOneWidget);
    expect(
      find.byKey(const ValueKey('building-info-actions')),
      findsNothing,
      reason: '들어갔으면 시트는 닫혀야 한다 — 도면 위에 남으면 볼 것을 가린다',
    );
  });

  testWidgets('매장 목록이 없어도 이름과 길찾기 버튼은 남는다', (WidgetTester tester) async {
    // 목업 자산은 층 도면을 GeoJSON `features`로만 갖고 있어 매장 색인이 비어
    // 있다(`MockBuildingRepository.getStoreIndex`). 목록이 비는 것은 실제로도
    // 있을 수 있는 상태이고, 그때 시트가 통째로 쓸모없어지면 안 된다.
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MapShellScreen()));
    await drain(tester);
    await tapBuilding(tester);

    expect(find.text('이 건물의 매장 정보가 아직 없습니다.'), findsOneWidget);
    expect(find.text('출발'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('building-info-enter-indoor')),
      findsOneWidget,
    );
  });

  testWidgets('실내에서 건물 안쪽을 눌러도 시트를 띄우지 않는다', (WidgetTester tester) async {
    // 도면을 보는 중에 빈 곳을 누른 것이라, 시트를 띄우면 매장을 누르려다
    // 빗나간 손가락마다 시트가 올라온다.
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MapShellScreen()));
    await drain(tester);
    tester
        .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
        // ignore: invalid_use_of_visible_for_testing_member
        .enterIndoorForTest();
    await drain(tester);

    await tapBuilding(tester);

    expect(find.byKey(const ValueKey('building-info-actions')), findsNothing);
    expect(find.byType(FloorSelector), findsOneWidget);
  });
}
