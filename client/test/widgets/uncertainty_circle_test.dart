import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/widgets/uncertainty_circle.dart';

void main() {
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
}
