import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/domain/route_movement.dart';
import 'package:navigation_client/features/indoor_navigation/application/corridor_position_tracker.dart';
import 'package:navigation_client/models/floor_graph.dart';

const _graph = FloorGraph(
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
    // 저장 방향은 경로 진행 방향(b → c)과 반대다.
    GraphEdge(
      id: 'cb',
      fromNodeId: 'c',
      toNodeId: 'b',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(20, 0), LocalPoint(10, 0)],
    ),
  ],
);

OptimisticStepAdvance _optimistic({
  required int peakId,
  required List<OptimisticEdgeTraversal> traversals,
  List<String> crossed = const [],
  bool relocated = false,
}) => OptimisticStepAdvance(
  peakId: peakId,
  occurredAtMs: peakId,
  hypothesisId: 'next-$peakId',
  parentHypothesisId: 'previous-$peakId',
  distanceM: traversals.fold(0, (sum, item) => sum + item.distanceM),
  edgeId: traversals.isEmpty ? 'ab' : traversals.last.edgeId,
  mapMatchedHeadingDeg: 90,
  previewIsAmbiguous: false,
  position: const PdrLocalPoint(0, 0),
  traversals: traversals,
  crossedNodeIds: crossed,
  leaderRelocated: relocated,
);

RouteStepAdvance _routeStep(int peakId, RouteStepRelation relation) =>
    RouteStepAdvance(
      peakId: peakId,
      occurredAtMs: peakId,
      signedRouteDistanceM: relation == RouteStepRelation.reverse ? -0.7 : 0.7,
      relation: relation,
      crossedRouteWaypointIds: const [],
    );

void main() {
  group('route signed traversal', () {
    test('한 peak가 node와 반대 저장 방향 edge를 넘어도 한 보폭을 양수로 센다', () {
      final step = adaptOptimisticStepToRoute(
        step: _optimistic(
          peakId: 1000,
          traversals: const [
            OptimisticEdgeTraversal(
              edgeId: 'ab',
              fromProgressM: 9.6,
              toProgressM: 10,
            ),
            OptimisticEdgeTraversal(
              edgeId: 'cb',
              fromProgressM: 10,
              toProgressM: 9.7,
            ),
          ],
          crossed: const ['b'],
        ),
        graph: _graph,
        routeEdgeIds: const ['ab', 'cb'],
        routeNodeIds: const ['a', 'b', 'c'],
        orientationHeadingDeg: 90,
      );

      expect(step.relation, RouteStepRelation.forward);
      expect(step.signedRouteDistanceM, closeTo(0.7, 1e-9));
      expect(step.crossedRouteWaypointIds, ['b']);
    });

    test('같은 route edge를 실제로 후퇴한 traversal만 reverse다', () {
      final step = adaptOptimisticStepToRoute(
        step: _optimistic(
          peakId: 1500,
          traversals: const [
            OptimisticEdgeTraversal(
              edgeId: 'ab',
              fromProgressM: 5,
              toProgressM: 4.3,
            ),
          ],
        ),
        graph: _graph,
        routeEdgeIds: const ['ab', 'cb'],
        routeNodeIds: const ['a', 'b', 'c'],
        orientationHeadingDeg: 90,
      );

      expect(step.relation, RouteStepRelation.reverse);
      expect(step.signedRouteDistanceM, closeTo(-0.7, 1e-9));
    });

    test('leader 재배치는 traversal이 있어도 방향 증거에서 제외한다', () {
      final step = adaptOptimisticStepToRoute(
        step: _optimistic(
          peakId: 2000,
          relocated: true,
          traversals: const [
            OptimisticEdgeTraversal(
              edgeId: 'ab',
              fromProgressM: 5,
              toProgressM: 4,
            ),
          ],
        ),
        graph: _graph,
        routeEdgeIds: const ['ab', 'cb'],
        routeNodeIds: const ['a', 'b', 'c'],
      );

      expect(step.relation, RouteStepRelation.relocated);
      expect(step.signedRouteDistanceM, 0);
    });
  });

  group('travel direction state', () {
    test('heading 변화나 걸음 없는 프레임은 상태를 바꿀 입력 자체가 아니다', () {
      final tracker = TravelDirectionTracker();
      expect(tracker.state, TravelDirectionState.forward);
    });

    test('첫 역방향 peak는 candidate, 세 번째 독립 peak에서 confirmed다', () {
      final tracker = TravelDirectionTracker();

      expect(
        tracker.apply(_routeStep(1, RouteStepRelation.reverse))?.to,
        TravelDirectionState.reverseCandidate,
      );
      expect(tracker.state, TravelDirectionState.reverseCandidate);
      tracker.apply(_routeStep(2, RouteStepRelation.reverse));
      expect(tracker.state, TravelDirectionState.reverseCandidate);
      expect(
        tracker.apply(_routeStep(3, RouteStepRelation.reverse))?.to,
        TravelDirectionState.reverseConfirmed,
      );
    });

    test('confirmed 뒤 첫 정방향 peak는 candidate, 세 번째에 forward다', () {
      final tracker = TravelDirectionTracker();
      for (var peak = 1; peak <= 3; peak++) {
        tracker.apply(_routeStep(peak, RouteStepRelation.reverse));
      }

      expect(
        tracker.apply(_routeStep(4, RouteStepRelation.forward))?.to,
        TravelDirectionState.forwardCandidate,
      );
      tracker.apply(_routeStep(5, RouteStepRelation.forward));
      expect(tracker.state, TravelDirectionState.forwardCandidate);
      expect(
        tracker.apply(_routeStep(6, RouteStepRelation.forward))?.to,
        TravelDirectionState.forward,
      );
    });

    test('같은 peak ID가 반복돼도 독립 증거로 세지 않는다', () {
      final tracker = TravelDirectionTracker();
      tracker.apply(_routeStep(1, RouteStepRelation.reverse));
      tracker.apply(_routeStep(1, RouteStepRelation.reverse));
      tracker.apply(_routeStep(2, RouteStepRelation.reverse));

      expect(tracker.state, TravelDirectionState.reverseCandidate);
      expect(tracker.evidencePeakCount, 2);
    });
  });
}
