import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:navigation_client/app.dart';
import 'package:navigation_client/core/api_config.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/models/poi_search_result.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';
import 'package:navigation_client/routing/app_routes.dart';
import 'package:navigation_client/screens/arrival/arrival_screen.dart';
import 'package:navigation_client/screens/debug/api_health_check_screen.dart';
import 'package:navigation_client/screens/destination/destination_screen.dart';
import 'package:navigation_client/screens/indoor_map/indoor_map_screen.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/route_guide/route_guide_screen.dart';
import 'package:navigation_client/widgets/floor_plan_view.dart';

// 1x1 흰색 PNG (base64). 배경지도 타일을 흉내내되 실제 네트워크 요청은 하지
// 않는다 - flutter_map 자체 테스트 스위트도 같은 방식을 쓴다.
const _whiteTileBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAQAAAAEAAQMAAABmvDolAAAAAXNSR0IB2cksfwAAAAlwSFlzAAALEwAACxMBAJqcGAAAAANQTFRF////p8QbyAAAAB9JREFUeJztwQENAAAAwqD3T20ON6AAAAAAAAAAAL4NIQAAAfFnIe4AAAAASUVORK5CYII=';
final _whiteTileImage = MemoryImage(base64Decode(_whiteTileBase64));

class _FakeTileProvider extends TileProvider {
  @override
  ImageProvider<Object> getImage(
    TileCoordinates coordinates,
    TileLayer options,
  ) => _whiteTileImage;
}

// 데모 건물 입구(37.5665, 126.9779)에서 약 185m 떨어진 좌표.
// 자동 건물 진입 감지(반경 50m)에 걸리지 않도록 충분히 멀리 둔다.
final _fakePosition = Position(
  latitude: 37.5665,
  longitude: 126.9800,
  timestamp: DateTime(2024, 1, 1),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

final _fakeLowAccuracyPosition = Position(
  latitude: 37.5665,
  longitude: 126.9800,
  timestamp: DateTime(2024, 1, 1),
  accuracy: 100,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

// 데모 건물 입구와 정확히 같은 좌표 + 신호 저하(자동 진입 감지 테스트용).
// accuracy가 저하 기준(15m)을 넘어야 "막 나빠진 신호"로 판정된다.
final _fakePositionAtEntrance = Position(
  latitude: 37.5665,
  longitude: 126.9779,
  timestamp: DateTime(2024, 1, 1),
  accuracy: 25,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  final originalBuildingRepository = buildingRepository;
  final originalDestinationRepository = destinationRepository;
  final testBuildingRepository = MockBuildingRepository();

  setUp(() {
    // 실제 permission_handler/geolocator 플러그인 채널이 없는 테스트 환경에서
    // 멈추지 않도록 즉시 완료되는 가짜 함수로 교체한다.
    requestStartupPermissions = () async => {};
    watchPosition = () => Stream.value(_fakePosition);

    // 네트워크가 없는 테스트 환경에서는 HttpBuildingRepository(운영 기본값)
    // 대신 asset 기반 MockBuildingRepository로 교체해 결정적으로 검증한다.
    // 테스트마다 새로 만들지 않고 파일 전체에서 하나를 공유한다.
    buildingRepository = testBuildingRepository;
    destinationRepository = MockDestinationRepository(buildingRepository);

    // 야외 지도의 배경 타일도 실제 OSM/VWorld 대신 가짜 provider로 교체한다.
    // 실제 네트워크 요청을 남겨두면 그 요청이 이후 테스트까지 이어져
    // pumpAndSettle이 끝없이 걸리는 원인이 된다.
    outdoorTileProvider = () => _FakeTileProvider();
  });

  tearDown(() {
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    outdoorTileProvider = NetworkTileProvider.new;
  });

  testWidgets('app opens directly into the outdoor (home) map shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NavigationApp());
    // 지도 타일은 네트워크 이미지라 pumpAndSettle을 쓰면 무한정 기다릴 수 있으니
    // 위치 조회가 끝날 만큼만 프레임을 진행한다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    // 야외(홈) 모드로 바로 시작했는지는 하단 공용 바의 홈/실내 세그먼트로 확인한다 —
    // 실내 모드였다면 상단 바에 햄버거 버튼이 추가로 보였을 것이다.
    expect(find.text('홈'), findsOneWidget);
    expect(find.text('실내'), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsNothing);
  });

  testWidgets('api health check shows loading then a status message', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ApiHealthCheckScreen()),
    );

    // Right after start, the health check is in-flight.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // The http call will fail immediately in the widget-test environment
    // (no real network), so let it settle and show a status message.
    await tester.pumpAndSettle(const Duration(seconds: 6));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('outdoor map shows a location marker after loading', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: OutdoorMapBody(onEnterBuilding: () {})),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.navigation), findsOneWidget);
    expect(find.text('GPS 신호 약함'), findsNothing);
  });

  testWidgets('outdoor map shows a low-accuracy warning badge', (
    WidgetTester tester,
  ) async {
    watchPosition = () => Stream.value(_fakeLowAccuracyPosition);

    await tester.pumpWidget(
      MaterialApp(home: OutdoorMapBody(onEnterBuilding: () {})),
    );
    await tester.pump();

    expect(find.text('GPS 신호 약함'), findsOneWidget);
  });

  testWidgets('outdoor map shows a route and ETA card to the entrance', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: OutdoorMapBody(onEnterBuilding: () {})),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.place), findsOneWidget);
    expect(find.textContaining('건물 입구까지'), findsOneWidget);
  });

  testWidgets(
    'map shell switches to indoor mode when entrance is detected nearby',
    (WidgetTester tester) async {
      watchPosition = () => Stream.value(_fakePositionAtEntrance);

      await tester.pumpWidget(const MaterialApp(home: MapShellScreen()));

      await tester.pump();
      await tester.pump();
      expect(find.text('건물 감지 중...'), findsOneWidget);

      await tester.pumpAndSettle();
      // 실내 모드로 전환되면 공용 상단바에 건물 선택용 햄버거 버튼이 나타난다.
      expect(find.byIcon(Icons.menu), findsOneWidget);
    },
  );

  testWidgets(
    'map shell does not switch to indoor mode when GPS signal stays strong near the entrance',
    (WidgetTester tester) async {
      // 입구와 같은 좌표지만 신호는 계속 양호함 (건물 앞을 지나가는 상황).
      final passingByPosition = Position(
        latitude: 37.5665,
        longitude: 126.9779,
        timestamp: DateTime(2024, 1, 1),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      watchPosition = () => Stream.value(passingByPosition);

      await tester.pumpWidget(const MaterialApp(home: MapShellScreen()));
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.menu), findsNothing);
    },
  );

  testWidgets('outdoor map reacts to multiple position stream updates', (
    WidgetTester tester,
  ) async {
    final controller = StreamController<Position>();
    watchPosition = () => controller.stream;

    await tester.pumpWidget(
      MaterialApp(home: OutdoorMapBody(onEnterBuilding: () {})),
    );

    controller.add(_fakePosition);
    await tester.pump();
    expect(find.text('GPS 신호 약함'), findsNothing);

    controller.add(_fakeLowAccuracyPosition);
    await tester.pump();
    expect(find.text('GPS 신호 약함'), findsOneWidget);

    await controller.close();
  });

  testWidgets('outdoor map falls back to a default location on failure', (
    WidgetTester tester,
  ) async {
    watchPosition = () => Stream.error(Exception('위치를 가져올 수 없음'));

    await tester.pumpWidget(
      MaterialApp(home: OutdoorMapBody(onEnterBuilding: () {})),
    );
    await tester.pump();

    expect(find.byIcon(Icons.navigation), findsOneWidget);
    expect(find.text('GPS 신호 약함'), findsOneWidget);
  });

  testWidgets('indoor map shows building info loaded from the repository', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: IndoorMapBody(buildingId: demoBuildingId)),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.textContaining('데모 건물'), findsOneWidget);
  });

  testWidgets('indoor map renders the floor plan view', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: IndoorMapBody(buildingId: demoBuildingId)),
    );
    await tester.pumpAndSettle();

    expect(find.text('데모 건물'), findsOneWidget);
    expect(find.textContaining('현재 1F 위치'), findsOneWidget);
    expect(find.byType(FloorPlanView), findsOneWidget);
    expect(find.byIcon(Icons.layers), findsOneWidget);

    // PDR이 아직 없어도, 실내 지도 진입 시 "현재 위치" 아이콘이 뜨도록
    // 층 평면도 근사 위치가 FloorPlanView로 전달돼야 한다.
    final floorPlanView = tester.widget<FloorPlanView>(find.byType(FloorPlanView));
    expect(floorPlanView.currentLocation, isNotNull);
  });

  testWidgets('indoor map switches floor via the floor tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: IndoorMapBody(buildingId: demoBuildingId)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('2F'));
    await tester.pumpAndSettle();

    expect(find.textContaining('현재 2F 위치'), findsOneWidget);
    expect(find.byType(FloorPlanView), findsOneWidget);
  });

  testWidgets('destination screen shows every POI by default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DestinationScreen()));
    await tester.pumpAndSettle();

    expect(find.text('강의실 101'), findsOneWidget);
    expect(find.text('강의실 201'), findsOneWidget);
  });

  testWidgets('destination screen filters as the user types', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DestinationScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '201');
    await tester.pumpAndSettle();

    expect(find.text('강의실 101'), findsNothing);
    expect(find.text('강의실 201'), findsOneWidget);
  });

  testWidgets('destination screen shows an empty state for no matches', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DestinationScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '존재하지않는장소');
    await tester.pumpAndSettle();

    expect(find.text('찾을 수 없어요'), findsOneWidget);
    expect(find.text('다시 입력해볼까요?'), findsOneWidget);
  });

  testWidgets('selecting a destination navigates to the route guide', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/': (context) => const DestinationScreen(),
          AppRoutes.routeGuide: (context) => const RouteGuideScreen(),
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('강의실 101'));
    await tester.pumpAndSettle();

    // 이전 화면(목적지 입력)의 "강의실 101" 목록 항목이 Navigator 스택에
    // 남아있어 textContaining만으로는 새 화면과 구분되지 않는다 - 경로 안내
    // 화면 AppBar에만 있는 정확한 제목으로 확인한다.
    expect(find.text('강의실 101(으)로 안내'), findsOneWidget);
    expect(find.textContaining('목적지까지'), findsWidgets);
  });

  testWidgets('route guide shows the ETA card and building info FAB', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/': (context) => const DestinationScreen(),
          AppRoutes.routeGuide: (context) => const RouteGuideScreen(),
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('강의실 201'));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text('건물 정보 Q&A'), findsOneWidget);
    expect(find.textContaining('화장실'), findsWidgets);
  });

  testWidgets('arrival screen shows a generic message and navigates on tap', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const ArrivalScreen(),
        routes: {
          AppRoutes.indoorMap: (context) => const Scaffold(body: Text('INDOOR')),
        },
      ),
    );

    expect(find.text('도착했습니다!'), findsOneWidget);

    await tester.tap(find.text('새 목적지 탐색'));
    await tester.pumpAndSettle();

    expect(find.text('INDOOR'), findsOneWidget);
  });

  testWidgets('arrival screen shows the destination and auto-dismisses', (
    WidgetTester tester,
  ) async {
    const destination = PoiSearchResult(
      name: '강의실 101',
      floor: '1F',
      point: LatLng(37.5665, 126.9780),
    );

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          AppRoutes.indoorMap: (context) => const Scaffold(body: Text('INDOOR')),
        },
        onGenerateInitialRoutes: (initialRoute) => [
          MaterialPageRoute(
            settings: const RouteSettings(arguments: destination),
            builder: (context) => const ArrivalScreen(),
          ),
        ],
      ),
    );

    expect(find.text('강의실 101에 도착했습니다'), findsOneWidget);

    // 자동 종료 타이머가 만료될 때까지 시간을 진행시킨다.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('INDOOR'), findsOneWidget);
  });
}
