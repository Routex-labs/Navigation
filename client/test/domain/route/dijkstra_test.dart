import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/route/dijkstra.dart';
import 'package:navigation_client/models/building/floor_graph.dart';

GraphNode _node(String id) =>
    GraphNode(id: id, type: 'junction', xM: 0, yM: 0, floorId: 'f1');

// length = 실제 수평 거리, cost = 탐색 가중치. 층 내부 간선은 둘이 같고,
// 수직 전이 간선만 갈린다(20m를 걷지만 부담은 탑승 시간까지 25m 등가).
GraphEdge _edge(
  String id,
  String from,
  String to,
  double length, {
  double? cost,
}) => GraphEdge(
  id: id,
  fromNodeId: from,
  toNodeId: to,
  lengthM: length,
  costM: cost,
  bidirectional: true,
  geometryLocalM: const [],
);

void main() {
  group('reachableFrom', () {
    test('출발 노드 자신은 거리·비용 0으로 들어 있다', () {
      final reach = reachableFrom(
        nodes: [_node('a'), _node('b')],
        edges: [_edge('e1', 'a', 'b', 10)],
        startNodeId: 'a',
      );

      expect(reach['a']!.distanceM, 0);
      expect(reach['a']!.costM, 0);
    });

    test('한 번의 탐색으로 도달 가능한 모든 노드까지의 거리를 준다', () {
      final reach = reachableFrom(
        nodes: [_node('a'), _node('b'), _node('c')],
        edges: [_edge('e1', 'a', 'b', 10), _edge('e2', 'b', 'c', 5)],
        startNodeId: 'a',
      );

      expect(reach['b']!.distanceM, 10);
      expect(reach['c']!.distanceM, 15);
    });

    // 호출부가 `null` 하나로 "도달 불가"를 판정한다. 도달 못 한 노드에
    // 무한대 같은 값을 넣어 두면 목록에 그 값이 그대로 새어 나간다.
    test('간선으로 이어지지 않은 노드는 키가 아예 없다', () {
      final reach = reachableFrom(
        nodes: [_node('a'), _node('b'), _node('island')],
        edges: [_edge('e1', 'a', 'b', 10)],
        startNodeId: 'a',
      );

      expect(reach.containsKey('island'), isFalse);
    });

    test('수직 전이는 거리와 비용을 따로 누적한다', () {
      final reach = reachableFrom(
        nodes: [_node('a'), _node('lift')],
        edges: [_edge('e1', 'a', 'lift', 20, cost: 25)],
        startNodeId: 'a',
      );

      expect(reach['lift']!.distanceM, 20);
      expect(reach['lift']!.costM, 25);
    });

    // 탐색은 비용으로 하므로, 표시용 거리도 **비용이 고른 그 경로**를 따라야
    // 한다. 최단 거리 경로의 값을 따로 돌려주면 목록의 거리와 실제로 그려지는
    // 경로가 어긋난다.
    test('비용이 고른 경로의 거리를 돌려준다 — 더 짧은 경로가 있어도', () {
      final reach = reachableFrom(
        nodes: [_node('a'), _node('b')],
        edges: [
          // 길지만 싼 길(에스컬레이터처럼)과 짧지만 비싼 길.
          _edge('cheap-long', 'a', 'b', 100, cost: 5),
          _edge('dear-short', 'a', 'b', 20, cost: 50),
        ],
        startNodeId: 'a',
      );

      expect(reach['b']!.costM, 5);
      expect(reach['b']!.distanceM, 100);
    });

    // 목록에 적힌 거리와, 그 매장을 눌러 실제로 길을 찾았을 때 나오는 거리는
    // 같아야 한다. 두 함수가 갈라지면 사용자가 먼저 마주치는 것이 이 불일치다.
    test('findShortestPath와 같은 거리·비용을 준다', () {
      final nodes = [_node('a'), _node('b'), _node('c'), _node('d')];
      final edges = [
        _edge('e1', 'a', 'b', 10),
        _edge('e2', 'b', 'd', 30),
        _edge('e3', 'a', 'c', 8, cost: 12),
        _edge('e4', 'c', 'd', 8, cost: 12),
      ];

      final reach = reachableFrom(nodes: nodes, edges: edges, startNodeId: 'a');
      final path = findShortestPath(
        nodes: nodes,
        edges: edges,
        startNodeId: 'a',
        endNodeId: 'd',
      )!;

      expect(reach['d']!.distanceM, path.totalDistanceM);
      expect(reach['d']!.costM, path.totalCostM);
    });

    test('없는 출발 노드는 ArgumentError다', () {
      expect(
        () => reachableFrom(
          nodes: [_node('a')],
          edges: const [],
          startNodeId: 'nope',
        ),
        throwsArgumentError,
      );
    });
  });

  /// api/tests/unit/test_dijkstra.py의 케이스를 그대로 옮긴 것.
  group('findShortestPath', () {
    GraphNode node(String id) =>
        GraphNode(id: id, type: 'corridor', xM: 0, yM: 0);

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
      expect(path?.totalCostM, 5.0);
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
      expect(path?.totalCostM, 0.0);
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
  });
}
