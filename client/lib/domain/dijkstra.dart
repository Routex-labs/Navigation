/// 길찾기 그래프에서 최단 경로를 계산하는 다익스트라 알고리즘.
///
/// api/app/domain/dijkstra.py의 1:1 포팅이다. 서버 왕복 없이 클라이언트가
/// 이미 받아둔 [FloorGraph](나 노드/간선 리스트)로 즉시 경로를 계산해
/// 화면 반응 속도를 올리는 데 쓴다. HTTP/Flutter를 알지 못하는 순수 함수다.
library;

import 'package:collection/collection.dart';

import '../models/floor_graph.dart';

class ShortestPath {
  const ShortestPath({
    required this.nodeIds,
    required this.edgeIds,
    required this.totalDistanceM,
    required this.totalCostM,
  });

  /// 출발 노드부터 도착 노드까지 방문하는 순서.
  final List<String> nodeIds;

  /// 위 노드들을 연결할 때 사용한 간선 순서.
  final List<String> edgeIds;

  /// 경로에 포함된 모든 간선의 **실제 거리** 합. 사용자에게 보여 주는 값이다.
  final double totalDistanceM;

  /// 탐색이 최소화한 **라우팅 비용** 합. 수직 전이가 섞이면 [totalDistanceM]과
  /// 달라진다(수단 선호를 인코딩한 튜닝값이기 때문). 표시용으로 쓰지 않는다.
  final double totalCostM;
}

typedef _Neighbor = (String nodeId, String edgeId, double costM);
typedef _QueueItem = (double cost, String nodeId);

/// 출발 노드에서 도착 노드까지 거리 합이 가장 짧은 경로를 찾는다.
///
/// 경로가 있으면 [ShortestPath], 연결된 경로가 없으면 null을 반환한다.
/// 출발/도착 노드가 없거나 간선 데이터가 올바르지 않으면 [ArgumentError]를 던진다.
ShortestPath? findShortestPath({
  required List<GraphNode> nodes,
  required List<GraphEdge> edges,
  required String startNodeId,
  required String endNodeId,
}) {
  final nodesById = {for (final node in nodes) node.id: node};

  if (!nodesById.containsKey(startNodeId)) {
    throw ArgumentError('출발 노드 $startNodeId가 존재하지 않습니다.');
  }
  if (!nodesById.containsKey(endNodeId)) {
    throw ArgumentError('도착 노드 $endNodeId가 존재하지 않습니다.');
  }

  if (startNodeId == endNodeId) {
    return ShortestPath(
      nodeIds: [startNodeId],
      edgeIds: const [],
      totalDistanceM: 0.0,
      totalCostM: 0.0,
    );
  }

  final graph = _buildGraph(nodesById, edges);
  // 경로가 정해진 뒤 실제 거리를 합산할 때 쓴다(탐색은 비용으로 하고, 표시는 거리로 한다).
  final lengthsByEdgeId = {for (final edge in edges) edge.id: edge.lengthM};

  // 출발점부터 각 노드까지 현재 발견한 최소 비용. 못 찾은 노드는 무한대로 취급한다.
  final distances = <String, double>{startNodeId: 0.0};

  // 경로 복원용 기록: 노드 ID -> (직전 노드 ID, 사용한 간선 ID)
  final previous = <String, (String, String)>{};

  // 다익스트라 표준 lazy-deletion 패턴: 같은 노드가 다른 거리로 여러 번
  // 큐에 들어갈 수 있으므로, 꺼낼 때 이미 더 짧은 거리가 기록돼 있으면 버린다.
  final queue = HeapPriorityQueue<_QueueItem>(
    (a, b) => a.$1.compareTo(b.$1),
  );
  queue.add((0.0, startNodeId));

  while (queue.isNotEmpty) {
    final (currentCost, currentNodeId) = queue.removeFirst();

    if (currentCost > (distances[currentNodeId] ?? double.infinity)) {
      continue;
    }

    if (currentNodeId == endNodeId) {
      return _restorePath(
        previous: previous,
        startNodeId: startNodeId,
        endNodeId: endNodeId,
        totalCostM: currentCost,
        lengthsByEdgeId: lengthsByEdgeId,
      );
    }

    for (final (nextNodeId, edgeId, costM)
        in graph[currentNodeId] ?? const <_Neighbor>[]) {
      final nextCost = currentCost + costM;
      if (nextCost >= (distances[nextNodeId] ?? double.infinity)) continue;

      distances[nextNodeId] = nextCost;
      previous[nextNodeId] = (currentNodeId, edgeId);
      queue.add((nextCost, nextNodeId));
    }
  }

  return null;
}

/// Edge 목록을 다익스트라가 탐색할 인접 리스트로 변환한다.
Map<String, List<_Neighbor>> _buildGraph(
  Map<String, GraphNode> nodesById,
  List<GraphEdge> edges,
) {
  final graph = <String, List<_Neighbor>>{
    for (final nodeId in nodesById.keys) nodeId: <_Neighbor>[],
  };

  for (final edge in edges) {
    if (edge.routingCostM < 0) {
      throw ArgumentError('간선 ${edge.id}의 비용은 음수일 수 없습니다.');
    }
    if (!nodesById.containsKey(edge.fromNodeId)) {
      throw ArgumentError(
        '간선 ${edge.id}가 존재하지 않는 노드 ${edge.fromNodeId}를 참조합니다.',
      );
    }
    if (!nodesById.containsKey(edge.toNodeId)) {
      throw ArgumentError(
        '간선 ${edge.id}가 존재하지 않는 노드 ${edge.toNodeId}를 참조합니다.',
      );
    }

    // 가중치는 실제 거리(lengthM)가 아니라 라우팅 비용(costM)이다. 수직 전이의
    // 수단 선호가 이 비용에만 인코딩돼 있어서, 거리로 탐색하면 층 이동 선택이 깨진다.
    graph[edge.fromNodeId]!.add((edge.toNodeId, edge.id, edge.routingCostM));
    if (edge.bidirectional) {
      graph[edge.toNodeId]!.add((edge.fromNodeId, edge.id, edge.routingCostM));
    }
  }

  return graph;
}

/// 직전 노드 기록을 도착점부터 역추적하여 정방향 경로로 복원한다.
ShortestPath _restorePath({
  required Map<String, (String, String)> previous,
  required String startNodeId,
  required String endNodeId,
  required double totalCostM,
  required Map<String, double> lengthsByEdgeId,
}) {
  final nodeIds = <String>[endNodeId];
  final edgeIds = <String>[];

  var currentNodeId = endNodeId;
  while (currentNodeId != startNodeId) {
    final (previousNodeId, edgeId) = previous[currentNodeId]!;
    nodeIds.add(previousNodeId);
    edgeIds.add(edgeId);
    currentNodeId = previousNodeId;
  }

  // 탐색은 비용으로 했으므로, 표시용 거리는 확정된 간선들의 실제 길이로 다시 더한다.
  var totalDistanceM = 0.0;
  for (final edgeId in edgeIds) {
    totalDistanceM += lengthsByEdgeId[edgeId] ?? 0.0;
  }

  return ShortestPath(
    nodeIds: nodeIds.reversed.toList(),
    edgeIds: edgeIds.reversed.toList(),
    totalDistanceM: totalDistanceM,
    totalCostM: totalCostM,
  );
}
