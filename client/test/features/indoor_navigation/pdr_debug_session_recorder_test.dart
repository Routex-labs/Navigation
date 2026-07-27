import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/features/indoor_navigation/contract/calibration_state.dart';
import 'package:navigation_client/features/indoor_navigation/contract/pdr_anchor.dart';
import 'package:navigation_client/features/indoor_navigation/debug/pdr_debug_session_recorder.dart';
import 'package:navigation_client/models/floor_graph.dart';

PdrSnapshot _snapshot({
  required int steps,
  required double distanceM,
  required List<PdrLocalPoint> path,
}) => PdrSnapshot(
  position: path.last,
  path: path,
  steps: steps,
  distanceM: distanceM,
  walkingHeadingDeg: 90,
  hasHeading: true,
  preview: PdrPreview(
    position: path.last,
    path: path,
    steps: steps + 1,
    distanceM: distanceM + 0.5,
  ),
  quality: const PdrQuality(
    state: PdrQualityState.caution,
    warnings: ['headingUnstable'],
    features: PdrQualityFeatures(
      greenOrangeDistanceDivergencePct: 10,
      orangeStepRatio: 1.1,
      orangeOvercountLikely: false,
      pedometerUndercountSuspected: false,
      pedometerFlaggedSpanS: 0,
      headingStable: false,
      headingSource: 'sensor_manager/rotation_vector+gyro_hold',
      magneticAccuracy: 'low',
      rotationHeadingAccuracyDeg: -1,
      cadenceHz: 1.5,
      pitchDeg: 4,
      rollDeg: -2,
      headingReferenceIsMagneticNorth: true,
      peakRejectHistogram: {},
    ),
  ),
);

FloorGraph _graph() => const FloorGraph(
  nodes: [
    GraphNode(id: 'a', type: 'path', xM: 0, yM: 0),
    GraphNode(id: 'b', type: 'path', xM: 10, yM: 0),
  ],
  edges: [
    GraphEdge(
      id: 'ab',
      fromNodeId: 'a',
      toNodeId: 'b',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(10, 0)],
    ),
  ],
);

void main() {
  test('확정 PDR 경로·품질·맵매칭 결과만 JSON으로 내보낸다', () {
    final recorder = PdrDebugSessionRecorder(
      startedAt: DateTime.utc(2026, 7, 18, 9),
    );
    recorder.recordCalibration(
      CalibrationStatus(
        phase: CalibrationPhase.calibrated,
        headingReference: HeadingReference.magneticNorth,
        requiresManualRotationCalibration: false,
        anchor: const PdrAnchor(
          floorId: '1F',
          anchorLocalM: PdrLocalPoint.zero,
          rotationDeg: 0,
          headingReference: HeadingReference.magneticNorth,
          requiresManualRotationCalibration: false,
          source: AnchorSource.userPin,
          confidence: 1,
        ),
      ),
    );
    recorder.recordSnapshot(
      _snapshot(
        steps: 4,
        distanceM: 3.1,
        path: const [PdrLocalPoint(0, 0), PdrLocalPoint(4, 1)],
      ),
      at: DateTime.utc(2026, 7, 18, 9, 0, 2),
    );

    final json = recorder.buildJson(
      buildingId: 'thehyundai-seoul',
      selectedFloor: '1F',
      mapCalibrationVersion: 'thehyundai-seoul-1f-svg-v1',
      graph: _graph(),
      device: const {'device_name': 'Test device'},
      exportedAt: DateTime.utc(2026, 7, 18, 9, 1),
    );

    final summary = json['summary']! as Map<String, Object?>;
    final paths = json['paths']! as Map<String, Object?>;
    final matched = paths['map_matched_floor_local_m']! as List<Object?>;
    final finalMatched = matched.last! as Map<String, double>;

    expect(json['schema_version'], 4);
    expect(
      (json['map_context']! as Map<String, Object?>)['map_calibration_version'],
      'thehyundai-seoul-1f-svg-v1',
    );
    expect(summary['confirmed_steps'], 4);
    expect(summary['confirmed_distance_m'], 3.1);
    expect(summary['map_matched_path_distance_m'], closeTo(4, 1e-9));
    expect(
      (summary['quality']! as Map<String, Object?>)['magnetic_accuracy'],
      'low',
    );
    expect(finalMatched['east_m'], closeTo(4, 1e-9));
    expect(finalMatched['north_m'], closeTo(0, 1e-9));
    expect((json['quality_samples_1hz']! as List<Object?>), hasLength(1));
  });

  test('1Hz 샘플에 주황(preview)도 같이 남긴다', () {
    // 초록만 남기면 둘이 언제 벌어졌는지를 파일에서 못 읽는다.
    final recorder = PdrDebugSessionRecorder(
      startedAt: DateTime.utc(2026, 7, 18, 9),
    );
    recorder.recordSnapshot(
      _snapshot(
        steps: 4,
        distanceM: 3.1,
        path: const [PdrLocalPoint(0, 0), PdrLocalPoint(4, 1)],
      ),
      at: DateTime.utc(2026, 7, 18, 9),
    );

    final json = recorder.buildJson(
      buildingId: 'thehyundai-seoul',
      selectedFloor: '1F',
      mapCalibrationVersion: 'v1',
      graph: _graph(),
      device: const {},
    );

    final sample =
        (json['quality_samples_1hz']! as List<Object?>).single!
            as Map<String, Object?>;
    expect(sample['steps'], 4);
    expect(sample['distance_m'], 3.1);
    expect(sample['preview_steps'], 5);
    expect(sample['preview_distance_m'], 3.6);
  });

  test('pedometer live/재조회 대조를 남기고, 없으면 null이다', () {
    final recorder = PdrDebugSessionRecorder(
      startedAt: DateTime.utc(2026, 7, 18, 9),
    );
    recorder.recordSnapshot(
      _snapshot(
        steps: 4,
        distanceM: 3.1,
        path: const [PdrLocalPoint(0, 0), PdrLocalPoint(4, 1)],
      ),
      at: DateTime.utc(2026, 7, 18, 9),
    );

    Map<String, Object?> build() => recorder.buildJson(
      buildingId: 'thehyundai-seoul',
      selectedFloor: '1F',
      mapCalibrationVersion: 'v1',
      graph: _graph(),
      device: const {},
    );

    expect(build()['pedometer_finalize'], isNull);

    recorder.recordPedometerFinalize(const {
      'steps': 112,
      'queriedSteps': 140,
      'queriedDistanceM': 107.4,
      'queryAvailable': true,
      'sessionStartMs': 1000.0,
      'stoppedAtMs': 77000.0,
    });

    final finalize = build()['pedometer_finalize']! as Map<String, Object?>;
    expect(finalize['live_steps'], 112);
    expect(finalize['queried_steps'], 140);
    // 이 차이가 0인지 아닌지가 초반 부족분의 성격을 가른다.
    expect(finalize['queried_minus_live'], 28);
  });
}
