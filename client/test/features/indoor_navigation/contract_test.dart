import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/contract/indoor_navigation_contract.dart';

/// 계약만 보고 만든 fake 구현. UI팀이 로직 완성을 기다리지 않고 이 계약으로
/// 병렬 작업할 수 있음을 보인다(Phase 1.5).
class FakeIndoorNavigation implements IndoorNavigationController {
  final _snapshots = StreamController<PdrSnapshot>.broadcast();
  final _calibration = StreamController<CalibrationStatus>.broadcast();

  PdrSnapshot? _current;
  CalibrationStatus _calib = const CalibrationStatus.uncalibrated();
  final List<String> log = [];

  @override
  Stream<PdrSnapshot> get snapshots => _snapshots.stream;

  @override
  PdrSnapshot? get currentSnapshot => _current;

  @override
  Stream<CalibrationStatus> get calibration => _calibration.stream;

  @override
  CalibrationStatus get currentCalibration => _calib;

  @override
  void startGuidance({required String floorId}) => log.add('start:$floorId');

  @override
  void stopGuidance() => log.add('stop');

  @override
  Future<void> confirmAnchorByPin({required PdrLocalPoint floorPointM}) async {
    log.add('pin:${floorPointM.eastM},${floorPointM.northM}');
  }

  @override
  Future<void> confirmAnchorByHeading({
    required double floorHeadingDeg,
  }) async {
    log.add('heading:$floorHeadingDeg');
  }

  @override
  void changeFloor({required String floorId}) => log.add('floor:$floorId');

  // 테스트 구동용.
  void pushCalibration(CalibrationStatus s) {
    _calib = s;
    _calibration.add(s);
  }

  void dispose() {
    _snapshots.close();
    _calibration.close();
  }
}

void main() {
  group('계약 conformance', () {
    test('fake는 View와 Intents를 모두 만족한다', () {
      final nav = FakeIndoorNavigation();
      expect(nav, isA<IndoorNavigationView>());
      expect(nav, isA<IndoorNavigationIntents>());
      nav.dispose();
    });

    test('UI intents가 로직으로 전달된다', () async {
      final nav = FakeIndoorNavigation();
      nav.startGuidance(floorId: 'F1');
      await nav.confirmAnchorByPin(
        floorPointM: const PdrLocalPoint(3, 4),
      );
      nav.changeFloor(floorId: 'F2');
      nav.stopGuidance();
      expect(nav.log, ['start:F1', 'pin:3.0,4.0', 'floor:F2', 'stop']);
      nav.dispose();
    });

    test('미보정 상태에서는 위치를 렌더하지 않는다', () {
      const status = CalibrationStatus.uncalibrated();
      expect(status.canRenderPosition, isFalse);
      expect(status.phase, CalibrationPhase.uncalibrated);
    });
  });

  group('FloorCoordinateTransform', () {
    PdrAnchor anchor({
      PdrLocalPoint origin = PdrLocalPoint.zero,
      double rotationDeg = 0,
    }) =>
        PdrAnchor(
          floorId: 'F1',
          anchorLocalM: origin,
          rotationDeg: rotationDeg,
          headingReference: HeadingReference.magneticNorth,
          requiresManualRotationCalibration: false,
          source: AnchorSource.userPin,
          confidence: 1,
        );

    test('회전·평행이동이 없으면 항등이다', () {
      final t = FloorCoordinateTransform(anchor());
      final p = t.toFloor(const PdrLocalPoint(2, 5));
      expect(p.eastM, closeTo(2, 1e-9));
      expect(p.northM, closeTo(5, 1e-9));
    });

    test('평행이동만 적용한다', () {
      final t = FloorCoordinateTransform(
        anchor(origin: const PdrLocalPoint(10, -3)),
      );
      final p = t.toFloor(const PdrLocalPoint(1, 2));
      expect(p.eastM, closeTo(11, 1e-9));
      expect(p.northM, closeTo(-1, 1e-9));
    });

    test('90도 회전을 적용한다', () {
      final t = FloorCoordinateTransform(anchor(rotationDeg: 90));
      // (1,0) → 90도 회전 → (0,1)
      final p = t.toFloor(const PdrLocalPoint(1, 0));
      expect(p.eastM, closeTo(0, 1e-9));
      expect(p.northM, closeTo(1, 1e-9));
    });

    test('회전 후 평행이동 순서로 왕복이 성립한다', () {
      final t = FloorCoordinateTransform(
        anchor(origin: const PdrLocalPoint(5, 5), rotationDeg: 90),
      );
      final p = t.toFloor(const PdrLocalPoint(2, 0));
      // (2,0)→회전→(0,2)→+anchor(5,5)→(5,7)
      expect(p.eastM, closeTo(5, 1e-9));
      expect(p.northM, closeTo(7, 1e-9));
    });
  });
}
