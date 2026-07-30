/// 건물 전체 그래프에서 두 노드 사이 최단 경로를 찾고, 층별 세그먼트로
/// 나누어 [MultiFloorRoute]로 반환한다.
///
/// 층 내부 간선은 [floor_router.dart]와 동일한 규칙으로 폴리라인을 이어붙이고,
/// 수직 전이 간선(elevator/escalator)은 세그먼트를 끊는 경계로만 쓴다 —
/// 실제 이동 폴리라인에는 포함하지 않는다(엘리베이터 안까지 선을 그리지 않음).
library;

import 'package:latlong2/latlong.dart';

import '../models/building_graph.dart';
import '../models/floor_graph.dart';
import '../models/indoor_route.dart';
import 'dijkstra.dart';
import 'geo_transform.dart';

/// 두 노드 사이 층 간 최단 경로를 계산한다. 경로가 없거나 층 매핑이 부족해
/// 세그먼트를 만들 수 없으면 null.
MultiFloorRoute? computeMultiFloorRoute(
  BuildingGraph graph,
  String startNodeId,
  String endNodeId,
) {
  final ShortestPath? path;
  try {
    path = findShortestPath(
      nodes: graph.nodes,
      edges: graph.edges,
      startNodeId: startNodeId,
      endNodeId: endNodeId,
    );
  } on ArgumentError {
    return null;
  }
  if (path == null) return null;

  final nodesById = {for (final node in graph.nodes) node.id: node};
  final edgesById = {for (final edge in graph.edges) edge.id: edge};

  // 층별 노드 목록 → 층별 좌표 변환. 층마다 앵커 노드가 달라 서버가 층별로
  // 피팅하는 것과 같은 결과를 얻으려면 여기서도 층별로 나눠 피팅해야 한다.
  final nodesByFloor = <String, List<GraphNode>>{};
  for (final node in graph.nodes) {
    final floorId = node.floorId;
    if (floorId == null) continue;
    nodesByFloor.putIfAbsent(floorId, () => <GraphNode>[]).add(node);
  }
  final transformByFloor = <String, AffineTransform>{
    for (final entry in nodesByFloor.entries)
      entry.key: fitFloorGeoTransform(entry.value),
  };

  final segments = <_PendingSegment>[];
  _PendingSegment? current;
  var totalDistance = 0.0;

  for (var index = 0; index < path.edgeIds.length; index++) {
    final edge = edgesById[path.edgeIds[index]]!;
    final fromNodeId = path.nodeIds[index];
    final toNodeId = path.nodeIds[index + 1];
    final fromNode = nodesById[fromNodeId]!;
    final toNode = nodesById[toNodeId]!;

    if (edge.transferMode != null) {
      // 수직 전이 간선: 현재 세그먼트를 닫고, 이 간선을 다음 세그먼트로
      // 갈아탈 수단으로 기록한다. 전이 노드가 겹치는 지점(엘리베이터 홀)은
      // 두 세그먼트 각각의 끝/시작에 그대로 남는다.
      current ??= _PendingSegment(fromNode.floorId!);
      current.addNode(fromNode);
      current.transferModeToNext = edge.transferMode;
      current.transferDistanceM = edge.lengthM;
      current.transferFromNode = fromNode;
      current.transferToNode = toNode;
      segments.add(current);
      totalDistance += current.distanceM + edge.lengthM;
      current = _PendingSegment(toNode.floorId!)..addNode(toNode);
      continue;
    }

    // 층 내부 간선: 현재 세그먼트에 이 간선의 geometry를 방향에 맞춰 이어붙인다.
    final floorId = fromNode.floorId ?? toNode.floorId;
    if (floorId == null) return null;
    current ??= _PendingSegment(floorId)..addNode(fromNode);

    var geometry = edge.geometryLocalM;
    if (geometry.isEmpty) {
      geometry = [
        LocalPoint(fromNode.xM, fromNode.yM),
        LocalPoint(toNode.xM, toNode.yM),
      ];
    } else if (edge.fromNodeId == toNodeId && edge.toNodeId == fromNodeId) {
      geometry = geometry.reversed.toList();
    }
    current.addGeometry(geometry, edge.lengthM, edge.id);
  }

  if (current != null) {
    segments.add(current);
    totalDistance += current.distanceM;
  } else if (path.edgeIds.isEmpty) {
    // 시작=도착 노드인 특수 케이스. 지도에 그릴 게 없다.
    final node = nodesById[path.nodeIds.first]!;
    final floorId = node.floorId;
    if (floorId == null) return null;
    current = _PendingSegment(floorId)..addNode(node);
    segments.add(current);
  }

  final built = <IndoorRouteSegment>[];
  for (final segment in segments) {
    final transform = transformByFloor[segment.floorId];
    if (transform == null) return null;
    final floorName = graph.floorNamesById[segment.floorId];
    if (floorName == null) return null;
    final points = <LatLng>[
      for (final point in segment.points) _apply(transform, point.x, point.y),
    ];
    final transferFrom = segment.transferFromNode;
    final transferTo = segment.transferToNode;
    final transferToTransform = transferTo?.floorId == null
        ? null
        : transformByFloor[transferTo!.floorId!];
    final transferPoints =
        transferFrom == null ||
            transferTo == null ||
            transferToTransform == null
        ? const <LatLng>[]
        : <LatLng>[
            _apply(transform, transferFrom.xM, transferFrom.yM),
            _apply(transferToTransform, transferTo.xM, transferTo.yM),
          ];
    built.add(
      IndoorRouteSegment(
        floorId: segment.floorId,
        floorName: floorName,
        route: IndoorRoute(
          points: points,
          distanceMeters: segment.distanceM,
          // 세그먼트 폴리라인·간선은 그 층 안에서만 이어진다. 진행률은 층별
          // 세그먼트 단위로 계산하고, 남은 거리는 화면이 이후 세그먼트 길이를
          // 더해 합산한다.
          pointsLocalM: segment.points,
          edgeIds: segment.edgeIds,
        ),
        transferModeToNext: segment.transferModeToNext,
        transferPointsToNext: transferPoints,
        transferDistanceMeters: segment.transferDistanceM,
      ),
    );
  }

  return MultiFloorRoute(segments: built, totalDistanceMeters: totalDistance);
}

LatLng _apply(AffineTransform transform, double xM, double yM) {
  final (lat, lng) = transform.apply(xM, yM);
  return LatLng(lat, lng);
}

/// 세그먼트를 조립하는 중간 상태. 마지막에 좌표 변환을 태워 [IndoorRouteSegment]
/// 로 굳는다.
class _PendingSegment {
  _PendingSegment(this.floorId);

  final String floorId;
  final List<LocalPoint> points = <LocalPoint>[];

  /// 이 세그먼트가 지나는 층 내부 간선 id. 수직 전이 간선은 세그먼트 경계일
  /// 뿐 이동 폴리라인에 포함되지 않으므로 여기에도 넣지 않는다.
  final List<String> edgeIds = <String>[];
  double distanceM = 0.0;
  String? transferModeToNext;
  double transferDistanceM = 0.0;
  GraphNode? transferFromNode;
  GraphNode? transferToNode;

  void addNode(GraphNode node) {
    if (points.isNotEmpty &&
        points.last.x == node.xM &&
        points.last.y == node.yM) {
      return;
    }
    points.add(LocalPoint(node.xM, node.yM));
  }

  void addGeometry(
    List<LocalPoint> geometry,
    double edgeLengthM,
    String edgeId,
  ) {
    if (geometry.isEmpty) return;
    edgeIds.add(edgeId);
    if (points.isNotEmpty &&
        points.last.x == geometry.first.x &&
        points.last.y == geometry.first.y) {
      points.addAll(geometry.skip(1));
    } else {
      points.addAll(geometry);
    }
    distanceM += edgeLengthM;
  }
}
