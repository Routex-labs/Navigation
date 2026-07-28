import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/models/building.dart';
import 'package:navigation_client/models/building_graph.dart';
import 'package:navigation_client/models/indoor_route.dart';
import 'package:navigation_client/repositories/building_repository.dart';
import 'package:navigation_client/repositories/destination_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/widgets/floor_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "밖으로 나갔다"를 센서로 알아채는 흐름에 대한 회귀 테스트.
///
/// 실내에서는 GPS를 끄는 것이 원칙이라, 사용자가 아무 조작 없이 걸어 나가면
/// 실내 도면이 켜진 채로 남았다. 지금은 **PDR이 계기를 만들고 판단은 GPS가
/// 한다** — PDR 위치가 입구 앞으로 오면 GPS를 잠깐 켜고, 거기서 신뢰할 수 있는
/// 좌표가 잡히면 밖으로 나온 것으로 보고 도면을 접는다.
///
/// 구독이 실제로 붙고 끊기는지는 broadcast 스트림의 `hasListener`로 본다.
/// 실내 여부는 층 선택기([FloorSelector]) 노출로 판정한다 — 실내 오버레이가
/// 켜졌을 때만 뜨는 위젯이다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  const metersPerDegreeLat = 111320.0;
  const metersPerDegreeLng = 88243.0;
  const originLat = 37.5663;
  const originLng = 126.9777;
  const entrance = LatLng(37.5665, 126.9779);

  Map<String, dynamic> node(String id, double xM, double yM) => {
        'id': id,
        'type': 'corridor',
        'x_m': xM,
        'y_m': yM,
        'lat': originLat + yM / metersPerDegreeLat,
        'lng': originLng + xM / metersPerDegreeLng,
      };

  // 입구는 층 로컬로 약 (17.6, 22.3)이라 n-a 바로 옆이다. 자동 앵커가 여기에
  // 찍히므로 PDR 위치도 입구 앞이 되고, 그래서 이탈 감시가 켜진다.
  final graphJson = <String, dynamic>{
    'nodes': [node('n-a', 18, 22), node('n-b', 48, 22), node('n-c', 18, 52)],
    'edges': [
      {
        'id': 'e-ab',
        'from': 'n-a',
        'to': 'n-b',
        'length_m': 30.0,
        'bidirectional': true,
        'geometry_local_m': <Map<String, dynamic>>[],
      },
      {
        'id': 'e-ac',
        'from': 'n-a',
        'to': 'n-c',
        'length_m': 30.0,
        'bidirectional': true,
        'geometry_local_m': <Map<String, dynamic>>[],
      },
    ],
  };

  Position fix(LatLng point, double accuracy) => Position(
        latitude: point.latitude,
        longitude: point.longitude,
        timestamp: DateTime(2024, 1, 1),
        accuracy: accuracy,
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

  const commandChannel = MethodChannel('navigation_client/pdr_motion_cmd');
  const eventChannel = EventChannel('navigation_client/pdr_motion');
  TestDefaultBinaryMessenger messenger() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalBuildingRepository = buildingRepository;
    originalDestinationRepository = destinationRepository;
    final repository = _GraphBuildingRepository(graphJson);
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    requestStartupPermissions = () async => {};
    messenger().setMockMethodCallHandler(commandChannel, (call) async => 1);
    messenger().setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (arguments, sink) {}),
    );
  });

  tearDown(() async {
    await indoorNavigationDriver.stopGuidance();
    messenger().setMockMethodCallHandler(commandChannel, null);
    messenger().setMockStreamHandler(eventChannel, null);
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  /// 자동 진입 → 입구 기준 자동 앵커까지 끌고 간다. 앵커가 입구에 찍혀야 PDR
  /// 위치도 입구 앞이 되어 이탈 감시가 켜진다.
  Future<void> enterIndoorViaEntrance(
    WidgetTester tester,
    StreamController<Position> positions,
  ) async {
    watchPosition = () => positions.stream;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OutdoorMapBody())),
    );
    await drain(tester);
    positions.add(fix(entrance, 10));
    await tester.pump(const Duration(milliseconds: 50));
    positions.add(fix(entrance, 60));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(
      find.byType(FloorSelector),
      findsOneWidget,
      reason: '테스트 전제(자동 실내 진입)가 성립하지 않았다',
    );
    // 센서 준비 대기가 끝나야 앵커가 확정되고, 그 확정이 이탈 감시를 켠다.
    await tester.pump(const Duration(seconds: 3));
    await drain(tester);
  }

  testWidgets('입구 앞에서 신뢰 좌표가 잡히면 실내 도면을 접는다', (
    WidgetTester tester,
  ) async {
    // 실내로 들어가면 구독이 끊기고 이탈 감시가 다시 붙으므로 broadcast여야 한다.
    final positions = StreamController<Position>.broadcast();
    await enterIndoorViaEntrance(tester, positions);

    // 앵커가 입구에 찍혔으므로 PDR 위치도 입구 앞이다 → GPS가 다시 붙어 있어야
    // 한다. 실내 진입 순간에는 분명히 끊겼던 구독이다.
    expect(
      positions.hasListener,
      isTrue,
      reason: 'PDR이 입구 앞이라고 했으면 확인용 GPS 구독이 붙어야 한다',
    );

    // 신호가 나쁜 동안에는 아무 일도 없다 — 실내에서 흔히 나오는 값이라,
    // 이걸로 나갔다고 보면 안에 있는 사용자의 도면이 제멋대로 닫힌다.
    positions.add(fix(entrance, 45));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(find.byType(FloorSelector), findsOneWidget);

    // 신뢰할 수 있는 좌표가 입구 앞에서 잡히면 그때 나온 것으로 본다.
    positions.add(fix(entrance, 8));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(find.byType(FloorSelector), findsNothing);
  });

  testWidgets('실내에서 켠 GPS는 이탈 확인에만 쓰고 화면에는 쓰지 않는다', (
    WidgetTester tester,
  ) async {
    // 이 구독으로 들어온 위치가 마커·경로 쪽으로 새면, 실내 도면 위에 건물 밖
    // GPS 점이 찍히던 예전 문제가 그대로 돌아온다. MapLibre 레이어는 위젯
    // 트리에 없으므로 'GPS 신호 약함' 배지로 대신 본다 — 배지는 GPS 기반
    // 표시가 살아 있을 때만 뜬다.
    final positions = StreamController<Position>.broadcast();
    await enterIndoorViaEntrance(tester, positions);
    expect(positions.hasListener, isTrue);

    positions.add(fix(entrance, 45));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);

    expect(find.byType(FloorSelector), findsOneWidget);
    expect(find.text('GPS 신호 약함'), findsNothing);
  });
}

class _GraphBuildingRepository implements BuildingRepository {
  _GraphBuildingRepository(this.graphJson);

  final Map<String, dynamic> graphJson;

  static const _building = Building(
    id: 'thehyundai-seoul',
    name: '데모 건물',
    floors: ['1F'],
    defaultFloor: '1F',
    entrance: LatLng(37.5665, 126.9779),
    footprintWgs84: [
      LatLng(37.5663, 126.9777),
      LatLng(37.5667, 126.9777),
      LatLng(37.5667, 126.9783),
      LatLng(37.5663, 126.9783),
    ],
  );

  @override
  Future<List<Building>> getAllBuildings() async => const [_building];

  @override
  Future<Building?> getBuilding(String buildingId) async =>
      buildingId == _building.id ? _building : null;

  @override
  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  ) async {
    if (buildingId != _building.id || floor != '1F') return null;
    return {
      'type': 'FeatureCollection',
      'features': <Map<String, dynamic>>[],
      'navigation_graph': graphJson,
    };
  }

  @override
  Future<IndoorRoute?> getShortestRoute(
    String buildingId,
    String floor,
    String startNodeId,
    String endNodeId,
  ) async =>
      null;

  @override
  Future<BuildingGraph?> getBuildingGraph(
    String buildingId, {
    String vertical = 'auto',
  }) async =>
      null;
}
