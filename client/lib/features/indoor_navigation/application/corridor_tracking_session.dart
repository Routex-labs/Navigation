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

  void reset() {
    _tracker = null;
    _graphKey = null;
    _anchorKey = null;
    _lastSteps = null;
    _lastDistanceM = null;
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
      return _tracker!.result;
    }

    final output = _tracker!.update(
      CorridorObservation(
        timestampMs: timestampMs,
        rawConfirmedPosition: transform.toFloor(snapshot.position),
        confirmedSteps: snapshot.steps,
        confirmedDistanceM: snapshot.distanceM,
        rawPreviewPosition: transform.toFloor(snapshot.preview.position),
        previewSteps: snapshot.preview.steps,
        sensorHeadingDeg: floorHeadingDeg,
        hasHeading: snapshot.hasHeading,
        rawConfirmedStepPositions: _newConfirmedFloorPoints(
          snapshot,
          transform,
        ),
        rawPreviewTailPositions: _previewTailFloorPoints(snapshot, transform),
      ),
    );
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
    final leadSteps = snapshot.preview.steps - snapshot.steps;
    final path = snapshot.preview.path;
    if (leadSteps <= 0 || path.length < 2) return const [];
    final movementCount = math.min(leadSteps, path.length - 1);
    return path
        .skip(path.length - movementCount - 1)
        .map(transform.toFloor)
        .toList(growable: false);
  }
}
