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

    // 앱은 이제 스플래시 화면 없이 바로 야외(홈) 지도로 시작한다.
    expect(find.text('홈'), findsOneWidget);
    expect(find.text('실내'), findsOneWidget);
  });
}
