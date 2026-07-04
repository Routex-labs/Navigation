import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:navigation_client/app.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/routing/app_routes.dart';
import 'package:navigation_client/screens/debug/api_health_check_screen.dart';
import 'package:navigation_client/screens/destination/destination_screen.dart';
import 'package:navigation_client/screens/indoor_map/indoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/route_guide/route_guide_screen.dart';

final _fakePosition = Position(
  latitude: 37.5665,
  longitude: 126.9780,
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
  longitude: 126.9780,
  timestamp: DateTime(2024, 1, 1),
  accuracy: 100,
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
    getCurrentPosition = () async => _fakePosition;
  });

  tearDown(() {
    requestStartupPermissions = defaultRequestStartupPermissions;
    getCurrentPosition = defaultGetCurrentPosition;
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
    getCurrentPosition = () async => _fakeLowAccuracyPosition;

    await tester.pumpWidget(const MaterialApp(home: OutdoorMapScreen()));
    await tester.pump();

    expect(find.text('GPS 신호 약함'), findsOneWidget);
  });

  testWidgets('outdoor map falls back to a default location on failure', (
    WidgetTester tester,
  ) async {
    getCurrentPosition = () async => throw Exception('위치를 가져올 수 없음');

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

  testWidgets('indoor map renders the first floor plan with its POIs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: IndoorMapScreen()));
    await tester.pumpAndSettle();

    expect(find.text('데모 건물 · 1층'), findsOneWidget);
    expect(find.text('강의실 101'), findsOneWidget);
    expect(find.byIcon(Icons.layers), findsOneWidget);
  });

  testWidgets('indoor map switches floor plan via the floor switcher', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: IndoorMapScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.layers));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2층').last);
    await tester.pumpAndSettle();

    expect(find.text('데모 건물 · 2층'), findsOneWidget);
    expect(find.text('강의실 201'), findsOneWidget);
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
}
