import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "지도에서 선택"을 누른 뒤 화면(MapShellScreen)이 어떤 상태로 넘어가는지에
/// 대한 회귀 테스트.
///
/// 가장 깨지기 쉬운 지점은 **목록이 닫힌 뒤 아무 표시도 남지 않는 것**이다.
/// 그러면 사용자는 방금 누른 버튼이 먹지 않은 것으로 보고, 다음에 매장을
/// 눌렀을 때 매장 정보 시트 대신 경로가 그려지는 이유도 알 수 없다.
///
/// 이 줄은 **도면을 보고 있을 때만** 뜬다. 야외 지도에서 누르면 이름 없는 좌표
/// 하나가 잡히는데, 매장 이름으로 고르는 줄과 나란히 두면 같은 무게로 읽힌다.
/// 그래서 아래 흐름은 전부 도면을 펴 놓은 상태에서 확인한다 — 예전에는 하단
/// 세그먼트의 '실내' 탭으로 그 상태를 만들었지만, 지도가 하나로 합쳐지면서
/// 지금은 건물 안에서 GPS가 잡히는 것이 그 상태로 들어가는 길이다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

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

  /// 데모 건물 외곽선(위도 37.5663~37.5667) 한가운데 + 신뢰할 수 있는 신호.
  /// 이 좌표 한 건이면 자동 실내 진입이 발동한다(judgeBuildingFromGps).
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

  /// 도면을 펴 놓은 상태에서 길찾기를 연 뒤 "지도에서 선택"을 누른다.
  Future<void> pickOnMap(WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MapShellScreen()));
    await drain(tester);
    positions.add(insideBuilding());
    await drain(tester);

    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    expect(
      find.text('지도에서 선택'),
      findsOneWidget,
      reason: '테스트 전제(도면을 보는 중 길찾기 열림)가 성립하지 않았다',
    );

    await tester.tap(find.text('지도에서 선택'));
    await drain(tester);
  }

  testWidgets('야외 지도에서는 "지도에서 선택"을 주지 않는다', (WidgetTester tester) async {
    // 야외에서 지도를 누르면 이름 없는 좌표가 잡힌다. 매장 이름으로 고르는 줄과
    // 나란히 두면 같은 무게로 읽히는데, 실제로 쓸 일은 GPS가 안 잡히는 예외뿐이라
    // 그 경우는 하단 바의 "위치 지정"이 따로 맡는다.
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MapShellScreen()));
    await drain(tester);

    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);

    expect(find.byKey(const Key('route-field-pick-on-map')), findsNothing);
    // 목록 자체는 떠 있어야 한다 — 줄 하나만 빠진 것이다.
    expect(find.byKey(const Key('route-planner')), findsOneWidget);
  });

  testWidgets('지도에서 선택을 누르면 지도 위에 안내가 남는다', (WidgetTester tester) async {
    await pickOnMap(tester);

    // 시트는 닫히고,
    expect(find.text('지도에서 선택'), findsNothing);
    // 지금 무엇을 해야 하는지는 지도 위에 남는다.
    expect(find.textContaining('도착지로 지정할 매장이나 복도를 지도에서 눌러주세요'), findsOneWidget);
    // 출발지가 무엇으로 잡혀 있는지도 함께 보여준다.
    expect(find.textContaining('출발: 현재 위치'), findsOneWidget);
  });

  testWidgets('안내의 X를 누르면 지도에서 고르기를 그만둔다', (WidgetTester tester) async {
    // 빠져나갈 길이 없으면, 마음이 바뀐 사용자는 매장을 눌러 원치 않는 경로를
    // 그리는 것 말고 선택지가 없다.
    await pickOnMap(tester);

    await tester.tap(find.byTooltip('지도에서 선택 취소'));
    await drain(tester);

    expect(find.textContaining('도착지로 지정할 매장이나 복도를 지도에서 눌러주세요'), findsNothing);
  });

  testWidgets('다시 칸을 눌러 치기 시작하면 지도에서 고르기가 풀린다', (
    WidgetTester tester,
  ) async {
    // 안내만 남으면, 이름으로 목적지를 정한 뒤에도 다음 매장 탭이 도착지로
    // 먹혀 엉뚱한 경로가 그려진다.
    await pickOnMap(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('route-planner')),
        matching: find.text('도착지를 정해 주세요'),
      ),
    );
    await drain(tester);

    expect(find.textContaining('도착지로 지정할 매장이나 복도를 지도에서 눌러주세요'), findsNothing);
  });
}
