import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/floor_selector.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/entry_floor_prompt_helper.dart';

/// **재진입은 지난 층이 아니라 기본 층에서 시작한다.**
///
/// 실측 증상: B2에서 안내를 받다가 건물 밖으로 나가 지상 1F 입구로 다시 들어왔는데
/// 활성 층이 B3 그대로였다. 그 층을 기준으로 기압 판정이 다시 시작돼 B3→B4 층 전환
/// 배너까지 떴다. 안내 중에는 층을 묻지 않으므로([_askEntryFloorThenTrack]의
/// `_guidancePlanned` 갈래) 틀린 층을 바로잡을 기회도 없었다.
///
/// 여기 목업 건물은 1F·2F뿐이라 지하 대신 2F로 같은 흐름을 시험한다 — 가르는 것은
/// 층 이름이 아니라 "나갔다 들어오면 되돌아가는가"다.
///
/// 지금 층은 층 선택기([FloorSelector.selectedFloor])로 읽는다. 화면이 실제로
/// 그리는 값이라, 내부 상태만 바뀌고 도면은 그대로인 반쪽 성공을 잡아낸다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final testBuildingRepository = MockBuildingRepository();

  // 건물 외곽선 안쪽. 진입 근거가 되는 좌표다.
  Position atEntrance() => Position(
    latitude: 37.5665,
    longitude: 126.9779,
    timestamp: DateTime(2024, 1, 1),
    accuracy: 10,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  // 외곽선에서 약 185m 밖 + 신호 양호. 첫 좌표는 반드시 밖이어야 한다 — 외곽선은
  // asset 로드 뒤에야 채워지므로, 안쪽 좌표를 먼저 흘리면 판정할 도형이 없다.
  Position farAway() => Position(
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

  // 지도 오버레이의 반복 애니메이션·타이머 때문에 pumpAndSettle이 정착하지
  // 않으므로, 정해진 횟수만큼 프레임을 진행해 큐를 비운다.
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  String selectedFloor(WidgetTester tester) =>
      tester.widget<FloorSelector>(find.byType(FloorSelector)).selectedFloor;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalBuildingRepository = buildingRepository;
    originalDestinationRepository = destinationRepository;
    buildingRepository = testBuildingRepository;
    destinationRepository = MockDestinationRepository(testBuildingRepository);
    requestStartupPermissions = () async => {};
    // 건물 asset을 미리 읽어 캐시를 채운다. 위젯 테스트의 가짜 시계는 실제 파일
    // I/O를 기다려 주지 않아, 캐시가 비면 외곽선이 도착하지 않는다.
    await testBuildingRepository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  /// 밖 → 안 순서로 좌표를 흘려 자동 진입시키고, 층 질문에 2F로 답한다.
  Future<StreamController<Position>> walkInAndPickSecondFloor(
    WidgetTester tester,
  ) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);
    positions.add(farAway());
    await tester.pump(const Duration(milliseconds: 50));
    positions.add(atEntrance());
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    await answerEntryFloorPrompt(tester, '2F');
    await drain(tester);
    expect(selectedFloor(tester), '2F', reason: '테스트 전제(층 선택)가 성립하지 않았다');
    return positions;
  }

  testWidgets('밖으로 나갔다 다시 들어오면 지난 층이 아니라 기본 층에서 시작한다', (tester) async {
    final positions = await walkInAndPickSecondFloor(tester);

    positions.add(farAway());
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(
      find.byType(FloorSelector),
      findsNothing,
      reason: '테스트 전제(GPS 이탈 판정)가 성립하지 않았다',
    );

    positions.add(atEntrance());
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);

    expect(
      selectedFloor(tester),
      '1F',
      reason: '지난 세션의 층에서 다시 시작하면 기압 판정의 기준 층이 통째로 어긋난다',
    );
  });

  testWidgets('도면만 접었다 다시 펴면 층이 유지된다', (tester) async {
    // 나간 것과 접은 것은 다르다. 접은 사용자는 같은 자리에 그대로 서 있으므로,
    // 여기서까지 되돌리면 2F에 선 사람의 도면이 1F로 갈린다.
    await walkInAndPickSecondFloor(tester);

    final state = tester.state<OutdoorMapBodyState>(find.byType(OutdoorMapBody));
    await state.returnToOutdoorView();
    await drain(tester);
    expect(state.currentFloor, '2F');

    // ignore: invalid_use_of_visible_for_testing_member
    state.enterIndoorForTest();
    await drain(tester);
    expect(selectedFloor(tester), '2F');
  });
}
