/// [FloorGraph] 하나를 받아 다익스트라로 최단 경로를 계산하고, 지도에 그릴
/// [IndoorRoute](WGS84 폴리라인 + 총 거리)로 바꾼다.
///
/// api/app/services/navigation_service.py::NavigationService.get_shortest_path의
/// 포팅이다. 서버 왕복 없이 이미 받아둔 그래프로 즉시 계산하는 게 목적이므로,
/// HTTP/Repository를 알지 못하는 순수 함수다.
library;

import 'package:latlong2/latlong.dart';

import '../models/floor_graph.dart';
import '../models/indoor_route.dart';
import 'dijkstra.dart';
import 'geo_transform.dart';

/// 두 노드 사이 최단 경로를 계산해 [IndoorRoute]로 반환한다.
/// 연결된 경로가 없으면 null. 노드 ID가 그래프에 없으면 [ArgumentError].
IndoorRoute? computeShortestRoute(
  FloorGraph graph,
  String startNodeId,
  String endNodeId,
) {
  final path = findShortestPath(
    nodes: graph.nodes,
    edges: graph.edges,
    startNodeId: startNodeId,
    endNodeId: endNodeId,
  );
  if (path == null) return null;

  final localPoints = _buildPathPoints(path, graph);
  final transform = fitFloorGeoTransform(graph.nodes);
  final wgs84Points = [
    for (final point in localPoints) transform.apply(point.x, point.y),
  ];

  return IndoorRoute(
    points: [for (final (lat, lng) in wgs84Points) LatLng(lat, lng)],
    distanceMeters: path.totalDistanceM,
  );
}

/// 최단 경로의 간선 geometry를 진행 방향에 맞춰 하나의 선으로 합친다.
List<LocalPoint> _buildPathPoints(ShortestPath path, FloorGraph graph) {
  final nodesById = {for (final node in graph.nodes) node.id: node};
  final edgesById = {for (final edge in graph.edges) edge.id: edge};

  if (path.edgeIds.isEmpty) {
    final node = nodesById[path.nodeIds.first]!;
    return [LocalPoint(node.xM, node.yM)];
  }

  final pathPoints = <LocalPoint>[];

  for (var index = 0; index < path.edgeIds.length; index++) {
    final edge = edgesById[path.edgeIds[index]]!;
    final fromNodeId = path.nodeIds[index];
    final toNodeId = path.nodeIds[index + 1];

    var geometry = edge.geometryLocalM;
    if (geometry.isEmpty) {
      final fromNode = nodesById[fromNodeId]!;
      final toNode = nodesById[toNodeId]!;
      geometry = [
        LocalPoint(fromNode.xM, fromNode.yM),
        LocalPoint(toNode.xM, toNode.yM),
      ];
    } else if (edge.fromNodeId == toNodeId && edge.toNodeId == fromNodeId) {
      // 간선을 역방향으로 지나면 좌표 순서를 뒤집어 진행 방향을 맞춘다.
      geometry = geometry.reversed.toList();
    } else if (!(edge.fromNodeId == fromNodeId && edge.toNodeId == toNodeId)) {
      throw ArgumentError(
        '간선 ${edge.id}가 경로 노드 $fromNodeId, $toNodeId와 연결되지 않습니다.',
      );
    }

    if (pathPoints.isNotEmpty &&
        pathPoints.last.x == geometry.first.x &&
        pathPoints.last.y == geometry.first.y) {
      pathPoints.addAll(geometry.skip(1));
    } else {
      pathPoints.addAll(geometry);
    }
  }

  return pathPoints;
}
