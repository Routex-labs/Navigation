import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/status_badge.dart';

void main() {
  testWidgets('StatusBadge shows the given label', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: StatusBadge(label: 'GPS 신호 약함')),
    );

    expect(find.text('GPS 신호 약함'), findsOneWidget);
  });
}
