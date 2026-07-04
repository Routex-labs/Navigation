import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:navigation_client/main.dart';

void main() {
  testWidgets('shows loading indicator then a status message', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    // Right after start, the health check is in-flight.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(apiBaseUrl), findsOneWidget);

    // The http call will fail immediately in the widget-test environment
    // (no real network), so let it settle and show a status message.
    await tester.pumpAndSettle(const Duration(seconds: 6));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });
}
