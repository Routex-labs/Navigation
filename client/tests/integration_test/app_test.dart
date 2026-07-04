import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:navigation_client/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app launches and reaches a settled state', (
    WidgetTester tester,
  ) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 10));

    expect(find.text(app.apiBaseUrl), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });
}
