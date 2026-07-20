import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/application/indoor_navigation_controller.dart';
import 'package:navigation_client/features/indoor_navigation/contract/indoor_navigation_contract.dart';
import 'package:navigation_client/features/indoor_navigation/platform/native_pdr_event.dart';
import 'package:navigation_client/features/indoor_navigation/platform/pdr_motion_source.dart';

/// 테스트/하니스용 fake 소스. raw native map을 파서에 태워 흘린다(파서+컨트롤러+코어
/// end-to-end = 헤드리스 하니스).
class FakePdrMotionSource implements PdrMotionSource {
  final _controller = StreamController<NativePdrEvent>.broadcast();
  int startCount = 0;
  int stopCount = 0;
  int resetCount = 0;
  int finalizeCount = 0;
  int _sessionId = 0;
  Object? startError;
  Object? stopError;
  Object? resetError;

  @override
  Stream<NativePdrEvent> get events => _controller.stream;

  @override
  Future<void> start() async {
    startCount++;
    if (startError case final error?) throw error;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    if (stopError case final error?) throw error;
  }

  @override
  Future<int?> resetPedometer() async {
    resetCount++;
    if (resetError case final error?) throw error;
    return ++_sessionId;
  }

  @override
  Future<void> finalizePedometer() async {
    finalizeCount++;
  }

  @override
  Future<void> dispose() async => _controller.close();

  void emitRaw(Map<String, Object?> raw) {
    final e = NativePdrEvent.tryParse(raw);
    if (e == null) return;
    _controller.add(e);
  }

  void emitError(Object error) => _controller.addError(error);
}

Map<String, Object?> motionEvent({
  required int tMs,
  double heading = 0,
  String source = 'device_motion/xMagneticNorthZVertical',
  int? stepPeakCount,
  int? latestStepPeakMs,
}) => {
  'source': 'ios_core_motion',
  'kind': 'motion',
  'stepSessionId': 1,
  'fusedHeadingDeg': heading,
  'headingStable': true,
  'headingSource': source,
  'motionTimestamp': tMs.toDouble(),
  'stepPeakCount': ?stepPeakCount,
  'latestStepPeakMs': ?latestStepPeakMs?.toDouble(),
};

Map<String, Object?> pedometerEvent({
  required int steps,
  required int sessionStartMs,
  required int endMs,
  required double distanceM,
  List<double>? peaks,
}) => {
  'source': 'ios_core_motion',
  'kind': 'pedometer',
  'stepSessionId': 1,
  'steps': steps,
  'pedometerSessionStartMs': sessionStartMs,
  'pedometerTimestamp': endMs.toDouble(),
  'pedometerDistance': distanceM,
  'pedometerDistanceAvailable': true,
  'stepPeakTimes': peaks,
};

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakePdrMotionSource source;
  late IndoorNavigationDriver driver;

  setUp(() {
    source = FakePdrMotionSource();
    driver = IndoorNavigationDriver(source: source, nowMs: () => 0);
  });

  tearDown(() async {
    await driver.dispose();
  });

  test('startGuidance는 소스를 켜고 awaitingPin으로 간다', () async {
    await driver.startGuidance(floorId: 'F1');
    expect(source.startCount, 1);
    expect(source.resetCount, 1);
    expect(driver.currentCalibration.phase, CalibrationPhase.awaitingPin);
  });

  test('start는 starting이고 첫 native 이벤트 뒤 running이다', () async {
    await driver.startGuidance(floorId: 'F1');
    expect(driver.currentRuntimeStatus.state, PdrRuntimeState.starting);

    source.emitRaw(motionEvent(tMs: 1000));
    await settle();

    expect(driver.currentRuntimeStatus.state, PdrRuntimeState.running);
  });

  test('센서 시작 실패는 degraded warning으로 노출된다', () async {
    source.startError = StateError('denied');

    await driver.startGuidance(floorId: 'F1');

    expect(driver.currentRuntimeStatus.state, PdrRuntimeState.degraded);
    expect(driver.currentRuntimeStatus.warnings, contains('sensorStartFailed'));
  });

  test('센서 stream 오류는 처리되어 degraded가 된다', () async {
    await driver.startGuidance(floorId: 'F1');

    source.emitError(StateError('stream'));
    await settle();

    expect(driver.currentRuntimeStatus.state, PdrRuntimeState.degraded);
    expect(driver.currentRuntimeStatus.warnings, contains('sensorStreamError'));
  });

  test('heading+pedometer를 흘리면 confirmed 스냅샷이 방출된다', () async {
    await driver.startGuidance(floorId: 'F1');
    final seen = <PdrSnapshot>[];
    driver.snapshots.listen(seen.add);

    source.emitRaw(motionEvent(tMs: 1000, heading: 0));
    source.emitRaw(
      pedometerEvent(
        steps: 10,
        sessionStartMs: 900,
        endMs: 2000,
        distanceM: 7.0,
        peaks: [1100, 1300, 1500, 1700, 1900],
      ),
    );
    await settle();

    expect(driver.currentSnapshot, isNotNull);
    expect(driver.currentSnapshot!.steps, 10);
    expect(driver.currentSnapshot!.distanceM, closeTo(7.0, 1e-9));
    expect(seen, isNotEmpty);
  });

  test('자북 기준: pin 확정으로 바로 calibrated', () async {
    await driver.startGuidance(floorId: 'F1');
    source.emitRaw(motionEvent(tMs: 1000, heading: 0));
    await settle();

    await driver.confirmAnchorByPin(
      floorPointM: const PdrLocalPoint(10, 20),
      axes: const PdrToFloorAxes(
        eastToX: 1,
        northToX: 0,
        eastToY: 0,
        northToY: -1,
      ),
    );
    expect(driver.currentCalibration.phase, CalibrationPhase.calibrated);
    expect(driver.currentCalibration.canRenderPosition, isTrue);
    expect(driver.currentCalibration.anchor, isNotNull);
    expect(driver.currentCalibration.anchor!.axes.northToY, -1);
  });

  test('arbitrary 기준: pin 후 heading 보정까지 요구한다', () async {
    await driver.startGuidance(floorId: 'F1');
    source.emitRaw(
      motionEvent(
        tMs: 1000,
        heading: 0,
        source: 'device_motion/xArbitraryCorrectedZVertical',
      ),
    );
    await settle();

    const rotatedAxes = PdrToFloorAxes(
      // 실제 동쪽은 floor 위쪽(+y), 실제 북쪽은 floor 왼쪽(-x)인 회전층.
      eastToX: 0,
      northToX: -1,
      eastToY: 1,
      northToY: 0,
    );
    await driver.confirmAnchorByPin(
      floorPointM: const PdrLocalPoint(0, 0),
      axes: rotatedAxes,
    );
    expect(driver.currentCalibration.phase, CalibrationPhase.awaitingHeading);
    expect(driver.currentCalibration.requiresManualRotationCalibration, isTrue);

    await driver.confirmAnchorByFloorDirection(
      floorDirection: const PdrLocalPoint(0, 1),
    );
    expect(driver.currentCalibration.phase, CalibrationPhase.calibrated);
    expect(driver.currentCalibration.anchor!.rotationDeg, closeTo(90, 1e-9));
    final mappedNorth = FloorCoordinateTransform(
      driver.currentCalibration.anchor!,
    ).toFloor(const PdrLocalPoint(0, 1));
    expect(mappedNorth.eastM, closeTo(0, 1e-9));
    expect(mappedNorth.northM, closeTo(1, 1e-9));
  });

  test('background는 tracking을 pause해 이후 배치를 반영하지 않는다', () async {
    await driver.startGuidance(floorId: 'F1');
    source.emitRaw(motionEvent(tMs: 1000, heading: 0));
    await settle();

    await driver.onAppBackgrounded();
    source.emitRaw(
      pedometerEvent(
        steps: 8,
        sessionStartMs: 900,
        endMs: 2000,
        distanceM: 5.6,
        peaks: [1200, 1600],
      ),
    );
    await settle();

    expect(
      driver.currentSnapshot?.steps ?? 0,
      0,
      reason: 'pause 중에는 confirmed가 늘지 않아야 한다',
    );
  });

  test('안내 중 background는 tracking과 native source를 한 번 멈춘다', () async {
    await driver.startGuidance(floorId: 'F1');
    source.emitRaw(motionEvent(tMs: 1000));
    await settle();

    await driver.onAppBackgrounded();
    await driver.onAppBackgrounded();

    expect(source.stopCount, 1);
    expect(driver.currentRuntimeStatus.state, PdrRuntimeState.paused);
  });

  test('background 뒤 foreground는 source와 tracking을 한 번 재개한다', () async {
    await driver.startGuidance(floorId: 'F1');
    await driver.onAppBackgrounded();

    await driver.onAppForegrounded();
    await driver.onAppForegrounded();

    expect(source.startCount, 2);
    expect(driver.currentRuntimeStatus.state, PdrRuntimeState.starting);
  });

  test('안내 중이 아니면 lifecycle이 source를 호출하지 않는다', () async {
    await driver.onAppBackgrounded();
    await driver.onAppForegrounded();

    expect(source.startCount, 0);
    expect(source.stopCount, 0);
  });

  test('background 센서 정지 실패는 degraded warning으로 노출된다', () async {
    await driver.startGuidance(floorId: 'F1');
    source.stopError = StateError('stop');

    await driver.onAppBackgrounded();

    expect(driver.currentRuntimeStatus.state, PdrRuntimeState.degraded);
    expect(driver.currentRuntimeStatus.warnings, contains('sensorStopFailed'));
  });

  test('foreground 센서 재시작 실패는 degraded warning으로 노출된다', () async {
    await driver.startGuidance(floorId: 'F1');
    await driver.onAppBackgrounded();
    source.startError = StateError('resume');

    await driver.onAppForegrounded();

    expect(driver.currentRuntimeStatus.state, PdrRuntimeState.degraded);
    expect(
      driver.currentRuntimeStatus.warnings,
      contains('sensorResumeFailed'),
    );
  });

  test('runtime 오류 뒤 snapshot quality와 warning도 degraded로 합성된다', () async {
    await driver.startGuidance(floorId: 'F1');
    source.emitError(StateError('stream'));
    source.emitRaw(motionEvent(tMs: 1000));
    source.emitRaw(
      pedometerEvent(
        steps: 4,
        sessionStartMs: 900,
        endMs: 2000,
        distanceM: 2.8,
        peaks: [1200, 1600],
      ),
    );
    await settle();

    expect(driver.currentSnapshot, isNotNull);
    expect(driver.currentSnapshot!.quality.state, PdrQualityState.degraded);
    expect(
      driver.currentSnapshot!.quality.warnings,
      contains('sensorStreamError'),
    );
  });

  test('stopGuidance는 소스를 끄고 uncalibrated로 되돌린다', () async {
    await driver.startGuidance(floorId: 'F1');
    await driver.stopGuidance();
    expect(source.stopCount, 1);
    expect(source.finalizeCount, 1);
    expect(driver.currentCalibration.phase, CalibrationPhase.uncalibrated);
  });

  test('changeFloor는 pedometer를 reset하고 awaitingPin으로 간다', () async {
    await driver.startGuidance(floorId: 'F1');
    await driver.changeFloor(floorId: 'F2');
    expect(source.resetCount, 2);
    expect(driver.currentCalibration.phase, CalibrationPhase.awaitingPin);
  });
}
