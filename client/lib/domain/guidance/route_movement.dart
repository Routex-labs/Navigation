import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import 'corridor_tracking.dart';
import '../../models/floor_graph.dart';

enum RouteStepRelation { forward, reverse, offRoute, ambiguous, relocated }

enum TravelDirectionState {
  forward,
  reverseCandidate,
  reverseConfirmed,
  forwardCandidate,
  offRoute,
}

class RouteStepAdvance {
  const RouteStepAdvance({
    required this.peakId,
    required this.occurredAtMs,
    required this.signedRouteDistanceM,
    required this.relation,
    required this.crossedRouteWaypointIds,
    this.optimisticEdgeId,
    this.previewIsAmbiguous = false,
    this.actualMarkerPosition,
    this.walkingHeadingDeg,
    this.mapMatchedHeadingDeg,
    this.routeHeadingDeg,
    this.orientationHeadingDeg,
    this.headingErrorDeg,
  });

  final int peakId;
  final int occurredAtMs;
  final double signedRouteDistanceM;
  final RouteStepRelation relation;
  final List<String> crossedRouteWaypointIds;
  final String? optimisticEdgeId;
  final bool previewIsAmbiguous;
  final PdrLocalPoint? actualMarkerPosition;
  final double? walkingHeadingDeg;
  final double? mapMatchedHeadingDeg;
  final double? routeHeadingDeg;
  final double? orientationHeadingDeg;
  final double? headingErrorDeg;
}

class TravelDirectionTransition {
  const TravelDirectionTransition({
    required this.from,
    required this.to,
    required this.peakId,
    required this.occurredAtMs,
    required this.evidencePeakCount,
    required this.evidenceDistanceM,
  });

  final TravelDirectionState from;
  final TravelDirectionState to;
  final int peakId;
  final int occurredAtMs;
  final int evidencePeakCount;
  final double evidenceDistanceM;
}

/// graph traversal을 활성 경로의 목적지 방향 부호로 정규화한다.
RouteStepAdvance adaptOptimisticStepToRoute({
  required OptimisticStepAdvance step,
  required FloorGraph graph,
  required List<String> routeEdgeIds,
  required List<String> routeNodeIds,
  double? orientationHeadingDeg,
  double? walkingHeadingDeg,
}) {
  if (step.leaderRelocated) {
    return RouteStepAdvance(
      peakId: step.peakId,
      occurredAtMs: step.occurredAtMs,
      signedRouteDistanceM: 0,
      relation: RouteStepRelation.relocated,
      crossedRouteWaypointIds: const [],
      optimisticEdgeId: step.edgeId,
      previewIsAmbiguous: step.previewIsAmbiguous,
      actualMarkerPosition: step.position,
      walkingHeadingDeg: walkingHeadingDeg,
      mapMatchedHeadingDeg: step.mapMatchedHeadingDeg,
      orientationHeadingDeg: orientationHeadingDeg,
    );
  }
  if (step.traversals.isEmpty ||
      routeNodeIds.length != routeEdgeIds.length + 1) {
    return RouteStepAdvance(
      peakId: step.peakId,
      occurredAtMs: step.occurredAtMs,
      signedRouteDistanceM: 0,
      relation: RouteStepRelation.ambiguous,
      crossedRouteWaypointIds: const [],
      optimisticEdgeId: step.edgeId,
      previewIsAmbiguous: step.previewIsAmbiguous,
      actualMarkerPosition: step.position,
      walkingHeadingDeg: walkingHeadingDeg,
      mapMatchedHeadingDeg: step.mapMatchedHeadingDeg,
      orientationHeadingDeg: orientationHeadingDeg,
    );
  }

  final edgesById = {for (final edge in graph.edges) edge.id: edge};
  final nodesById = {for (final node in graph.nodes) node.id: node};
  var signedM = 0.0;
  var routeHeadingDeg = <double>[];
  for (final traversal in step.traversals) {
    final routeIndex = routeEdgeIds.indexOf(traversal.edgeId);
    final edge = edgesById[traversal.edgeId];
    if (routeIndex < 0 || edge == null) {
      return RouteStepAdvance(
        peakId: step.peakId,
        occurredAtMs: step.occurredAtMs,
        signedRouteDistanceM: signedM,
        relation: RouteStepRelation.offRoute,
        crossedRouteWaypointIds: const [],
        optimisticEdgeId: step.edgeId,
        previewIsAmbiguous: step.previewIsAmbiguous,
        actualMarkerPosition: step.position,
        walkingHeadingDeg: walkingHeadingDeg,
        mapMatchedHeadingDeg: step.mapMatchedHeadingDeg,
        orientationHeadingDeg: orientationHeadingDeg,
      );
    }
    final routeFrom = routeNodeIds[routeIndex];
    final routeTo = routeNodeIds[routeIndex + 1];
    final routeSign = edge.fromNodeId == routeFrom && edge.toNodeId == routeTo
        ? 1
        : edge.fromNodeId == routeTo && edge.toNodeId == routeFrom
        ? -1
        : 0;
    if (routeSign == 0) {
      return RouteStepAdvance(
        peakId: step.peakId,
        occurredAtMs: step.occurredAtMs,
        signedRouteDistanceM: signedM,
        relation: RouteStepRelation.ambiguous,
        crossedRouteWaypointIds: const [],
        optimisticEdgeId: step.edgeId,
        previewIsAmbiguous: step.previewIsAmbiguous,
        actualMarkerPosition: step.position,
        walkingHeadingDeg: walkingHeadingDeg,
        mapMatchedHeadingDeg: step.mapMatchedHeadingDeg,
        orientationHeadingDeg: orientationHeadingDeg,
      );
    }
    signedM += traversal.distanceM * traversal.edgeDirectionSign * routeSign;
    final heading = _edgeRouteBearing(edge, routeSign, nodesById: nodesById);
    if (heading != null) routeHeadingDeg.add(heading);
  }

  final routeHeading = routeHeadingDeg.isEmpty ? null : routeHeadingDeg.last;
  final headingError = orientationHeadingDeg == null || routeHeading == null
      ? null
      : _bearingError(orientationHeadingDeg, routeHeading);
  final routeNodes = routeNodeIds.toSet();
  return RouteStepAdvance(
    peakId: step.peakId,
    occurredAtMs: step.occurredAtMs,
    signedRouteDistanceM: signedM,
    relation: signedM > 1e-6
        ? RouteStepRelation.forward
        : signedM < -1e-6
        ? RouteStepRelation.reverse
        : RouteStepRelation.ambiguous,
    crossedRouteWaypointIds: [
      for (final nodeId in step.crossedNodeIds)
        if (routeNodes.contains(nodeId)) nodeId,
    ],
    optimisticEdgeId: step.edgeId,
    previewIsAmbiguous: step.previewIsAmbiguous,
    actualMarkerPosition: step.position,
    walkingHeadingDeg: walkingHeadingDeg,
    mapMatchedHeadingDeg: step.mapMatchedHeadingDeg,
    routeHeadingDeg: routeHeading,
    orientationHeadingDeg: orientationHeadingDeg,
    headingErrorDeg: headingError,
  );
}

/// heading만으로는 전이하지 않고, 서로 다른 preview peak의 signed traversal만
/// 제품 방향 상태로 승격한다.
class TravelDirectionTracker {
  TravelDirectionTracker({
    this.confirmPeakCount = 3,
    this.confirmDistanceM = 1.2,
    this.recoverPeakCount = 3,
    this.recoverDistanceM = 1.2,
  });

  final int confirmPeakCount;
  final double confirmDistanceM;
  final int recoverPeakCount;
  final double recoverDistanceM;

  TravelDirectionState _state = TravelDirectionState.forward;
  int? _lastEvidencePeakId;
  int _evidencePeakCount = 0;
  double _evidenceDistanceM = 0;

  TravelDirectionState get state => _state;
  int get evidencePeakCount => _evidencePeakCount;
  double get evidenceDistanceM => _evidenceDistanceM;

  void reset() {
    _state = TravelDirectionState.forward;
    _lastEvidencePeakId = null;
    _evidencePeakCount = 0;
    _evidenceDistanceM = 0;
  }

  TravelDirectionTransition? apply(RouteStepAdvance step) {
    if (step.peakId == _lastEvidencePeakId) return null;
    if (step.relation == RouteStepRelation.relocated ||
        step.relation == RouteStepRelation.ambiguous) {
      return null;
    }
    _lastEvidencePeakId = step.peakId;
    final before = _state;

    if (step.relation == RouteStepRelation.offRoute) {
      _state = TravelDirectionState.offRoute;
      _clearEvidence();
      return _transition(before, step);
    }

    if (step.relation == RouteStepRelation.reverse) {
      if (_state == TravelDirectionState.forward ||
          _state == TravelDirectionState.offRoute) {
        _state = TravelDirectionState.reverseCandidate;
        _startEvidence(step.signedRouteDistanceM.abs());
      } else if (_state == TravelDirectionState.forwardCandidate) {
        _state = TravelDirectionState.reverseConfirmed;
        _startEvidence(step.signedRouteDistanceM.abs());
      } else {
        _addEvidence(step.signedRouteDistanceM.abs());
      }
      if (_state == TravelDirectionState.reverseCandidate &&
          _evidencePeakCount >= confirmPeakCount &&
          _evidenceDistanceM >= confirmDistanceM) {
        _state = TravelDirectionState.reverseConfirmed;
      }
    } else {
      if (_state == TravelDirectionState.reverseConfirmed) {
        _state = TravelDirectionState.forwardCandidate;
        _startEvidence(step.signedRouteDistanceM.abs());
      } else if (_state == TravelDirectionState.forwardCandidate ||
          _state == TravelDirectionState.offRoute) {
        if (_state == TravelDirectionState.offRoute) {
          _state = TravelDirectionState.forwardCandidate;
          _startEvidence(step.signedRouteDistanceM.abs());
        } else {
          _addEvidence(step.signedRouteDistanceM.abs());
        }
        if (_evidencePeakCount >= recoverPeakCount &&
            _evidenceDistanceM >= recoverDistanceM) {
          _state = TravelDirectionState.forward;
          _clearEvidence();
        }
      } else {
        _state = TravelDirectionState.forward;
        _clearEvidence();
      }
    }
    return _transition(before, step);
  }

  void _startEvidence(double distanceM) {
    _evidencePeakCount = 1;
    _evidenceDistanceM = distanceM;
  }

  void _addEvidence(double distanceM) {
    _evidencePeakCount += 1;
    _evidenceDistanceM += distanceM;
  }

  void _clearEvidence() {
    _evidencePeakCount = 0;
    _evidenceDistanceM = 0;
  }

  TravelDirectionTransition? _transition(
    TravelDirectionState before,
    RouteStepAdvance step,
  ) {
    if (before == _state) return null;
    return TravelDirectionTransition(
      from: before,
      to: _state,
      peakId: step.peakId,
      occurredAtMs: step.occurredAtMs,
      evidencePeakCount: _evidencePeakCount,
      evidenceDistanceM: _evidenceDistanceM,
    );
  }
}

double? _edgeRouteBearing(
  GraphEdge edge,
  int routeSign, {
  required Map<String, GraphNode> nodesById,
}) {
  final points = edge.geometryLocalM;
  final LocalPoint from;
  final LocalPoint to;
  if (points.length >= 2) {
    from = routeSign > 0 ? points.first : points.last;
    to = routeSign > 0 ? points.last : points.first;
  } else {
    final storedFrom = nodesById[edge.fromNodeId];
    final storedTo = nodesById[edge.toNodeId];
    if (storedFrom == null || storedTo == null) return null;
    from = routeSign > 0
        ? LocalPoint(storedFrom.xM, storedFrom.yM)
        : LocalPoint(storedTo.xM, storedTo.yM);
    to = routeSign > 0
        ? LocalPoint(storedTo.xM, storedTo.yM)
        : LocalPoint(storedFrom.xM, storedFrom.yM);
  }
  final east = to.x - from.x;
  final north = to.y - from.y;
  final bearing = math.atan2(east, north) * 180 / math.pi;
  return bearing < 0 ? bearing + 360 : bearing;
}

double _bearingError(double a, double b) {
  final delta = ((a - b + 540) % 360) - 180;
  return delta.abs();
}
