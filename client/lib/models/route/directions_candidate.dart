import 'package:latlong2/latlong.dart';

/// 길찾기에서 고를 수 있는 출발지/도착지 후보. 야외 모드에서는 [Building],
/// 실내 모드에서는 [PoiSearchResult]를 이 공통 형태로 변환해 검색·선택
/// 로직을 한 곳에서 공유한다.
class DirectionsCandidate {
  const DirectionsCandidate({
    required this.title,
    required this.subtitle,
    required this.point,
    this.nodeId,
    this.floor,
    this.buildingId,
    this.reason,
  });

  final String title;
  final String subtitle;
  final LatLng point;

  /// 실내 경로탐색(다익스트라)에 필요한 노드 ID. 야외 후보에는 없다.
  final String? nodeId;

  /// 실내 후보가 속한 층. 야외 후보에는 없다.
  final String? floor;

  /// 이 후보가 **건물 그 자체**일 때 그 건물 id. 건물 안의 매장이면 null이다.
  ///
  /// 좌표만으로는 둘을 구분할 수 없어서 따로 둔다. 목록의 아이콘도 이 값으로
  /// 갈린다 — 건물과 매장이 같은 핀으로 보이면 무엇이 건물인지 읽을 방법이 없다.
  final String? buildingId;

  /// 건물 안의 한 지점(매장)인지. 실내 그래프로 안내할 수 있는 후보만 참이다.
  ///
  /// 층과 노드가 **둘 다** 있어야 한다. 하나만 있으면 실내 라우팅이 시작 노드나
  /// 층을 정하지 못해 "출발 위치를 먼저 지정해주세요"에서 조용히 끝난다.
  bool get isIndoorPoint => nodeId != null && floor != null;

  /// 의미 검색(`/query/ai`)이 준 추천 이유. 값이 있으면 [subtitle] 대신
  /// 보여준다 — "왜 이 매장이 나왔는지"가 층 라벨보다 중요한 정보다.
  /// 경량 검색 후보에는 없다.
  final String? reason;

  /// 같은 지점을 두 번 쌓지 않기 위한 키. [FavoritePlace.key]와 같은 규칙이다 —
  /// 노드가 있으면 그걸로, 없으면 층·이름으로 대체한다. 야외 지점은 층도 없어
  /// 좌표까지 내려간다(같은 이름의 다른 지점을 하나로 접으면 안 된다).
  String get dedupeKey {
    if (nodeId != null) return 'node::$nodeId';
    if (buildingId != null) return 'building::$buildingId';
    if (floor != null) return 'floor::$floor::$title';
    return 'point::$title::${point.latitude}::${point.longitude}';
  }

  /// 최근 출발지·목적지로 남길 때 쓴다.
  ///
  /// **[reason]은 싣지 않는다.** 그건 이번 검색어에 대한 설명이라, 다음에 목록에서
  /// 꺼냈을 때는 하지도 않은 질문의 답으로 남는다. [nodeId]·[floor]는 반드시
  /// 실어야 한다 — 둘이 살아야 다시 눌렀을 때 실내 경로가 산다([isIndoorPoint]).
  Map<String, dynamic> toJson() => {
    'title': title,
    'subtitle': subtitle,
    'lat': point.latitude,
    'lng': point.longitude,
    if (nodeId != null) 'nodeId': nodeId,
    if (floor != null) 'floor': floor,
    if (buildingId != null) 'buildingId': buildingId,
  };

  /// 저장된 한 건을 되살린다. 좌표나 제목이 깨져 있으면 null — 목록 전체를
  /// 버리지 않고 그 줄만 건너뛰기 위해서다.
  static DirectionsCandidate? fromJson(Map<String, dynamic> json) {
    final title = json['title'];
    final lat = json['lat'];
    final lng = json['lng'];
    if (title is! String || title.isEmpty) return null;
    if (lat is! num || lng is! num) return null;
    return DirectionsCandidate(
      title: title,
      subtitle: json['subtitle'] is String ? json['subtitle'] as String : '',
      point: LatLng(lat.toDouble(), lng.toDouble()),
      nodeId: json['nodeId'] as String?,
      floor: json['floor'] as String?,
      buildingId: json['buildingId'] as String?,
    );
  }
}

/// "지도에서 선택"으로 정할 대상. 출발지·도착지 양쪽 모두 지도에서 고를 수
/// 있으므로, 어느 칸을 채우려는 것인지 호출자에게 알려야 한다. bool 하나로는
/// 표현할 수 없어 열거형으로 둔다.
enum DirectionsMapPickTarget { origin, destination }

/// 길찾기 화면이 부모(MapShellScreen)에 검색을 위임할 때 쓰는 콜백.
///
/// 길찾기 검색은 **항상 건물 전체**를 뒤진다. 예전에는 현재 층으로 좁히고
/// "전체 층에서 찾기" 토글로 넓히게 했는데, 길찾기는 원래 다른 층으로 가려고
/// 여는 기능이라 기본값이 반대였다 — 찾는 매장이 대부분 다른 층에 있어서
/// 사용자가 매번 토글을 켜야 결과가 나왔다.
typedef DirectionsSearchCallback =
    Future<List<DirectionsCandidate>> Function(String query);
