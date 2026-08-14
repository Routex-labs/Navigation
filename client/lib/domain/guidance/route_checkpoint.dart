import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import 'corridor_tracking.dart';
import '../../models/building/floor_graph.dart';
import '../../models/route/indoor_route.dart';
import 'route_movement.dart';

enum RouteCheckpointKind { strongTurn, weakStraight }

enum RouteCheckpointDecision { candidate, commit, reject, dispute }

class RouteCheckpointWaypoint {
  const RouteCheckpointWaypoint({
    required this.nodeId,
    required this.kind,
    required this.routeDistanceM,
    required this.incomingEdgeId,
    required this.outgoingEdgeId,
  });

  final String nodeId;
  final RouteCheckpointKind kind;
  final double routeDistanceM;
  final String incomingEdgeId;
  final String outgoingEdgeId;
}

class RouteCheckpointEvent {
  const RouteCheckpointEvent({
    required this.routeGeneration,
    required this.waypoint,
    required this.decision,
    required this.reason,
    required this.peakId,
    required this.occurredAtMs,
    required this.waypointDistanceM,
  });

  final int routeGeneration;
  final RouteCheckpointWaypoint waypoint;
  final RouteCheckpointDecision decision;
  final String reason;
  final int peakId;
  final int occurredAtMs;
  final double waypointDistanceM;
}

List<RouteCheckpointWaypoint> buildRouteCheckpointWaypoints({
  required IndoorRoute route,
  required FloorGraph graph,
  double weakSpacingM = 9,
}) {
  if (route.nodeIds.length != route.edgeIds.length + 1 ||
      route.edgeIds.length < 2) {
    return const [];
  }
  final edgesById = {for (final edge in graph.edges) edge.id: edge};
  final nodesById = {for (final node in graph.nodes) node.id: node};
  final incidentCount = <String, int>{};
  for (final edge in graph.edges) {
    if (edge.transferMode != null) continue;
    incidentCount[edge.fromNodeId] = (incidentCount[edge.fromNodeId] ?? 0) + 1;
    incidentCount[edge.toNodeId] = (incidentCount[edge.toNodeId] ?? 0) + 1;
  }
  final cumulative = <double>[0];
  for (final edgeId in route.edgeIds) {
    cumulative.add(cumulative.last + (edgesById[edgeId]?.lengthM ?? 0));
  }

  final output = <RouteCheckpointWaypoint>[];
  var lastCheckpointM = 0.0;
  for (var nodeIndex = 1; nodeIndex < route.nodeIds.length - 1; nodeIndex++) {
    final incoming = edgesById[route.edgeIds[nodeIndex - 1]];
    final outgoing = edgesById[route.edgeIds[nodeIndex]];
    if (incoming == null || outgoing == null) continue;
    final nodeId = route.nodeIds[nodeIndex];
    final incomingBearing = _bearingOnRoute(
      incoming,
      route.nodeIds[nodeIndex - 1],
      nodeId,
      nodesById,
    );
    final outgoingBearing = _bearingOnRoute(
      outgoing,
      nodeId,
      route.nodeIds[nodeIndex + 1],
      nodesById,
    );
    if (incomingBearing == null || outgoingBearing == null) continue;
    final turn = _bearingError(incomingBearing, outgoingBearing);
    final routeDistanceM = cumulative[nodeIndex];
    final isStrongTurn = turn >= 35 && turn <= 150;
    final isWeakStraight =
        turn <= 20 &&
        incidentCount[nodeId] == 2 &&
        routeDistanceM - lastCheckpointM >= weakSpacingM;
    if (!isStrongTurn && !isWeakStraight) continue;
    output.add(
      RouteCheckpointWaypoint(
        nodeId: nodeId,
        kind: isStrongTurn
            ? RouteCheckpointKind.strongTurn
            : RouteCheckpointKind.weakStraight,
        routeDistanceM: routeDistanceM,
        incomingEdgeId: incoming.id,
        outgoingEdgeId: outgoing.id,
      ),
    );
    lastCheckpointM = routeDistanceM;
  }
  return List.unmodifiable(output);
}

/// 제품 위치를 바꾸지 않고 checkpoint gate와 예상 결정을 기록한다.
class RouteCheckpointShadowTracker {
  int? _routeGeneration;
  List<RouteCheckpointWaypoint> _waypoints = const [];
  Set<String> _routeEdgeIds = const {};
  int _nextIndex = 0;
  RouteCheckpointWaypoint? _pendingStrong;
  int _pendingStrongForwardPeaks = 0;
  double? _pendingStrongWaypointDistanceM;
  final List<double> _recentForwardDistances = [];

  RouteCheckpointWaypoint? get nextWaypoint =>
      _nextIndex < _waypoints.length ? _waypoints[_nextIndex] : null;

  void configure({
    required int routeGeneration,
    required IndoorRoute route,
    required FloorGraph graph,
  }) {
    if (_routeGeneration == routeGeneration) return;
    _routeGeneration = routeGeneration;
    _waypoints = buildRouteCheckpointWaypoints(route: route, graph: graph);
    _routeEdgeIds = route.edgeIds.toSet();
    _nextIndex = 0;
    _pendingStrong = null;
    _pendingStrongForwardPeaks = 0;
    _pendingStrongWaypointDistanceM = null;
    _recentForwardDistances.clear();
  }

  /// 복도 보정의 **전체 결과가 아니라 실제로 읽는 두 값만** 받는다.
  /// [trackerPreviewPosition]은 걸음이 위치를 안 실어 줬을 때의 폴백이고,
  /// [trackerState]는 게이트 판정에만 쓴다. 30개 필드짜리 결과 객체를 받으면
  /// domain이 features를 import하게 되어 계층이 거꾸로 선다.
  List<RouteCheckpointEvent> apply({
    required RouteStepAdvance step,
    required TravelDirectionState travelDirectionState,
    required PdrLocalPoint trackerPreviewPosition,
    required CorridorTrackingState trackerState,
    required FloorGraph graph,
    required bool rerouteInFlight,
  }) {
    final waypoint = nextWaypoint;
    final generation = _routeGeneration;
    if (waypoint == null || generation == null) return const [];
    final crossed = step.crossedRouteWaypointIds.contains(waypoint.nodeId);
    final waypointNode = graph.nodes
        .where((node) => node.id == waypoint.nodeId)
        .firstOrNull;
    if (waypointNode == null) return const [];
    final distanceM =
        ((step.actualMarkerPosition ?? trackerPreviewPosition) -
                PdrLocalPoint(waypointNode.xM, waypointNode.yM))
            .distance;

    final gateReason = _gateFailure(
      step: step,
      travelDirectionState: travelDirectionState,
      trackerState: trackerState,
      rerouteInFlight: rerouteInFlight,
    );
    if (gateReason != null) {
      _pendingStrong = null;
      _pendingStrongForwardPeaks = 0;
      _pendingStrongWaypointDistanceM = null;
      _recentForwardDistances.clear();
      if (!crossed) return const [];
      return [
        RouteCheckpointEvent(
          routeGeneration: generation,
          waypoint: waypoint,
          decision: RouteCheckpointDecision.reject,
          reason: gateReason,
          peakId: step.peakId,
          occurredAtMs: step.occurredAtMs,
          waypointDistanceM: distanceM,
        ),
      ];
    }

    _recentForwardDistances.add(step.signedRouteDistanceM);
    if (_recentForwardDistances.length > 4) _recentForwardDistances.removeAt(0);

    if (waypoint.kind == RouteCheckpointKind.weakStraight && crossed) {
      final monotonic =
          _recentForwardDistances.length >= 3 &&
          _recentForwardDistances.every((distance) => distance > 0);
      final decision = distanceM > 1.5
          ? RouteCheckpointDecision.dispute
          : monotonic
          ? RouteCheckpointDecision.commit
          : RouteCheckpointDecision.reject;
      final reason = distanceM > 1.5
          ? 'residualTooLarge'
          : monotonic
          ? 'shadowEligible'
          : 'insufficientMonotonicSteps';
      if (decision == RouteCheckpointDecision.commit) _nextIndex += 1;
      return [
        RouteCheckpointEvent(
          routeGeneration: generation,
          waypoint: waypoint,
          decision: decision,
          reason: reason,
          peakId: step.peakId,
          occurredAtMs: step.occurredAtMs,
          waypointDistanceM: distanceM,
        ),
      ];
    }

    if (waypoint.kind == RouteCheckpointKind.strongTurn) {
      if (crossed && _pendingStrong == null) {
        if (distanceM > 1.5) {
          return [
            RouteCheckpointEvent(
              routeGeneration: generation,
              waypoint: waypoint,
              decision: RouteCheckpointDecision.dispute,
              reason: 'residualTooLarge',
              peakId: step.peakId,
              occurredAtMs: step.occurredAtMs,
              waypointDistanceM: distanceM,
            ),
          ];
        }
        _pendingStrong = waypoint;
        _pendingStrongForwardPeaks = 1;
        _pendingStrongWaypointDistanceM = distanceM;
        return [
          RouteCheckpointEvent(
            routeGeneration: generation,
            waypoint: waypoint,
            decision: RouteCheckpointDecision.candidate,
            reason: 'awaitingOutgoingEvidence',
            peakId: step.peakId,
            occurredAtMs: step.occurredAtMs,
            waypointDistanceM: distanceM,
          ),
        ];
      }
      if (_pendingStrong?.nodeId == waypoint.nodeId) {
        if (step.optimisticEdgeId != waypoint.outgoingEdgeId) {
          final candidateDistanceM = _pendingStrongWaypointDistanceM;
          _pendingStrong = null;
          _pendingStrongForwardPeaks = 0;
          _pendingStrongWaypointDistanceM = null;
          return [
            RouteCheckpointEvent(
              routeGeneration: generation,
              waypoint: waypoint,
              decision: RouteCheckpointDecision.reject,
              reason: 'outgoingEvidenceBroken',
              peakId: step.peakId,
              occurredAtMs: step.occurredAtMs,
              waypointDistanceM: candidateDistanceM ?? distanceM,
            ),
          ];
        }
        _pendingStrongForwardPeaks += 1;
        if (_pendingStrongForwardPeaks >= 3) {
          final candidateDistanceM = _pendingStrongWaypointDistanceM;
          _pendingStrong = null;
          _pendingStrongForwardPeaks = 0;
          _pendingStrongWaypointDistanceM = null;
          _nextIndex += 1;
          return [
            RouteCheckpointEvent(
              routeGeneration: generation,
              waypoint: waypoint,
              decision: RouteCheckpointDecision.commit,
              reason: 'shadowEligible',
              peakId: step.peakId,
              occurredAtMs: step.occurredAtMs,
              waypointDistanceM: candidateDistanceM ?? distanceM,
            ),
          ];
        }
      }
    }
    return const [];
  }

  String? _gateFailure({
    required RouteStepAdvance step,
    required TravelDirectionState travelDirectionState,
    required CorridorTrackingState trackerState,
    required bool rerouteInFlight,
  }) {
    if (step.relation != RouteStepRelation.forward) return 'notForwardStep';
    if (travelDirectionState != TravelDirectionState.forward) {
      return 'travelDirectionNotForward';
    }
    if (trackerState == CorridorTrackingState.uncertain) return 'uncertain';
    if (step.optimisticEdgeId == null ||
        !_routeEdgeIds.contains(step.optimisticEdgeId)) {
      return 'optimisticEdgeOffRoute';
    }
    if (step.previewIsAmbiguous) return 'ambiguousPreview';
    if (rerouteInFlight) return 'rerouteInFlight';
    return null;
  }
}

double? _bearingOnRoute(
  GraphEdge edge,
  String fromNodeId,
  String toNodeId,
  Map<String, GraphNode> nodesById,
) {
  var geometry = edge.geometryLocalM;
  if (geometry.length < 2) {
    final from = nodesById[fromNodeId];
    final to = nodesById[toNodeId];
    if (from == null || to == null) return null;
    geometry = [LocalPoint(from.xM, from.yM), LocalPoint(to.xM, to.yM)];
  }
  if (edge.fromNodeId == toNodeId && edge.toNodeId == fromNodeId) {
    geometry = geometry.reversed.toList(growable: false);
  } else if (edge.fromNodeId != fromNodeId || edge.toNodeId != toNodeId) {
    return null;
  }
  final from = geometry.first;
  final to = geometry.last;
  final value = math.atan2(to.x - from.x, to.y - from.y) * 180 / math.pi;
  return value < 0 ? value + 360 : value;
}

double _bearingError(double a, double b) {
  final delta = ((a - b + 540) % 360) - 180;
  return delta.abs();
}
