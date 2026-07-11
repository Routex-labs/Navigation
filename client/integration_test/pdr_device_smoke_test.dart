import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:navigation_client/features/indoor_navigation/application/indoor_navigation_controller.dart';
import 'package:navigation_client/features/indoor_navigation/contract/indoor_navigation_contract.dart';
import 'package:navigation_client/features/indoor_navigation/platform/ios_pdr_motion_source.dart';

const _enabled = bool.fromEnvironment('PDR_DEVICE_SMOKE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS 실기기 센서가 PDR snapshot을 갱신하고 stop 후 멈춘다', (tester) async {
    final source = IosPdrMotionSource();
    final driver = IndoorNavigationDriver(source: source);
    addTearDown(driver.dispose);

    await driver.startGuidance(floorId: 'device-smoke-floor');
    if (driver.currentRuntimeStatus.state != PdrRuntimeState.running) {
      await driver.runtimeStatuses
          .firstWhere((status) => status.state == PdrRuntimeState.running)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException(
              'PDR_DEVICE_SMOKE_HEADING_TIMEOUT: native heading/event를 '
              '15초 안에 받지 못했습니다. 현재 상태: '
              '${driver.currentRuntimeStatus.state}, '
              'warnings=${driver.currentRuntimeStatus.warnings}',
            ),
          );
    }

    // ignore: avoid_print
    print('PDR_DEVICE_SMOKE_WALK_NOW: 20초 동안 자연스럽게 걸어주세요.');
    final current = driver.currentSnapshot;
    final snapshot = current != null && current.steps > 0
        ? current
        : await driver.snapshots
              .firstWhere((value) => value.steps > 0 && value.distanceM > 0)
              .timeout(
                const Duration(seconds: 45),
                onTimeout: () => throw TimeoutException(
                  'PDR_DEVICE_SMOKE_WALK_TIMEOUT: 45초 안에 걸음 snapshot을 '
                  '받지 못했습니다. 권한을 확인하고 자연스럽게 걸어주세요.',
                ),
              );

    expect(snapshot.steps, greaterThan(0));
    expect(snapshot.distanceM, greaterThan(0));
    expect(
      snapshot.position.eastM.abs() + snapshot.position.northM.abs(),
      greaterThan(0),
    );

    var eventsAfterStop = 0;
    final eventSub = source.events.listen((_) => eventsAfterStop++);
    await driver.stopGuidance();
    eventsAfterStop = 0;
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(
      eventsAfterStop,
      0,
      reason: 'stopGuidance 이후 native 이벤트가 계속 들어오면 안 된다',
    );
    await eventSub.cancel();
  }, skip: !_enabled);
}
