import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/repositories/building_repository.dart';
import 'package:navigation_client/repositories/destination_repository.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:navigation_client/widgets/place_detail_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **검색은 길을 찾지 않는다**는 규칙에 대한 회귀 테스트.
///
/// 예전에는 검색 결과의 건물 줄을 누르는 순간 그 입구까지 경로를 그렸다. 검색은
/// "저기가 어디지"를 묻는 조작이지 "저기로 데려다 줘"가 아닌데, 위치만 확인하려던
/// 사용자에게 안내가 시작되고 그만두려면 안내 종료를 눌러야 했다.
///
/// 지금은 고른 장소로 지도를 옮기고, 보여 줄 정보가 있으면 그것까지 띄운다.
/// 길찾기는 상단 길찾기 버튼에서 시작한다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

  // 건물 밖 좌표. 건물 안이면 GPS가 실내 진입을 발동시켜 흐름이 갈라진다.
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

  Future<void> search(WidgetTester tester, String query) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    await tester.pumpWidget(const MaterialApp(home: MapShellScreen()));
    await drain(tester);
    positions.add(fix());
    await drain(tester);

    await tester.tap(find.byType(TextField).first);
    await drain(tester);
    await tester.enterText(find.byType(TextField).first, query);
    await drain(tester);
  }

  testWidgets('건물을 고르면 길을 찾지 않고 그 건물 이름만 띄운다', (
    WidgetTester tester,
  ) async {
    await search(tester, '데모');
    await tester.tap(find.text('데모 건물').first);
    await drain(tester);

    // 경로도, 길찾기 바도 없다.
    expect(find.byType(EtaCard), findsNothing);
    expect(find.byKey(const Key('route-draft-destination')), findsNothing);
    // 대신 무엇으로 옮겨 왔는지는 화면에 남는다 — 지도만 움직이면 사용자는
    // 자기가 누른 것이 반영됐는지 모른다.
    expect(find.text('데모 건물'), findsOneWidget);
  });

  testWidgets('매장을 고르면 그 매장 정보 시트가 올라온다', (WidgetTester tester) async {
    await search(tester, '강의실');
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);

    expect(find.byType(PlaceDetailSheet), findsOneWidget);
    // 시트가 떴을 뿐 안내는 시작되지 않는다. 길찾기는 시트의 "도착"이나 상단
    // 길찾기 버튼에서 시작한다.
    expect(find.byType(EtaCard), findsNothing);
  });
}
