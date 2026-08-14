/// 건물 전체 길찾기 그래프. api/app/dto/route.py의 BuildingGraphResponse를
/// 파싱한 결과다. 층 내부 간선 + 수직 전이 간선(elevator/escalator)이 함께
/// 담겨 있어 클라이언트가 층 간 경로까지 온디바이스 다익스트라로 계산할 수
/// 있다.
library;

import 'package:latlong2/latlong.dart';

import 'floor_graph.dart';
import 'indoor_route.dart';

class BuildingGraph {
  const BuildingGraph({
    required this.buildingId,
    required this.vertical,
    required this.floorNamesById,
    required this.nodes,
    required this.edges,
  });

  final String buildingId;

  /// 적용된 수직 이동 정책 (auto/elevator/escalator). 서버가 이 값에 맞춰
  /// 수직 전이 간선을 필터링한 결과가 [edges]에 담긴다.
  final String vertical;

  /// 내부 floor id → 사람이 보는 층 라벨(예: "B2"). 그래프 노드의 floorId를
  /// 실제 층 라벨로 되돌릴 때 쓴다.
  final Map<String, String> floorNamesById;

  /// 전 층 노드. 각 노드의 [GraphNode.floorId]로 어느 층인지 구분한다.
  final List<GraphNode> nodes;

  /// 층 내부 간선 + 수직 전이 간선. 전이 간선은
  /// [GraphEdge.transferMode]가 "elevator" 또는 "escalator"다.
  final List<GraphEdge> edges;

  factory BuildingGraph.fromJson(Map<String, dynamic> json) {
    final floorList = (json['floors'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return BuildingGraph(
      buildingId: (json['building'] as Map<String, dynamic>)['id'] as String,
      vertical: json['vertical'] as String,
      floorNamesById: {
        for (final floor in floorList)
          floor['id'] as String: floor['name'] as String,
      },
      nodes: ((json['nodes'] as List<dynamic>?) ?? const [])
          .map((node) => GraphNode.fromJson(node as Map<String, dynamic>))
          .toList(),
      edges: ((json['edges'] as List<dynamic>?) ?? const [])
          .map((edge) => GraphEdge.fromJson(edge as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 층 하나 안에서 이어지는 경로 조각. WGS84 폴리라인은 그 층의 좌표 변환으로
/// 계산된 값이라 지도 위에 그대로 그릴 수 있다. [transferModeToNext]가 있으면
/// 이 조각의 마지막 지점에서 다음 세그먼트 층으로 넘어가는 수직 이동이 붙는다.
class IndoorRouteSegment {
  const IndoorRouteSegment({
    required this.floorId,
    required this.floorName,
    required this.route,
    this.transferModeToNext,
    this.transferPointsToNext = const [],
    this.transferDistanceMeters = 0,
    this.transferCostMeters = 0,
    this.transferEdgeId,
    this.transferFromNodeId,
    this.transferToNodeId,
  });

  /// 이 세그먼트가 속한 층의 내부 id (Floor.id).
  final String floorId;

  /// 사람이 보는 층 라벨(예: "B2"). 지도가 그릴 층을 고를 때 쓰므로 이 값이
  /// [Building.floors]의 원소와 같아야 한다.
  final String floorName;

  /// 이 층 안에서 이어지는 폴리라인 + 거리. 그리기 편의를 위해 기존
  /// [IndoorRoute]와 같은 형태를 재사용한다.
  final IndoorRoute route;

  /// 이 세그먼트 마지막 지점에서 다음 세그먼트 층으로 갈아탈 때 쓸 수단.
  /// "elevator" / "escalator" / null(마지막 세그먼트).
  final String? transferModeToNext;

  /// 현재 층 탑승 노드와 다음 층 도착 노드를 WGS84로 연결한 수직 이동 표시선.
  /// 백엔드 수직 간선에는 geometry가 없으므로 두 끝점을 사용해 합성한다.
  /// 일반 보행 경로와 섞지 않아 층별 진행률 계산에는 들어가지 않는다.
  final List<LatLng> transferPointsToNext;

  /// 수직 이동의 **실제 수평 거리**(탑승구~하차구 오프셋). 에스컬레이터는 약 20m,
  /// 엘리베이터는 약 0~3m다. 남은거리 표시에 더하지만 층 내부 진행률에는 넣지 않는다.
  final double transferDistanceMeters;

  /// 수직 이동의 **경로 탐색 비용**(보행 등가 m). 탑승·대기 시간을 담고 있어
  /// 소요 시간 추정에 쓴다 — 거리 표시에는 쓰지 않는다(거리가 비용만큼 부풀어 보인다).
  final double transferCostMeters;

  /// 수직 이동에 실제로 선택된 간선과 양 끝 노드. 중앙 에스컬레이터처럼
  /// 여러 레인이 붙어 있을 때 좌표·그룹명만으로 다시 추정하지 않게 보존한다.
  final String? transferEdgeId;
  final String? transferFromNodeId;
  final String? transferToNodeId;
}

/// 층 간 경로를 층별로 나누어 담은 결과.
///
/// [totalDistanceMeters]는 전 세그먼트의 **실제 이동 거리** 합이고(ETA 카드의 "m 남음"),
/// [totalCostMeters]는 탑승·대기 비용까지 포함한 **보행 등가** 합이다(소요 시간 추정).
/// 둘을 한 값으로 겸하면 엘리베이터 경로의 남은거리가 비용만큼 부풀어 보인다.
class MultiFloorRoute {
  const MultiFloorRoute({
    required this.segments,
    required this.totalDistanceMeters,
    required this.totalCostMeters,
  });

  final List<IndoorRouteSegment> segments;
  final double totalDistanceMeters;
  final double totalCostMeters;

  bool get isEmpty => segments.isEmpty;
  bool get isNotEmpty => segments.isNotEmpty;

  IndoorRouteSegment? segmentForFloor(String floorName) {
    for (final segment in segments) {
      if (segment.floorName == floorName) return segment;
    }
    return null;
  }

  IndoorRouteSegment get destinationSegment => segments.last;
}
