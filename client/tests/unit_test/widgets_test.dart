import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:navigation_client/widgets/location_marker.dart';
import 'package:navigation_client/widgets/rag_chat_panel.dart';
import 'package:navigation_client/widgets/route_polyline.dart';
import 'package:navigation_client/widgets/status_badge.dart';
import 'package:navigation_client/widgets/uncertainty_circle.dart';

void main() {
  testWidgets('LocationMarker uses the outdoor mode color by default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LocationMarker(mode: LocationMode.outdoor),
      ),
    );

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.navigation);
    expect(icon.color, Colors.blue);
  });

  testWidgets('LocationMarker colorOverride wins over the mode color', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LocationMarker(
          mode: LocationMode.outdoor,
          colorOverride: Colors.amber,
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, Colors.amber);
  });

  testWidgets('UncertaintyCircle renders with the requested diameter', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: UncertaintyCircle(diameter: 40, color: Colors.purple),
      ),
    );

    final box = tester.widget<SizedBox>(find.byType(SizedBox));
    expect(box.width, 40);
    expect(box.height, 40);
  });

  testWidgets('StatusBadge shows the given label', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StatusBadge(label: 'GPS 신호 약함'),
      ),
    );

    expect(find.text('GPS 신호 약함'), findsOneWidget);
  });

  testWidgets('EtaCard shows the distance and minutes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: EtaCard(distanceMeters: 150, minutes: 2),
      ),
    );

    expect(find.text('목적지까지 약 2분 / 150m'), findsOneWidget);
  });

  testWidgets('RagChatPanel shows the hardcoded sample exchanges', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RagChatPanel())),
    );

    expect(find.text('건물 정보 Q&A'), findsOneWidget);
    expect(find.textContaining('화장실'), findsWidgets);
  });

  test('buildRoutePolyline connects the given points', () {
    const points = [LatLng(37.5665, 126.9780), LatLng(37.5670, 126.9790)];

    final polyline = buildRoutePolyline(points);

    expect(polyline.points, points);
    expect(polyline.color, const Color(0xFF1A73E8));
  });
}
