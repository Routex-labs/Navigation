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
  int _sessionId = 1;

  @override
  Stream<NativePdrEvent> get events => _controller.stream;

  @override
  Future<void> start() async => startCount++;

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<int?> resetPedometer() async {
    resetCount++;
    return ++_sessionId;
  }

  @override
  Future<void> dispose() async => _controller.close();

  void emitRaw(Map<String, Object?> raw) {
    final e = NativePdrEvent.tryParse(raw);
    if (e == null) return;
    _controller.add(e);
  }
}

Map<String, Object?> motionEvent({
  required int tMs,
  double heading = 0,
  String source = 'device_motion/xMagneticNorthZVertical',
  int? stepPeakCount,
  int? latestStepPeakMs,
}) =>
    {
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
}) =>
    {
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
    driver = IndoorNavigationDriver(
      source: source,
      nowMs: () => 0,
    );
  });

  tearDown(() async {
    await driver.dispose();
  });

  test('startGuidance는 소스를 켜고 awaitingPin으로 간다', () {
    driver.startGuidance(floorId: 'F1');
    expect(source.startCount, 1);
    expect(driver.currentCalibration.phase, CalibrationPhase.awaitingPin);
  });

  test('heading+pedometer를 흘리면 confirmed 스냅샷이 방출된다', () async {
    driver.startGuidance(floorId: 'F1');
    final seen = <PdrSnapshot>[];
    driver.snapshots.listen(seen.add);

    source.emitRaw(motionEvent(tMs: 1000, heading: 0));
    source.emitRaw(pedometerEvent(
      steps: 10,
      sessionStartMs: 900,
      endMs: 2000,
      distanceM: 7.0,
      peaks: [1100, 1300, 1500, 1700, 1900],
    ));
    await settle();

    expect(driver.currentSnapshot, isNotNull);
    expect(driver.currentSnapshot!.steps, 10);
    expect(driver.currentSnapshot!.distanceM, closeTo(7.0, 1e-9));
    expect(seen, isNotEmpty);
  });

  test('자북 기준: pin 확정으로 바로 calibrated', () async {
    driver.startGuidance(floorId: 'F1');
    source.emitRaw(motionEvent(tMs: 1000, heading: 0));
    await settle();

    await driver.confirmAnchorByPin(
      floorPointM: const PdrLocalPoint(10, 20),
    );
    expect(driver.currentCalibration.phase, CalibrationPhase.calibrated);
    expect(driver.currentCalibration.canRenderPosition, isTrue);
    expect(driver.currentCalibration.anchor, isNotNull);
  });

  test('arbitrary 기준: pin 후 heading 보정까지 요구한다', () async {
    driver.startGuidance(floorId: 'F1');
    source.emitRaw(motionEvent(
      tMs: 1000,
      heading: 0,
      source: 'device_motion/xArbitraryCorrectedZVertical',
    ));
    await settle();

    await driver.confirmAnchorByPin(
      floorPointM: const PdrLocalPoint(0, 0),
    );
    expect(driver.currentCalibration.phase, CalibrationPhase.awaitingHeading);
    expect(driver.currentCalibration.requiresManualRotationCalibration, isTrue);

    await driver.confirmAnchorByHeading(floorHeadingDeg: 90);
    expect(driver.currentCalibration.phase, CalibrationPhase.calibrated);
    expect(driver.currentCalibration.anchor!.rotationDeg, closeTo(90, 1e-9));
  });

  test('background는 tracking을 pause해 이후 배치를 반영하지 않는다', () async {
    driver.startGuidance(floorId: 'F1');
    source.emitRaw(motionEvent(tMs: 1000, heading: 0));
    await settle();

    driver.onAppBackgrounded();
    source.emitRaw(pedometerEvent(
      steps: 8,
      sessionStartMs: 900,
      endMs: 2000,
      distanceM: 5.6,
      peaks: [1200, 1600],
    ));
    await settle();

    expect(driver.currentSnapshot?.steps ?? 0, 0,
        reason: 'pause 중에는 confirmed가 늘지 않아야 한다');
  });

  test('stopGuidance는 소스를 끄고 uncalibrated로 되돌린다', () {
    driver.startGuidance(floorId: 'F1');
    driver.stopGuidance();
    expect(source.stopCount, 1);
    expect(driver.currentCalibration.phase, CalibrationPhase.uncalibrated);
  });

  test('changeFloor는 pedometer를 reset하고 awaitingPin으로 간다', () async {
    driver.startGuidance(floorId: 'F1');
    driver.changeFloor(floorId: 'F2');
    await settle();
    expect(source.resetCount, 1);
    expect(driver.currentCalibration.phase, CalibrationPhase.awaitingPin);
  });
}
