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

/// **실내→실외→실내 한 주행이 JSON 하나로 남는다(디버그 모드).**
///
/// 실측 시나리오: B2 매장에서 출발해 에스컬레이터로 올라와 문 밖으로 나갔다가
/// 다시 들어온다. 15~20분짜리 한 번의 주행이라 파일도 하나여야 하는데, 예전에는
/// GPS 이탈이 PDR 세션을 끄고([_dropIndoorPosition]) 재진입 뒤 새 길찾기가
/// 레코더를 통째로 갈아 끼워([_beginRouteRecordingSession]) 나갈 때 걸은 구간이
/// 사라졌다.
///
/// 가르는 것은 **레코더 인스턴스가 같은가**다. 경계 문자열만 보면 새 레코더가
/// 우연히 같은 값을 갖는 경우를 못 잡는다.
///
/// 일반 사용자(디버그 꺼짐)에게는 예전 동작 그대로여야 하므로 그쪽도 함께 건다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final testBuildingRepository = MockBuildingRepository();

  Position at(double longitude) => Position(
    latitude: 37.5665,
    longitude: longitude,
    timestamp: DateTime(2024, 1, 1),
    accuracy: 10,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  // 건물 외곽선 안쪽 / 약 185 m 밖. reentry_floor_reset_test와 같은 좌표다.
  Position atEntrance() => at(126.9779);
  Position farAway() => at(126.9800);

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
    buildingRepository = testBuildingRepository;
    destinationRepository = MockDestinationRepository(testBuildingRepository);
    requestStartupPermissions = () async => {};
    await testBuildingRepository.getAllBuildings();
  });

  tearDown(() async {
    await debugModeController.setEnabled(false);
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  /// 밖 → 안 순서로 좌표를 흘려 자동 진입시키고, 진단 세션을 연다.
  Future<(StreamController<Position>, OutdoorMapBodyState)> walkInAndRecord(
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
    await dismissEntryFloorPrompt(tester);
    await drain(tester);
    expect(
      find.byType(FloorSelector),
      findsOneWidget,
      reason: '테스트 전제(GPS 자동 진입)가 성립하지 않았다',
    );
    final state = tester.state<OutdoorMapBodyState>(
      find.byType(OutdoorMapBody),
    );
    // ignore: invalid_use_of_visible_for_testing_member
    state.beginRouteRecordingSessionForTest();
    return (positions, state);
  }

  testWidgets('디버그 모드: 나갔다 들어와도 같은 레코더가 이어진다', (tester) async {
    await debugModeController.setEnabled(true);
    final (positions, state) = await walkInAndRecord(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    final opened = state.debugRecorderForTest;
    expect(opened, isNotNull, reason: '테스트 전제(진단 세션 열림)가 성립하지 않았다');

    positions.add(farAway());
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);

    // ignore: invalid_use_of_visible_for_testing_member
    expect(identical(state.debugRecorderForTest, opened), isTrue);
    expect(opened!.spansBuildingExit, isTrue);

    positions.add(atEntrance());
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    await dismissEntryFloorPrompt(tester);
    await drain(tester);

    // 재진입 뒤 새 길찾기를 시작해도 갈아 끼우지 않는다 — 여기가 예전에 나갈 때
    // 걸은 구간을 통째로 잃던 자리다.
    // ignore: invalid_use_of_visible_for_testing_member
    state.beginRouteRecordingSessionForTest();
    // ignore: invalid_use_of_visible_for_testing_member
    expect(identical(state.debugRecorderForTest, opened), isTrue);

    final boundaries =
        (opened.buildJson(
                  buildingId: 'b',
                  selectedFloor: state.currentFloor,
                  mapCalibrationVersion: 'v1',
                  graph: null,
                  device: const {},
                )['session_boundaries']!
                as List<Object?>)
            .cast<Map<String, Object?>>()
            .map((b) => b['boundary'])
            .toList();
    expect(boundaries, contains('leftBuilding'));
    expect(boundaries, contains('reEntered'));
    expect(boundaries.last, 'routeStartedAfterReEntry');
  });

  testWidgets('디버그가 꺼져 있으면 예전대로 새 세션으로 갈아 끼운다', (tester) async {
    final (positions, state) = await walkInAndRecord(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    final opened = state.debugRecorderForTest;
    expect(opened, isNotNull, reason: '테스트 전제(진단 세션 열림)가 성립하지 않았다');

    positions.add(farAway());
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(opened!.spansBuildingExit, isFalse);

    positions.add(atEntrance());
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    await dismissEntryFloorPrompt(tester);
    await drain(tester);

    // ignore: invalid_use_of_visible_for_testing_member
    state.beginRouteRecordingSessionForTest();
    // ignore: invalid_use_of_visible_for_testing_member
    expect(identical(state.debugRecorderForTest, opened), isFalse);
  });
}
