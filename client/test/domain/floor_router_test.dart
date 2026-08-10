import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/floor_router.dart';
import 'package:navigation_client/models/floor_graph.dart';

void main() {
  test('최단 경로가 edge 저장 방향과 별도로 node 진행 순서를 보존한다', () {
    const graph = FloorGraph(
      nodes: [
        GraphNode(id: 'a', type: 'path', xM: 0, yM: 0, lat: 37, lng: 127),
        GraphNode(id: 'b', type: 'path', xM: 10, yM: 0, lat: 37, lng: 127.0001),
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

    final route = computeShortestRoute(graph, 'b', 'a');

    expect(route, isNotNull);
    expect(route!.edgeIds, ['ab']);
    expect(route.nodeIds, ['b', 'a']);
    expect(route.pointsLocalM.first.x, 10);
    expect(route.pointsLocalM.last.x, 0);
  });
}
