import 'package:latlong2/latlong.dart';

import 'poi_search_result.dart';

/// 사용자가 "장소" 탭에 저장해둔 매장 한 개.
///
/// PoiSearchResult를 그대로 저장하지 않고 별도 모델로 두는 이유는 (1) 어느
/// 건물에서 저장했는지도 함께 기억해야 하고, (2) SharedPreferences로 앱
/// 재실행 뒤에도 살아남게 JSON 직렬화가 필요하기 때문이다.
class FavoritePlace {
  const FavoritePlace({
    required this.buildingId,
    required this.name,
    required this.floor,
    required this.lat,
    required this.lng,
    this.placeId,
    this.nodeId,
    this.category,
    this.subcategory,
  });

  final String buildingId;
  final String name;
  final String floor;
  final double lat;
  final double lng;

  /// 매장 상세 조회 키(백엔드 Store.id). 이 필드가 도입되기 전에 저장된
  /// 항목은 null이고, 이름이 유일 키가 아니라 소급해서 채울 수 없다 —
  /// 상세를 못 여는 것보다 엉뚱한 매장의 상세를 여는 쪽이 나쁘다.
  /// [key]에는 절대 넣지 않는다: 키가 바뀌면 이미 저장된 항목이 전부
  /// 다른 장소로 인식돼 목록에 중복으로 쌓인다.
  final String? placeId;

  /// 매장 입구 노드 ID. 있으면 이걸로 그래프 상에서 유일하게 식별하고,
  /// 없으면(POI만 있고 노드가 없는 경우) 건물+층+이름 조합으로 식별한다.
  final String? nodeId;

  /// 매장 대분류·소분류. 카테고리 chip을 즉시 표시하려고 저장 시점의 값을
  /// 그대로 함께 캐시한다. 이 필드가 도입되기 전에 저장된 항목은 null이라
  /// 호출부에서 필요하면 실시간 매장 데이터에서 채워 넣는다.
  final String? category;
  final String? subcategory;

  /// 같은 매장을 두 번 저장하지 않기 위한 키. 노드 ID가 있으면 그걸로,
  /// 없으면 건물/층/이름 조합으로 대체한다.
  String get key => nodeId != null
      ? '$buildingId::node::$nodeId'
      : '$buildingId::$floor::$name';

  /// 원본 필드는 그대로 두고 [category]/[subcategory]만 갈아끼운 사본을 만든다.
  /// SharedPreferences에 저장된 예전 항목을 실시간 매장 데이터로 보강할 때 쓴다.
  FavoritePlace copyWithCategory({String? category, String? subcategory}) =>
      FavoritePlace(
        buildingId: buildingId,
        name: name,
        floor: floor,
        lat: lat,
        lng: lng,
        placeId: placeId,
        nodeId: nodeId,
        category: category,
        subcategory: subcategory,
      );

  PoiSearchResult toPoiSearchResult() => PoiSearchResult(
    name: name,
    floor: floor,
    point: LatLng(lat, lng),
    placeId: placeId,
    nodeId: nodeId,
    category: category,
    subcategory: subcategory,
  );

  factory FavoritePlace.fromPoiSearchResult(
    PoiSearchResult poi, {
    required String buildingId,
  }) => FavoritePlace(
    buildingId: buildingId,
    name: poi.name,
    floor: poi.floor,
    lat: poi.point.latitude,
    lng: poi.point.longitude,
    placeId: poi.placeId,
    nodeId: poi.nodeId,
    category: poi.category,
    subcategory: poi.subcategory,
  );

  Map<String, dynamic> toJson() => {
    'buildingId': buildingId,
    'name': name,
    'floor': floor,
    'lat': lat,
    'lng': lng,
    if (placeId != null) 'placeId': placeId,
    if (nodeId != null) 'nodeId': nodeId,
    if (category != null) 'category': category,
    if (subcategory != null) 'subcategory': subcategory,
  };

  factory FavoritePlace.fromJson(Map<String, dynamic> json) => FavoritePlace(
    buildingId: json['buildingId'] as String,
    name: json['name'] as String,
    floor: json['floor'] as String,
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    // 이 필드 도입 전에 저장된 항목에는 키가 없다 — null로 읽고 상세만 비운다.
    placeId: json['placeId'] as String?,
    nodeId: json['nodeId'] as String?,
    category: json['category'] as String?,
    subcategory: json['subcategory'] as String?,
  );
}
