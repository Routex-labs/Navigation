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

/// 중간층 보행에 매기는 가중치.
///
/// 거리 합만 최소화하면 "중간층을 가로질러 다른 에스컬레이터로 갈아타기"와
/// "목적층에서 걷기"가 같은 값이 된다. 사람에게는 전혀 같지 않다 — 중간층 보행은
/// 목적지로 가는 진척이 아니고, 그 층에서 다음 기기를 다시 찾아야 하며, 층 전환
/// 감지가 흔들릴 구간도 늘어난다. 그래서 **출발층도 목적층도 아닌 층**의 보행만
/// 이 배수로 비싸게 매겨, 걸어야 할 거리를 사용자가 이미 서 있는 출발층으로 옮긴다.
///
/// 실측(현대 서울, B1 출발): 이 값이 1.0이면 B1→2F가 1F를 69.6m 가로질러 뱅크를
/// 갈아탔다. 1.3~2.0 구간은 모두 "처음부터 같은 뱅크를 타고 직행"을 고르며(중간층
/// 보행 2.0m), 대가는 실거리 +10.6m다. 안정 구간의 가운데를 취한다.
///
/// 선택에만 쓰는 값이다 — ETA·남은거리는 아래에서 원본 `length_m`으로 계산한다.
const double kIntermediateFloorWalkPenalty = 1.5;

/// 두 노드 사이 층 간 최단 경로를 계산한다. 경로가 없거나 층 매핑이 부족해
/// 세그먼트를 만들 수 없으면 null.
MultiFloorRoute? computeMultiFloorRoute(
  BuildingGraph graph,
  String startNodeId,
  String endNodeId,
) {
  // 노드·간선 조회 맵은 경로 선택과 세그먼트 조립이 함께 쓴다. 각자 만들면
  // 2천 개 넘는 목록을 여러 번 훑게 된다.
  final nodesById = {for (final node in graph.nodes) node.id: node};
  final edgesById = {for (final edge in graph.edges) edge.id: edge};

  final ShortestPath? path;
  try {
    path = _selectPath(graph, nodesById, edgesById, startNodeId, endNodeId);
  } on ArgumentError {
    return null;
  }
  if (path == null) return null;

  // 층별 노드 목록 → 층별 좌표 변환. 층마다 앵커 노드가 달라 서버가 층별로
  // 피팅하는 것과 같은 결과를 얻으려면 여기서도 층별로 나눠 피팅해야 한다.
  // 피팅은 **경로가 실제로 지나는 층만** 한다(12개 층 전부 피팅할 이유가 없다).
  final nodesByFloor = <String, List<GraphNode>>{};
  for (final node in graph.nodes) {
    final floorId = node.floorId;
    if (floorId == null) continue;
    nodesByFloor.putIfAbsent(floorId, () => <GraphNode>[]).add(node);
  }
  final transformByFloor = <String, AffineTransform>{};
  AffineTransform? transformFor(String floorId) {
    final nodes = nodesByFloor[floorId];
    if (nodes == null) return null;
    return transformByFloor.putIfAbsent(
      floorId,
      () => fitFloorGeoTransform(nodes),
    );
  }

  final segments = <_PendingSegment>[];
  _PendingSegment? current;
  // 표시용 실거리 합과, 소요 시간 추정용 비용 합을 따로 센다.
  var totalDistance = 0.0;
  var totalCost = 0.0;

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
      current.transferCostM = edge.routingCostM;
      current.transferFromNode = fromNode;
      current.transferToNode = toNode;
      segments.add(current);
      totalDistance += current.distanceM + edge.lengthM;
      totalCost += current.distanceM + edge.routingCostM;
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
    totalCost += current.distanceM;
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
    final transform = transformFor(segment.floorId);
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
        : transformFor(transferTo!.floorId!);
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
        transferCostMeters: segment.transferCostM,
      ),
    );
  }

  return MultiFloorRoute(
    segments: built,
    totalDistanceMeters: totalDistance,
    totalCostMeters: totalCost,
  );
}

/// 경로를 고른다. 중간층 보행 가중치는 **수단 선택을 바꾸지 않는 선에서만** 쓴다.
///
/// 가중치를 무조건 적용하면 엘리베이터 경로의 환승 보행(샤프트가 전 층을 서비스하지
/// 않아 중간층에서 갈아타는 구간)까지 비싸져, 긴 이동이 에스컬레이터 연속 탑승으로
/// 뒤집힌다. 실측에서 200쌍 중 13건이 그렇게 바뀌었고 전부 4~9홉짜리였다
/// (예: 6F→B4가 엘리베이터 3회 → 에스컬레이터 9회). 층수에 따른 수단 선택은
/// 백엔드 비용 상수(ESCALATOR_HOP_M·ELEVATOR_BOARD_M)의 소관이고, 이 가중치가
/// 뒤집을 문제가 아니다.
///
/// 그래서 원본 가중치 경로가 엘리베이터를 쓰면 그대로 두고, 에스컬레이터만 쓰는
/// 경로일 때만 가중치를 적용하며, 그 결과가 엘리베이터를 끌어들이면 되돌린다.
/// 이 규칙으로 같은 200쌍에서 수단이 바뀐 경로는 0건이 된다.
ShortestPath? _selectPath(
  BuildingGraph graph,
  Map<String, GraphNode> nodesById,
  Map<String, GraphEdge> edgesById,
  String startNodeId,
  String endNodeId,
) {
  ShortestPath? solve({double Function(GraphEdge edge)? weight}) =>
      findShortestPath(
        nodes: graph.nodes,
        edges: graph.edges,
        startNodeId: startNodeId,
        endNodeId: endNodeId,
        weight: weight,
      );
  bool usesElevator(ShortestPath path) => path.edgeIds.any(
    (id) => edgesById[id]?.transferMode == 'elevator',
  );

  final raw = solve();
  if (raw == null || usesElevator(raw)) return raw;

  final penalize = _intermediateFloorWeight(
    nodesById,
    startNodeId,
    endNodeId,
  );
  if (penalize == null) return raw;
  final weighted = solve(weight: penalize);
  if (weighted == null || usesElevator(weighted)) return raw;
  return weighted;
}

/// 중간층 보행에 가중치를 매기는 함수. 가중할 대상이 없으면 null.
///
/// 어느 층이 중간층인지는 경로를 풀기 전에 알 수 있다 — 출발/목적 노드의 층이
/// 아닌 모든 층이다. 그래서 상태 확장이나 k-최단경로 없이, 같은 다익스트라에
/// 가중치 함수만 넘기면 된다. 수직 전이 간선은 건드리지 않는다(수단 선택 교차점은
/// 백엔드 비용 상수가 정한다).
double Function(GraphEdge edge)? _intermediateFloorWeight(
  Map<String, GraphNode> nodesById,
  String startNodeId,
  String endNodeId,
) {
  if (kIntermediateFloorWalkPenalty == 1.0) return null;
  final startFloorId = nodesById[startNodeId]?.floorId;
  final endFloorId = nodesById[endNodeId]?.floorId;
  // 같은 층 안의 경로면 중간층이 없다 — 가중할 대상도 없다.
  if (startFloorId == null ||
      endFloorId == null ||
      startFloorId == endFloorId) {
    return null;
  }
  return (edge) {
    if (edge.transferMode != null) return edge.routingCostM;
    final floorId =
        nodesById[edge.fromNodeId]?.floorId ?? nodesById[edge.toNodeId]?.floorId;
    if (floorId == null || floorId == startFloorId || floorId == endFloorId) {
      return edge.routingCostM;
    }
    return edge.routingCostM * kIntermediateFloorWalkPenalty;
  };
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
  double transferCostM = 0.0;
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
