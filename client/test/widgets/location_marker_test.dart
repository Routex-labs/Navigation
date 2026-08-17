import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/location_marker.dart';

void main() {
  testWidgets('LocationMarker uses the outdoor mode color by default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: LocationMarker(mode: LocationMode.outdoor)),
    );

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.navigation);
    expect(icon.color, AppColors.primary);
  });

  testWidgets('LocationMarker colorOverride wins over the mode color', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: LocationMarker(
          mode: LocationMode.outdoor,
          colorOverride: Colors.amber,
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, Colors.amber);
  });
}
