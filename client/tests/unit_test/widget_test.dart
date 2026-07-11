import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:navigation_client/app.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/models/poi_search_result.dart';
import 'package:navigation_client/routing/app_routes.dart';
import 'package:navigation_client/screens/arrival/arrival_screen.dart';
import 'package:navigation_client/screens/debug/api_health_check_screen.dart';
import 'package:navigation_client/screens/destination/destination_screen.dart';
import 'package:navigation_client/screens/indoor_map/indoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/route_guide/route_guide_screen.dart';

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
  setUp(() {
    // 실제 permission_handler/geolocator 플러그인 채널이 없는 테스트 환경에서
    // 멈추지 않도록 즉시 완료되는 가짜 함수로 교체한다.
    requestStartupPermissions = () async => {};
    watchPosition = () => Stream.value(_fakePosition);
  });

  tearDown(() {
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  testWidgets('splash screen shows entry points', (WidgetTester tester) async {
    await tester.pumpWidget(const NavigationApp());

    expect(find.text('Navigation'), findsOneWidget);
    expect(find.text('시작하기'), findsOneWidget);
  });

  testWidgets('splash screen requests permissions then stops loading', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NavigationApp());

    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('splash "시작하기" navigates to outdoor map', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NavigationApp());

    await tester.tap(find.text('시작하기'));
    // 지도 타일은 네트워크 이미지라 pumpAndSettle을 쓰면 무한정 기다릴 수 있으니
    // 라우트 전환과 위치 조회가 끝날 만큼만 프레임을 진행한다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('야외 지도 (GPS 모드)'), findsOneWidget);
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
    await tester.pumpWidget(const MaterialApp(home: OutdoorMapScreen()));

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

    await tester.pumpWidget(const MaterialApp(home: OutdoorMapScreen()));
    await tester.pump();

    expect(find.text('GPS 신호 약함'), findsOneWidget);
  });

  testWidgets('outdoor map shows a route and ETA card to the entrance', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: OutdoorMapScreen()));
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.place), findsOneWidget);
    expect(find.textContaining('목적지까지 약'), findsOneWidget);
  });

  testWidgets(
    'outdoor map auto-navigates to indoor map within the entrance radius',
    (WidgetTester tester) async {
      watchPosition = () => Stream.value(_fakePositionAtEntrance);

      await tester.pumpWidget(
        MaterialApp(
          home: const OutdoorMapScreen(),
          routes: {
            AppRoutes.indoorMap: (context) =>
                const Scaffold(body: Text('INDOOR')),
          },
        ),
      );

      await tester.pump();
      await tester.pump();
      expect(find.text('건물 감지 중...'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('INDOOR'), findsOneWidget);
    },
  );

  testWidgets(
    'outdoor map does not auto-navigate near the entrance when GPS signal stays strong',
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

      await tester.pumpWidget(
        MaterialApp(
          home: const OutdoorMapScreen(),
          routes: {
            AppRoutes.indoorMap: (context) =>
                const Scaffold(body: Text('INDOOR')),
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('야외 지도 (GPS 모드)'), findsOneWidget);
      expect(find.text('INDOOR'), findsNothing);
    },
  );

  testWidgets('outdoor map reacts to multiple position stream updates', (
    WidgetTester tester,
  ) async {
    final controller = StreamController<Position>();
    watchPosition = () => controller.stream;

    await tester.pumpWidget(const MaterialApp(home: OutdoorMapScreen()));

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

    await tester.pumpWidget(const MaterialApp(home: OutdoorMapScreen()));
    await tester.pump();

    expect(find.byIcon(Icons.navigation), findsOneWidget);
    expect(find.text('GPS 신호 약함'), findsOneWidget);
  });

  testWidgets('indoor map shows building info loaded from the repository', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: IndoorMapScreen()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.textContaining('데모 건물'), findsOneWidget);
  });

  testWidgets('indoor map renders the floor map image', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: IndoorMapScreen()));
    await tester.pumpAndSettle();

    expect(find.text('데모 건물 · 1F'), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byIcon(Icons.layers), findsOneWidget);
  });

  testWidgets('indoor map switches floor label via the floor switcher', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: IndoorMapScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.layers));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2F').last);
    await tester.pumpAndSettle();

    expect(find.text('데모 건물 · 2F'), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
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

    expect(find.text('찾을 수 없어요. 다시 입력해볼까요?'), findsOneWidget);
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

    expect(find.textContaining('강의실 101'), findsOneWidget);
    expect(find.textContaining('목적지까지 약'), findsOneWidget);
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

    expect(find.text('강의실 101에 도착했습니다!'), findsOneWidget);

    // 자동 종료 타이머가 만료될 때까지 시간을 진행시킨다.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('INDOOR'), findsOneWidget);
  });
}
