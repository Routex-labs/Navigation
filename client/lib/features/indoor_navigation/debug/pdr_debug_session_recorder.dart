import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../models/floor_graph.dart';
import '../application/floor_map_matcher.dart';
import '../contract/calibration_state.dart';
import '../contract/pdr_anchor.dart';
import '../contract/pdr_runtime_status.dart';

/// 실측 뒤 원인을 되짚기 위한, 의도적으로 작은 PDR 디버그 세션 레코더.
///
/// 매 원시 IMU 샘플을 저장하지 않는다. 확정 경로 전체와 1초 단위 품질 샘플만
/// 남겨 파일 크기를 제한하면서도 보폭·heading·맵매칭 문제를 구분할 수 있게 한다.
class PdrDebugSessionRecorder {
  PdrDebugSessionRecorder({DateTime? startedAt})
    : _startedAt = startedAt ?? DateTime.now().toUtc();

  // v4: 1Hz 샘플에 preview(주황)를 추가하고, pedometer live/재조회 대조 블록을
  // 넣었다. 지금까지는 시계열에 confirmed(초록)만 있어서 주황이 언제 벌어졌는지
  // 파일만으로는 알 수 없었다.
  static const schemaVersion = 4;
  static const _maxQualitySamples = 900;

  final DateTime _startedAt;
  final List<_PdrQualitySample> _qualitySamples = [];

  PdrSnapshot? _latestSnapshot;
  PdrAnchor? _anchor;
  PdrRuntimeStatus _runtimeStatus = const PdrRuntimeStatus.idle();
  Map<String, Object?>? _pedometerFinalize;
  DateTime? _lastQualitySampleAt;
  int? _lastSampledSteps;

  bool get hasSnapshot => _latestSnapshot != null;

  void recordSnapshot(PdrSnapshot snapshot, {DateTime? at}) {
    _latestSnapshot = snapshot;
    final now = (at ?? DateTime.now()).toUtc();
    final shouldSample =
        _lastQualitySampleAt == null ||
        _lastSampledSteps != snapshot.steps ||
        now.difference(_lastQualitySampleAt!).inMilliseconds >= 1000;
    if (!shouldSample) return;

    _qualitySamples.add(_PdrQualitySample.fromSnapshot(now, snapshot));
    if (_qualitySamples.length > _maxQualitySamples) {
      _qualitySamples.removeAt(0);
    }
    _lastQualitySampleAt = now;
    _lastSampledSteps = snapshot.steps;
  }

  void recordCalibration(CalibrationStatus status) {
    // stopGuidance 뒤에는 uncalibrated로 돌아가므로, 마지막으로 확정된 anchor는
    // 세션 JSON에 보존한다.
    if (status.anchor != null) _anchor = status.anchor;
  }

  void recordRuntime(PdrRuntimeStatus status) => _runtimeStatus = status;

  /// stopGuidance에서 native가 돌려준 pedometer 동결/재조회 결과.
  void recordPedometerFinalize(Map<String, Object?>? info) =>
      _pedometerFinalize = info;

  Map<String, Object?> buildJson({
    required String buildingId,
    required String? selectedFloor,
    required String mapCalibrationVersion,
    required FloorGraph? graph,
    required Map<String, Object?> device,
    DateTime? exportedAt,
  }) {
    final snapshot = _latestSnapshot;
    final anchor = _anchor;
    final hasMapContext =
        snapshot != null &&
        anchor != null &&
        graph != null &&
        graph.nodes.isNotEmpty &&
        anchor.floorId == selectedFloor;
    final rawPath = snapshot?.path ?? const <PdrLocalPoint>[];
    final floorPath = hasMapContext
        ? rawPath
              .map(FloorCoordinateTransform(anchor).toFloor)
              .toList(growable: false)
        : const <PdrLocalPoint>[];
    final matchedPath = hasMapContext
        ? FloorMapMatcher(graph).matchRoutedPath(floorPath)
        : const <PdrLocalPoint>[];

    return {
      'schema_version': schemaVersion,
      'type': 'pdr_debug_session',
      'started_at_utc': _startedAt.toIso8601String(),
      'exported_at_utc': (exportedAt ?? DateTime.now().toUtc())
          .toIso8601String(),
      'device': device,
      'map_context': {
        'building_id': buildingId,
        'floor_id': selectedFloor,
        'map_calibration_version': mapCalibrationVersion,
        'graph_node_count': graph?.nodes.length ?? 0,
        'graph_edge_count': graph?.edges.length ?? 0,
      },
      'anchor': _anchorJson(anchor),
      'summary': _summaryJson(
        snapshot,
        floorPathDistanceM: _pathLength(floorPath),
        mapMatchedDistanceM: _pathLength(matchedPath),
      ),
      'paths': {
        'confirmed_pdr_local_m': _pointsJson(rawPath),
        'floor_local_m_before_matching': _pointsJson(floorPath),
        'map_matched_floor_local_m': _pointsJson(matchedPath),
      },
      'quality_samples_1hz': [
        for (final sample in _qualitySamples) sample.toJson(),
      ],
      'runtime': {
        'state': _runtimeStatus.state.name,
        'warnings': _runtimeStatus.warnings,
      },
      'pedometer_finalize': _pedometerFinalizeJson(),
    };
  }

  /// live stream이 센 걸음(`live_steps`)과 같은 구간을 사후 재조회한
  /// 걸음(`queried_steps`)의 대조.
  ///
  /// 이 둘의 관계가 초반 구간 부족분의 성격을 가른다:
  ///  - `queried > live`  -> OS는 봤는데 live stream이 늦게/적게 흘린 것.
  ///                         재조회 값으로 백필하는 게 옳다.
  ///  - `queried == live` -> OS가 그 걸음들을 아예 못 봤다. 백필할 근거가 없고
  ///                         다른 방법을 찾아야 한다.
  ///
  /// 판단 근거를 모으는 단계이므로 이 값으로 경로를 보정하지 않는다.
  Map<String, Object?>? _pedometerFinalizeJson() {
    final info = _pedometerFinalize;
    if (info == null) return null;
    final live = (info['steps'] as num?)?.toInt();
    final queried = (info['queriedSteps'] as num?)?.toInt();
    return {
      'live_steps': live,
      'queried_steps': queried,
      'queried_distance_m': (info['queriedDistanceM'] as num?)?.toDouble(),
      'query_available': info['queryAvailable'],
      'query_error': info['queryError'],
      'session_start_ms': (info['sessionStartMs'] as num?)?.toDouble(),
      'stopped_at_ms': (info['stoppedAtMs'] as num?)?.toDouble(),
      if (live != null && queried != null) 'queried_minus_live': queried - live,
    };
  }

  static Map<String, Object?>? _anchorJson(PdrAnchor? anchor) {
    if (anchor == null) return null;
    return {
      'floor_id': anchor.floorId,
      'floor_local_m': _pointJson(anchor.anchorLocalM),
      'rotation_deg': anchor.rotationDeg,
      'pdr_to_floor_axes': {
        'east_to_x': anchor.axes.eastToX,
        'north_to_x': anchor.axes.northToX,
        'east_to_y': anchor.axes.eastToY,
        'north_to_y': anchor.axes.northToY,
      },
      'heading_reference': anchor.headingReference.name,
      'requires_manual_rotation_calibration':
          anchor.requiresManualRotationCalibration,
      'source': anchor.source.name,
      'confidence': anchor.confidence,
    };
  }

  static Map<String, Object?> _summaryJson(
    PdrSnapshot? snapshot, {
    required double floorPathDistanceM,
    required double mapMatchedDistanceM,
  }) {
    if (snapshot == null) return const {'recorded': false};
    final features = snapshot.quality.features;
    return {
      'recorded': true,
      'confirmed_steps': snapshot.steps,
      'confirmed_distance_m': snapshot.distanceM,
      'floor_path_distance_m_before_matching': floorPathDistanceM,
      'map_matched_path_distance_m': mapMatchedDistanceM,
      'walking_heading_deg': snapshot.walkingHeadingDeg,
      'has_heading': snapshot.hasHeading,
      'preview_steps': snapshot.preview.steps,
      'preview_distance_m': snapshot.preview.distanceM,
      'quality': {
        'state': snapshot.quality.state.name,
        'warnings': snapshot.quality.warnings,
        'heading_stable': features.headingStable,
        'heading_source': features.headingSource,
        'magnetic_accuracy': features.magneticAccuracy,
        'rotation_heading_accuracy_deg': features.rotationHeadingAccuracyDeg,
        'heading_reference_is_magnetic_north':
            features.headingReferenceIsMagneticNorth,
        'cadence_hz': features.cadenceHz,
        'pitch_deg': features.pitchDeg,
        'roll_deg': features.rollDeg,
        'green_orange_distance_divergence_pct':
            features.greenOrangeDistanceDivergencePct,
        'orange_step_ratio': features.orangeStepRatio,
        'orange_overcount_likely': features.orangeOvercountLikely,
        'pedometer_undercount_suspected': features.pedometerUndercountSuspected,
        'pedometer_flagged_span_s': features.pedometerFlaggedSpanS,
        'peak_reject_histogram': features.peakRejectHistogram,
      },
    };
  }

  static List<Map<String, double>> _pointsJson(
    Iterable<PdrLocalPoint> points,
  ) => [for (final point in points) _pointJson(point)];

  static Map<String, double> _pointJson(PdrLocalPoint point) => {
    'east_m': point.eastM,
    'north_m': point.northM,
  };

  static double _pathLength(List<PdrLocalPoint> points) {
    var total = 0.0;
    for (var index = 1; index < points.length; index++) {
      final dx = points[index].eastM - points[index - 1].eastM;
      final dy = points[index].northM - points[index - 1].northM;
      total += math.sqrt(dx * dx + dy * dy);
    }
    return total;
  }
}

class _PdrQualitySample {
  const _PdrQualitySample({
    required this.at,
    required this.steps,
    required this.distanceM,
    required this.walkingHeadingDeg,
    required this.headingStable,
    required this.magneticAccuracy,
    required this.rotationHeadingAccuracyDeg,
    required this.cadenceHz,
    required this.previewSteps,
    required this.previewDistanceM,
  });

  final DateTime at;
  final int steps;
  final double distanceM;
  final double walkingHeadingDeg;
  final bool headingStable;
  final String magneticAccuracy;
  final double rotationHeadingAccuracyDeg;
  final double cadenceHz;

  /// 주황(accel preview) 시계열. 초록만 남기면 둘이 **언제** 벌어졌는지를
  /// 파일에서 못 읽는다 — 초반 지연인지 전 구간에 걸친 과다 계수인지 구분하려면
  /// 두 곡선을 같은 시간축에 놓아야 한다.
  final int previewSteps;
  final double previewDistanceM;

  factory _PdrQualitySample.fromSnapshot(DateTime at, PdrSnapshot snapshot) {
    final features = snapshot.quality.features;
    return _PdrQualitySample(
      at: at,
      steps: snapshot.steps,
      distanceM: snapshot.distanceM,
      walkingHeadingDeg: snapshot.walkingHeadingDeg,
      headingStable: features.headingStable,
      magneticAccuracy: features.magneticAccuracy,
      rotationHeadingAccuracyDeg: features.rotationHeadingAccuracyDeg,
      cadenceHz: features.cadenceHz,
      previewSteps: snapshot.preview.steps,
      previewDistanceM: snapshot.preview.distanceM,
    );
  }

  Map<String, Object?> toJson() => {
    'at_utc': at.toIso8601String(),
    'steps': steps,
    'distance_m': distanceM,
    'preview_steps': previewSteps,
    'preview_distance_m': previewDistanceM,
    'walking_heading_deg': walkingHeadingDeg,
    'heading_stable': headingStable,
    'magnetic_accuracy': magneticAccuracy,
    'rotation_heading_accuracy_deg': rotationHeadingAccuracyDeg,
    'cadence_hz': cadenceHz,
  };
}
