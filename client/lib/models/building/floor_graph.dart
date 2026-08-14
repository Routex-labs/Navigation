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
    this.floorId,
  });

  final String id;
  final String type;
  final String? name;
  final double xM;
  final double yM;

  /// 건물에 실측 wgs84 앵커가 없으면 null.
  final double? lat;
  final double? lng;

  /// 건물 전체 그래프(/buildings/{id}/graph)에서만 채워진다. 전 층 노드가 한
  /// 그래프에 섞이므로 여기서 층 소속을 알 수 있어야 층별로 다시 나누거나
  /// 층별 좌표 변환을 피팅할 수 있다. 층별 그래프에서는 null.
  final String? floorId;

  factory GraphNode.fromJson(Map<String, dynamic> json) => GraphNode(
    id: json['id'] as String,
    type: json['type'] as String,
    name: json['name'] as String?,
    xM: (json['x_m'] as num).toDouble(),
    yM: (json['y_m'] as num).toDouble(),
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
    floorId: json['floor_id'] as String?,
  );
}

class GraphEdge {
  /// [costM]을 생략하면 [lengthM]과 같다고 본다 — 층 내부 간선의 정의가 그렇고,
  /// 값이 갈라지는 것은 서버가 비용을 따로 실어 주는 수직 전이 간선뿐이다.
  const GraphEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.lengthM,
    this.costM,
    required this.bidirectional,
    required this.geometryLocalM,
    this.transferMode,
    this.fromFloorId,
    this.toFloorId,
  });

  final String id;
  final String fromNodeId;
  final String toNodeId;

  /// 실제 이동 거리(m). 사용자에게 보여 주는 거리·진행률에 쓴다.
  final double lengthM;

  /// 서버가 내려준 라우팅 비용. 아직 cost_m을 주지 않는 서버·구 테스트에서는 null이다.
  /// 탐색에는 이 값 대신 [routingCostM]을 쓴다.
  final double? costM;

  /// 최단 경로 탐색이 최소화하는 가중치(m 단위). [costM]이 없으면 [lengthM]으로 폴백한다.
  ///
  /// 층 내부 간선은 [lengthM]과 같아 폴백이 곧 정답이다. 수직 전이 간선만 값이
  /// 갈라지는데, 서버가 수단 선호(에스컬레이터 vs 엘리베이터)를 인코딩한 튜닝값이기
  /// 때문이다. 이 값을 표시 거리로 쓰면 총 거리가 부풀려지므로 용도를 섞지 않는다.
  double get routingCostM => costM ?? lengthM;

  final bool bidirectional;

  /// fromNodeId -> toNodeId 진행 방향의 폴리라인. 비어 있으면 두 노드를
  /// 직선으로 잇는다(백엔드 NavigationService._build_path_points와 동일 규칙).
  final List<LocalPoint> geometryLocalM;

  /// 층 내부 간선은 null. 수직 전이 간선은 "elevator"/"escalator" 문자열이며,
  /// 이 간선을 지날 때 사용자에게 어떤 이동 수단을 안내해야 하는지의 근거다.
  final String? transferMode;

  /// 이 간선이 잇는 층. 전이 간선은 두 값이 다르고 층 내부 간선은 같다.
  ///
  /// 수직 전이의 도착 지점은 [toNodeId]와 [toFloorId]가 단일 원천이다 —
  /// 이름·그룹을 파싱해 도착 노드를 다시 고르면 서버 그래프와 어긋난다.
  final String? fromFloorId;
  final String? toFloorId;

  /// 간선 양 끝 노드 id의 키. 백엔드는 짧은 `from`/`to`로 내보내는 것이 계약이지만
  /// **필드명 그대로인 `from_node_id`/`to_node_id`로 나가는 경로가 실제로 있었다** —
  /// ETag를 뽑으려고 `model_dump_json()`을 직접 부르는 엔드포인트가 by_alias를
  /// 빠뜨리면 alias가 적용되지 않는다(`routers/buildings.py`의 get_floor_map).
  ///
  /// 그 한 글자 차이가 여기서 조용한 타입 예외(`null is not a String`)가 되고,
  /// 호출부가 예외를 삼키면 **층 도면과 그래프가 통째로 null**이 되어 층 외곽선·
  /// 카메라 fit·매장 탭·검색 포커스가 한꺼번에 죽는다. 화면에는 원인을 짚을 단서가
  /// 하나도 남지 않는다. 그래서 두 철자를 모두 받는다 — 서버를 고치더라도
  /// 배포되지 않은 구 버전에 붙는 앱이 이 하나로 전부 망가지면 안 된다.
  static String _nodeId(Map<String, dynamic> json, String short, String long) {
    final value = json[short] ?? json[long];
    if (value is String) return value;
    throw FormatException('간선에 $short/$long 키가 없다: ${json.keys.toList()}');
  }

  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    final lengthM = (json['length_m'] as num).toDouble();
    return GraphEdge(
      id: json['id'] as String,
      fromNodeId: _nodeId(json, 'from', 'from_node_id'),
      toNodeId: _nodeId(json, 'to', 'to_node_id'),
      lengthM: lengthM,
      // cost_m을 아직 안 내려주는 서버면 null로 두고, routingCostM이 lengthM으로
      // 폴백한다(층 내부 간선은 두 값이 같으므로 폴백이 곧 정답이다).
      costM: (json['cost_m'] as num?)?.toDouble(),
      bidirectional: json['bidirectional'] as bool,
      geometryLocalM: ((json['geometry_local_m'] as List<dynamic>?) ?? const [])
          .map((point) => LocalPoint.fromJson(point as Map<String, dynamic>))
          .toList(),
      transferMode: json['transfer_mode'] as String?,
      fromFloorId: json['from_floor_id'] as String?,
      toFloorId: json['to_floor_id'] as String?,
    );
  }
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
