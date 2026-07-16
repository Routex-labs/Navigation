/// api/app/schemas/route.py의 FloorGraphResponse를 파싱한 결과.
/// GET /buildings/{id}/floors/{floor} 응답의 navigation_graph 필드이며,
/// 클라이언트가 직접 다익스트라를 돌릴 때 쓰는 nodes/edges 원본이다.
class LocalPoint {
  const LocalPoint(this.x, this.y);

  final double x;
  final double y;

  factory LocalPoint.fromJson(Map<String, dynamic> json) => LocalPoint(
    (json['x'] as num).toDouble(),
    (json['y'] as num).toDouble(),
  );
}

class GraphNode {
  const GraphNode({
    required this.id,
    required this.type,
    this.name,
    required this.xM,
    required this.yM,
    this.lat,
    this.lng,
  });

  final String id;
  final String type;
  final String? name;
  final double xM;
  final double yM;

  /// 건물에 실측 wgs84 앵커가 없으면 null.
  final double? lat;
  final double? lng;

  factory GraphNode.fromJson(Map<String, dynamic> json) => GraphNode(
    id: json['id'] as String,
    type: json['type'] as String,
    name: json['name'] as String?,
    xM: (json['x_m'] as num).toDouble(),
    yM: (json['y_m'] as num).toDouble(),
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
  );
}

class GraphEdge {
  const GraphEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.lengthM,
    required this.bidirectional,
    required this.geometryLocalM,
  });

  final String id;
  final String fromNodeId;
  final String toNodeId;
  final double lengthM;
  final bool bidirectional;

  /// fromNodeId -> toNodeId 진행 방향의 폴리라인. 비어 있으면 두 노드를
  /// 직선으로 잇는다(백엔드 NavigationService._build_path_points와 동일 규칙).
  final List<LocalPoint> geometryLocalM;

  factory GraphEdge.fromJson(Map<String, dynamic> json) => GraphEdge(
    id: json['id'] as String,
    fromNodeId: json['from'] as String,
    toNodeId: json['to'] as String,
    lengthM: (json['length_m'] as num).toDouble(),
    bidirectional: json['bidirectional'] as bool,
    geometryLocalM: ((json['geometry_local_m'] as List<dynamic>?) ?? const [])
        .map((point) => LocalPoint.fromJson(point as Map<String, dynamic>))
        .toList(),
  );
}

class FloorGraph {
  const FloorGraph({required this.nodes, required this.edges});

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  factory FloorGraph.fromJson(Map<String, dynamic> json) => FloorGraph(
    nodes: ((json['nodes'] as List<dynamic>?) ?? const [])
        .map((node) => GraphNode.fromJson(node as Map<String, dynamic>))
        .toList(),
    edges: ((json['edges'] as List<dynamic>?) ?? const [])
        .map((edge) => GraphEdge.fromJson(edge as Map<String, dynamic>))
        .toList(),
  );
}
