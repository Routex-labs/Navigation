import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/dijkstra.dart';
import 'package:navigation_client/models/floor_graph.dart';

/// api/tests/unit/test_dijkstra.py의 케이스를 그대로 옮긴 것.
void main() {
  GraphNode node(String id) => GraphNode(id: id, type: 'corridor', xM: 0, yM: 0);

  GraphEdge edge(
    String id,
    String start,
    String end,
    double length, {
    bool bidirectional = true,
  }) => GraphEdge(
    id: id,
    fromNodeId: start,
    toNodeId: end,
    lengthM: length,
    bidirectional: bidirectional,
    geometryLocalM: const [],
  );

  test('거리 합이 가장 작은 경로를 선택한다', () {
    final path = findShortestPath(
      nodes: [node('A'), node('B'), node('C')],
      edges: [
        edge('AC', 'A', 'C', 10.0),
        edge('AB', 'A', 'B', 2.0),
        edge('BC', 'B', 'C', 3.0),
      ],
      startNodeId: 'A',
      endNodeId: 'C',
    );

    expect(path?.nodeIds, ['A', 'B', 'C']);
    expect(path?.edgeIds, ['AB', 'BC']);
    expect(path?.totalDistanceM, 5.0);
  });

  test('단방향 간선은 역방향으로 이동할 수 없다', () {
    final path = findShortestPath(
      nodes: [node('A'), node('B')],
      edges: [edge('AB', 'A', 'B', 1.0, bidirectional: false)],
      startNodeId: 'B',
      endNodeId: 'A',
    );

    expect(path, isNull);
  });

  test('출발지와 목적지가 같으면 거리는 0이다', () {
    final path = findShortestPath(
      nodes: [node('A')],
      edges: const [],
      startNodeId: 'A',
      endNodeId: 'A',
    );

    expect(path?.nodeIds, ['A']);
    expect(path?.edgeIds, isEmpty);
    expect(path?.totalDistanceM, 0.0);
  });

  test('연결되지 않은 노드는 경로가 없다', () {
    final path = findShortestPath(
      nodes: [node('A'), node('B')],
      edges: const [],
      startNodeId: 'A',
      endNodeId: 'B',
    );

    expect(path, isNull);
  });

  test('음수 가중치는 오류다', () {
    expect(
      () => findShortestPath(
        nodes: [node('A'), node('B')],
        edges: [edge('AB', 'A', 'B', -1.0)],
        startNodeId: 'A',
        endNodeId: 'B',
      ),
      throwsArgumentError,
    );
  });

  test('존재하지 않는 출발 노드는 오류다', () {
    expect(
      () => findShortestPath(
        nodes: [node('A')],
        edges: const [],
        startNodeId: 'missing',
        endNodeId: 'A',
      ),
      throwsArgumentError,
    );
  });

  test('존재하지 않는 도착 노드는 오류다', () {
    expect(
      () => findShortestPath(
        nodes: [node('A')],
        edges: const [],
        startNodeId: 'A',
        endNodeId: 'missing',
      ),
      throwsArgumentError,
    );
  });
}
