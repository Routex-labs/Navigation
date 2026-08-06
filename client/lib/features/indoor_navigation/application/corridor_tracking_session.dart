import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../models/floor_graph.dart';
import '../contract/pdr_anchor.dart';
import 'corridor_position_tracker.dart';

/// 화면 생명주기와 무관하게 한 PDR 세션의 복도 보정 상태를 이어주는 어댑터.
///
/// 이전 구현처럼 build 때 전체 원본 경로를 다시 맵매칭하지 않는다. 새 snapshot의
/// 누적 걸음·거리 차이만 [CorridorPositionTracker]에 적용한다.
class CorridorTrackingSession {
  CorridorPositionTracker? _tracker;
  String? _graphKey;
  String? _anchorKey;
  int? _lastSteps;
  double? _lastDistanceM;

  CorridorTrackingResult? get result => _tracker?.result;

  /// 직전 [update]가 tracker에 실제로 넘긴 관측. 디버그 레코더가 정확 재생용
  /// 입력 이벤트로 기록한다. 재초기화(reset) 경로였다면 null이다.
  CorridorObservation? get lastObservation => _lastObservation;

  /// 직전 [update]가 tracker를 재초기화했는지. 재생 시 같은 지점에서 상태를
  /// 다시 세워야 하므로 입력 이벤트와 함께 남긴다.
  bool get lastWasReset => _lastWasReset;

  CorridorObservation? _lastObservation;
  bool _lastWasReset = false;

  void reset() {
    _tracker = null;
    _graphKey = null;
    _anchorKey = null;
    _lastSteps = null;
    _lastDistanceM = null;
    _lastObservation = null;
    _lastWasReset = false;
  }

  CorridorTrackingResult? update({
    required FloorGraph? graph,
    required PdrAnchor? anchor,
    required PdrSnapshot? snapshot,
    required int timestampMs,
  }) {
    if (graph == null ||
        graph.edges.isEmpty ||
        anchor == null ||
        snapshot == null ||
        anchor.floorId.isEmpty) {
      return result;
    }

    final transform = FloorCoordinateTransform(anchor);
    final floorHeadingDeg = transform.toFloorBearing(
      snapshot.walkingHeadingDeg,
    );
    final sessionRewound =
        (_lastSteps != null && snapshot.steps < _lastSteps!) ||
        (_lastDistanceM != null && snapshot.distanceM < _lastDistanceM!);
    final nextGraphKey = _keyForGraph(graph);
    final nextAnchorKey = _keyForAnchor(anchor);
    if (_graphKey != nextGraphKey ||
        _anchorKey != nextAnchorKey ||
        _tracker == null ||
        sessionRewound) {
      final initialPosition = snapshot.steps == 0
          ? anchor.anchorLocalM
          : transform.toFloor(snapshot.position);
      _tracker = CorridorPositionTracker(graph)
        ..reset(
          initialPosition: initialPosition,
          initialHeadingDeg: floorHeadingDeg,
          timestampMs: timestampMs,
          initialConfirmedSteps: snapshot.steps,
          initialConfirmedDistanceM: snapshot.distanceM,
          initialPreviewSteps: snapshot.preview.steps,
        );
      _graphKey = nextGraphKey;
      _anchorKey = nextAnchorKey;
      _lastSteps = snapshot.steps;
      _lastDistanceM = snapshot.distanceM;
      _lastObservation = null;
      _lastWasReset = true;
      return _tracker!.result;
    }

    final observation = CorridorObservation(
      timestampMs: timestampMs,
      rawConfirmedPosition: transform.toFloor(snapshot.position),
      confirmedSteps: snapshot.steps,
      confirmedDistanceM: snapshot.distanceM,
      rawPreviewPosition: transform.toFloor(snapshot.preview.position),
      previewSteps: snapshot.preview.steps,
      sensorHeadingDeg: floorHeadingDeg,
      hasHeading: snapshot.hasHeading,
      rawConfirmedStepPositions: _newConfirmedFloorPoints(snapshot, transform),
      rawPreviewTailPositions: _previewTailFloorPoints(snapshot, transform),
      // 좌표만으로는 "이 주황 걸음을 이미 태웠는지"를 알 수 없다. accepted peak
      // 시각을 같은 인덱스로 함께 넘겨야 optimistic cursor가 배치 구성과
      // 무관하게 걸음을 한 번만 적용한다.
      rawPreviewTailPeakTimesMs: previewTailPeakTimesMs(snapshot),
      confirmedThroughMs: snapshot.lastAppliedBatch?.spanEndMs,
    );
    final output = _tracker!.update(observation);
    _lastObservation = observation;
    _lastWasReset = false;
    _lastSteps = snapshot.steps;
    _lastDistanceM = snapshot.distanceM;
    return output;
  }

  String _keyForGraph(FloorGraph graph) => [
    for (final node in graph.nodes)
      '${node.id}:${node.xM}:${node.yM}:${node.type}',
    for (final edge in graph.edges)
      '${edge.id}:${edge.fromNodeId}:${edge.toNodeId}:${edge.lengthM}:'
          '${edge.bidirectional}:${edge.transferMode}:'
          '${edge.geometryLocalM.map((point) => '${point.x},${point.y}').join(';')}',
  ].join('|');

  String _keyForAnchor(PdrAnchor anchor) => [
    anchor.floorId,
    anchor.anchorLocalM.eastM,
    anchor.anchorLocalM.northM,
    anchor.rotationDeg,
    anchor.axes.eastToX,
    anchor.axes.northToX,
    anchor.axes.eastToY,
    anchor.axes.northToY,
  ].join(':');

  List<PdrLocalPoint> _newConfirmedFloorPoints(
    PdrSnapshot snapshot,
    FloorCoordinateTransform transform,
  ) {
    final previousSteps = _lastSteps ?? snapshot.steps;
    final deltaSteps = snapshot.steps - previousSteps;
    if (deltaSteps <= 0 || snapshot.path.isEmpty) return const [];
    final start = (snapshot.path.length - deltaSteps).clamp(
      0,
      snapshot.path.length,
    );
    return snapshot.path
        .skip(start)
        .map(transform.toFloor)
        .toList(growable: false);
  }

  List<PdrLocalPoint> _previewTailFloorPoints(
    PdrSnapshot snapshot,
    FloorCoordinateTransform transform,
  ) {
    final start = _previewTailStart(snapshot);
    if (start == null) return const [];
    return snapshot.preview.path
        .skip(start)
        .map(transform.toFloor)
        .toList(growable: false);
  }

  /// [_previewTailFloorPoints]와 **같은 인덱스**의 accepted peak 시각.
  ///
  /// 재생·분석이 "이 주황 꼬리가 언제 찍힌 걸음인지"를 알아야 확정 배치
  /// 시간창과 대조할 수 있다. 좌표만으로는 복원되지 않는 정보다.
  List<int?> previewTailPeakTimesMs(PdrSnapshot snapshot) {
    final start = _previewTailStart(snapshot);
    if (start == null) return const [];
    final times = snapshot.preview.acceptedPeakTimesMs;
    if (times.length != snapshot.preview.path.length) return const [];
    return times.skip(start).toList(growable: false);
  }

  int? _previewTailStart(PdrSnapshot snapshot) {
    final path = snapshot.preview.path;
    if (path.length < 2) return null;
    final times = snapshot.preview.acceptedPeakTimesMs;
    final confirmedThroughMs = snapshot.lastAppliedBatch?.spanEndMs;
    if (confirmedThroughMs != null && times.length == path.length) {
      for (var index = 1; index < times.length; index++) {
        final peakMs = times[index];
        if (peakMs != null && peakMs > confirmedThroughMs) {
          // 첫 pending 점의 이동 벡터를 만들 수 있게 직전 점부터 돌려준다.
          return index - 1;
        }
      }
      return null;
    }

    // 시간 정보가 없는 Android/옛 fixture만 기존 걸음 수 차이로 폴백한다.
    final leadSteps = snapshot.preview.steps - snapshot.steps;
    if (leadSteps <= 0) return null;
    final movementCount = math.min(leadSteps, path.length - 1);
    return path.length - movementCount - 1;
  }
}
