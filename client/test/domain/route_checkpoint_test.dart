import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/domain/route_checkpoint.dart';
import 'package:navigation_client/domain/route_movement.dart';
import 'package:navigation_client/features/indoor_navigation/application/corridor_position_tracker.dart';
import 'package:navigation_client/models/floor_graph.dart';
import 'package:navigation_client/models/indoor_route.dart';

const _straightGraph = FloorGraph(
  nodes: [
    GraphNode(id: 'a', type: 'path', xM: 0, yM: 0),
    GraphNode(id: 'b', type: 'path', xM: 10, yM: 0),
    GraphNode(id: 'c', type: 'path', xM: 20, yM: 0),
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
    GraphEdge(
      id: 'bc',
      fromNodeId: 'b',
      toNodeId: 'c',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(10, 0), LocalPoint(20, 0)],
    ),
  ],
);

const _route = IndoorRoute(
  points: [],
  distanceMeters: 20,
  pointsLocalM: [LocalPoint(0, 0), LocalPoint(10, 0), LocalPoint(20, 0)],
  edgeIds: ['ab', 'bc'],
  nodeIds: ['a', 'b', 'c'],
);

const _turnGraph = FloorGraph(
  nodes: [
    GraphNode(id: 'a', type: 'path', xM: 0, yM: 0),
    GraphNode(id: 'b', type: 'junction', xM: 10, yM: 0),
    GraphNode(id: 'c', type: 'path', xM: 10, yM: 10),
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
    GraphEdge(
      id: 'bc',
      fromNodeId: 'b',
      toNodeId: 'c',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(10, 0), LocalPoint(10, 10)],
    ),
  ],
);

RouteStepAdvance _step(
  int peakId, {
  bool crossed = false,
  bool ambiguous = false,
  String edgeId = 'bc',
  RouteStepRelation relation = RouteStepRelation.forward,
  PdrLocalPoint? position,
}) => RouteStepAdvance(
  peakId: peakId,
  occurredAtMs: peakId,
  signedRouteDistanceM: relation == RouteStepRelation.reverse ? -0.7 : 0.7,
  relation: relation,
  crossedRouteWaypointIds: crossed ? const ['b'] : const [],
  optimisticEdgeId: edgeId,
  previewIsAmbiguous: ambiguous,
  actualMarkerPosition: position,
);

CorridorTrackingResult _result({
  PdrLocalPoint position = const PdrLocalPoint(10.3, 0),
  bool ambiguous = false,
  bool relocated = false,
}) => CorridorTrackingResult(
  state: CorridorTrackingState.straightTracking,
  correctedPosition: position,
  correctedHeadingDeg: 90,
  headingBiasDeg: 0,
  currentEdgeId: 'bc',
  currentEdgeProgressM: 0.3,
  travelDirectionSign: 1,
  pendingEdgeId: null,
  lastConfirmedNodeId: 'b',
  correctedPath: [position],
  previewPosition: position,
  previewHeadingDeg: 90,
  previewPath: [position],
  previewCandidateEdgeIds: const ['bc'],
  previewIsAmbiguous: ambiguous,
  rawConfirmedPosition: position,
  rawPreviewPosition: position,
  confirmedDisplacementM: 0,
  optimisticLeadM: 0.7,
  optimisticEdgeId: 'bc',
  optimisticEdgeProgressM: 0.3,
  previewPeakIdsSynthetic: false,
  junctionNodeId: null,
  junctionDistanceM: double.infinity,
  junctionCandidateEdgeIds: const [],
  leaderRelocated: relocated,
);

void main() {
  test('9m 이상 떨어진 degree-2 직선 node만 약한 waypoint로 만든다', () {
    final waypoints = buildRouteCheckpointWaypoints(
      route: _route,
      graph: _straightGraph,
    );

    expect(waypoints, hasLength(1));
    expect(waypoints.single.nodeId, 'b');
    expect(waypoints.single.kind, RouteCheckpointKind.weakStraight);
  });

  test('직전 세 peak가 단조 forward이고 1.5m 이내면 shadow commit한다', () {
    final tracker = RouteCheckpointShadowTracker()
      ..configure(routeGeneration: 1, route: _route, graph: _straightGraph);
    tracker.apply(
      step: _step(1),
      travelDirectionState: TravelDirectionState.forward,
      tracker: _result(),
      graph: _straightGraph,
      rerouteInFlight: false,
    );
    tracker.apply(
      step: _step(2),
      travelDirectionState: TravelDirectionState.forward,
      tracker: _result(),
      graph: _straightGraph,
      rerouteInFlight: false,
    );
    final events = tracker.apply(
      step: _step(3, crossed: true),
      travelDirectionState: TravelDirectionState.forward,
      tracker: _result(),
      graph: _straightGraph,
      rerouteInFlight: false,
    );

    expect(events.single.decision, RouteCheckpointDecision.commit);
    expect(events.single.reason, 'shadowEligible');
    expect(tracker.nextWaypoint, isNull);
  });

  test('회전점은 node 통과 뒤 outgoing 세 peak에서 shadow commit한다', () {
    final tracker = RouteCheckpointShadowTracker()
      ..configure(routeGeneration: 1, route: _route, graph: _turnGraph);

    final candidate = tracker.apply(
      step: _step(1, crossed: true),
      travelDirectionState: TravelDirectionState.forward,
      tracker: _result(),
      graph: _turnGraph,
      rerouteInFlight: false,
    );
    expect(candidate.single.decision, RouteCheckpointDecision.candidate);
    expect(
      tracker.apply(
        step: _step(2),
        travelDirectionState: TravelDirectionState.forward,
        tracker: _result(),
        graph: _turnGraph,
        rerouteInFlight: false,
      ),
      isEmpty,
    );
    final committed = tracker.apply(
      step: _step(3),
      travelDirectionState: TravelDirectionState.forward,
      tracker: _result(),
      graph: _turnGraph,
      rerouteInFlight: false,
    );

    expect(committed.single.decision, RouteCheckpointDecision.commit);
  });

  for (final state in [
    TravelDirectionState.reverseCandidate,
    TravelDirectionState.reverseConfirmed,
    TravelDirectionState.forwardCandidate,
    TravelDirectionState.offRoute,
  ]) {
    test('$state 상태에서는 waypoint를 commit하지 않는다', () {
      final tracker = RouteCheckpointShadowTracker()
        ..configure(routeGeneration: 1, route: _route, graph: _straightGraph);
      final events = tracker.apply(
        step: _step(3, crossed: true),
        travelDirectionState: state,
        tracker: _result(),
        graph: _straightGraph,
        rerouteInFlight: false,
      );

      expect(events.single.decision, RouteCheckpointDecision.reject);
      expect(events.single.reason, 'travelDirectionNotForward');
    });
  }

  test('1.5m를 넘는 약한 waypoint 오차는 dispute하고 ledger를 넘기지 않는다', () {
    final tracker = RouteCheckpointShadowTracker()
      ..configure(routeGeneration: 1, route: _route, graph: _straightGraph);
    for (var peak = 1; peak <= 2; peak++) {
      tracker.apply(
        step: _step(peak),
        travelDirectionState: TravelDirectionState.forward,
        tracker: _result(),
        graph: _straightGraph,
        rerouteInFlight: false,
      );
    }
    final events = tracker.apply(
      step: _step(3, crossed: true),
      travelDirectionState: TravelDirectionState.forward,
      tracker: _result(position: const PdrLocalPoint(12, 0)),
      graph: _straightGraph,
      rerouteInFlight: false,
    );

    expect(events.single.decision, RouteCheckpointDecision.dispute);
    expect(tracker.nextWaypoint?.nodeId, 'b');
  });

  test('peak 순간의 모호·재배치·경로 밖 증거는 checkpoint를 거부한다', () {
    for (final testCase in <(RouteStepAdvance, String)>[
      (_step(1, crossed: true, ambiguous: true), 'ambiguousPreview'),
      (
        _step(2, crossed: true, relation: RouteStepRelation.relocated),
        'notForwardStep',
      ),
      (_step(3, crossed: true, edgeId: 'outside'), 'optimisticEdgeOffRoute'),
    ]) {
      final tracker = RouteCheckpointShadowTracker()
        ..configure(routeGeneration: 1, route: _route, graph: _straightGraph);
      final events = tracker.apply(
        step: testCase.$1,
        travelDirectionState: TravelDirectionState.forward,
        tracker: _result(),
        graph: _straightGraph,
        rerouteInFlight: false,
      );
      expect(events.single.decision, RouteCheckpointDecision.reject);
      expect(events.single.reason, testCase.$2);
    }
  });

  test('강한 회전점도 통과 순간 residual이 1.5m를 넘으면 dispute한다', () {
    final tracker = RouteCheckpointShadowTracker()
      ..configure(routeGeneration: 1, route: _route, graph: _turnGraph);
    final events = tracker.apply(
      step: _step(1, crossed: true, position: const PdrLocalPoint(12, 0)),
      travelDirectionState: TravelDirectionState.forward,
      tracker: _result(),
      graph: _turnGraph,
      rerouteInFlight: false,
    );

    expect(events.single.decision, RouteCheckpointDecision.dispute);
    expect(events.single.reason, 'residualTooLarge');
    expect(tracker.nextWaypoint?.nodeId, 'b');
  });

  test('강한 회전점의 outgoing edge 증거가 끊기면 후보를 거부한다', () {
    final tracker = RouteCheckpointShadowTracker()
      ..configure(routeGeneration: 1, route: _route, graph: _turnGraph);
    tracker.apply(
      step: _step(1, crossed: true),
      travelDirectionState: TravelDirectionState.forward,
      tracker: _result(),
      graph: _turnGraph,
      rerouteInFlight: false,
    );
    final events = tracker.apply(
      step: _step(2, edgeId: 'ab'),
      travelDirectionState: TravelDirectionState.forward,
      tracker: _result(),
      graph: _turnGraph,
      rerouteInFlight: false,
    );

    expect(events.single.decision, RouteCheckpointDecision.reject);
    expect(events.single.reason, 'outgoingEvidenceBroken');
  });
}
