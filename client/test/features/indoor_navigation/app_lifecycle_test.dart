import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/app.dart';

void main() {
  testWidgets('앱 lifecycle을 PDR callback으로 전달한다', (tester) async {
    var backgrounds = 0;
    var foregrounds = 0;
    await tester.pumpWidget(
      NavigationApp(
        onPdrBackgrounded: () => backgrounds++,
        onPdrForegrounded: () => foregrounds++,
        home: const SizedBox(),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(backgrounds, 1);
    expect(foregrounds, 1);
  });

  testWidgets('동일 lifecycle 반복 알림은 한 번만 전달한다', (tester) async {
    var backgrounds = 0;
    var foregrounds = 0;
    await tester.pumpWidget(
      NavigationApp(
        onPdrBackgrounded: () => backgrounds++,
        onPdrForegrounded: () => foregrounds++,
        home: const SizedBox(),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(backgrounds, 1);
    expect(foregrounds, 1);
  });

  testWidgets('iOS의 짧은 inactive는 PDR 센서를 중단하지 않는다', (tester) async {
    var backgrounds = 0;
    var foregrounds = 0;
    await tester.pumpWidget(
      NavigationApp(
        onPdrBackgrounded: () => backgrounds++,
        onPdrForegrounded: () => foregrounds++,
        home: const SizedBox(),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(backgrounds, 0);
    expect(foregrounds, 0);
  });
}
