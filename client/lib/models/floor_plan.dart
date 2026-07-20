import 'package:latlong2/latlong.dart';

/// 백엔드 {"lat":.., "lng":..} 좌표를 LatLng으로 바꾼다. 실내 관련 모델
/// (FloorPlan, IndoorRoute)이 전부 이 규칙을 공유해야 MapLibre 벡터 타일
/// (실좌표 기준으로 렌더링됨) 위에서 좌표가 어긋나지 않는다.
///
/// 건물에 실좌표 앵커(geo_transform)가 없으면 백엔드가 이
/// 필드를 null로 내려준다 — 이 경우 null을 그대로 반환하고 호출자가 그
/// 지점을 건너뛴다.
LatLng? wgs84PointToLatLng(Map<String, dynamic>? point) {
  if (point == null) return null;
  return LatLng((point['lat'] as num).toDouble(), (point['lng'] as num).toDouble());
}

/// 두 실좌표(WGS84) 사이의 대권 거리(m). 실내 매장은 건물 규모(수백m)라
/// 대권 거리와 평면 거리 차이가 무시할 만큼 작아 그대로 써도 된다.
double wgs84DistanceMeters(LatLng a, LatLng b) {
  return const Distance().as(LengthUnit.Meter, a, b);
}

class PoiMarker {
  const PoiMarker({required this.name, required this.point, this.type});

  final String name;
  final LatLng point;

  /// 백엔드 실데이터에서만 채워짐(예: elevator/escalator/restroom). mock GeoJSON엔 없음.
  final String? type;
}

class StorePolygon {
  const StorePolygon({
    required this.id,
    required this.name,
    required this.polygon,
    required this.centroid,
    this.entranceNodeId,
    this.category,
    this.subcategory,
  });

  /// 벡터 타일에서 탭한 매장 feature(properties.id)와 매칭하는 데 쓴다.
  final String id;
  final String name;
  final List<LatLng> polygon;
  final LatLng centroid;

  /// 경로탐색 시작/도착 노드로 쓸 매장 입구 노드 ID. 없으면 경로탐색 불가.
  final String? entranceNodeId;

  /// 매장 대분류(예: 패션/뷰티/서비스). 백엔드 실데이터에만 채워짐.
  final String? category;

  /// 매장 소분류(예: 여성패션/남성패션/컨템포러리). 백엔드 실데이터에만 채워짐.
  final String? subcategory;
}

/// 층 평면도 중 지도 위젯(MapLibre)이 직접 그리지 않는 값들 — 근처 입구
/// 찾기, 현재 위치/외곽선 중심 fallback 등 "위치 계산"용으로만 쓴다.
/// 실제 매장 폴리곤/POI/외곽선 렌더링은 벡터 타일(MVT) 소스가 대신한다.
///
/// 두 가지 소스를 모두 파싱한다:
/// - mock: api/app/data/sample_building.json과 동일한 GeoJSON FeatureCollection
/// - 백엔드: api/app/router/buildingRouter.py의 /floors/{floor} 응답
///   (footprint_wgs84/stores/pois, 진짜 WGS84 — 건물에 실좌표 앵커가 없으면 비어 있음)
class FloorPlan {
  const FloorPlan({
    this.footprint = const [],
    this.corridors = const [],
    this.stores = const [],
    required this.pois,
  });

  final List<LatLng> footprint;
  final List<List<LatLng>> corridors;
  final List<StorePolygon> stores;
  final List<PoiMarker> pois;

  /// 실내 위치 추정(PDR)이 아직 없어 실제 "현재 위치"를 모를 때 쓰는 임시
  /// 근사치. 외곽선 중심 → 복도 시작점 → 첫 POI 순으로 계산 가능한 첫 값을
  /// 쓴다. 셋 다 없으면 null(호출자가 별도 fallback을 쓴다).
  /// 실제 PDR 위치 연동이 붙으면 이 자리를 대체한다.
  LatLng? approximateCurrentLocation() {
    if (footprint.isNotEmpty) {
      final avgLat =
          footprint.map((p) => p.latitude).reduce((a, b) => a + b) / footprint.length;
      final avgLng =
          footprint.map((p) => p.longitude).reduce((a, b) => a + b) / footprint.length;
      return LatLng(avgLat, avgLng);
    }
    if (corridors.isNotEmpty && corridors.first.isNotEmpty) {
      return corridors.first.first;
    }
    if (pois.isNotEmpty) return pois.first.point;
    return null;
  }

  factory FloorPlan.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('footprint_wgs84') || json.containsKey('footprint_local_m')) {
      return _fromApiResponse(json);
    }
    return _fromGeoJson(json);
  }

  static FloorPlan _fromApiResponse(Map<String, dynamic> json) {
    final footprint = ((json['footprint_wgs84'] as List<dynamic>?) ?? const [])
        .map((point) => wgs84PointToLatLng(point as Map<String, dynamic>))
        .whereType<LatLng>()
        .toList();

    final stores = ((json['stores'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((store) {
          final centroid = wgs84PointToLatLng(
            store['centroid_wgs84'] as Map<String, dynamic>?,
          );
          // 실좌표 앵커가 없는 건물의 매장은 지도 위에 놓을 위치가 없으니 건너뛴다.
          if (centroid == null) return null;
          final polygon = ((store['polygon_wgs84'] as List<dynamic>?) ?? const [])
              .map((point) => wgs84PointToLatLng(point as Map<String, dynamic>))
              .whereType<LatLng>()
              .toList();
          return StorePolygon(
            id: store['id'] as String,
            name: store['name'] as String? ?? '',
            polygon: polygon,
            centroid: centroid,
            entranceNodeId: store['entrance_node_id'] as String?,
            category: store['category'] as String?,
            subcategory: store['subcategory'] as String?,
          );
        })
        .whereType<StorePolygon>()
        .toList();

    final pois = ((json['pois'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((poi) {
          final point = wgs84PointToLatLng(poi['position_wgs84'] as Map<String, dynamic>?);
          if (point == null) return null;
          return PoiMarker(
            name: poi['name'] as String? ?? '',
            point: point,
            type: poi['type'] as String?,
          );
        })
        .whereType<PoiMarker>()
        .toList();

    return FloorPlan(footprint: footprint, stores: stores, pois: pois);
  }

  static FloorPlan _fromGeoJson(Map<String, dynamic> geojson) {
    final corridors = <List<LatLng>>[];
    final pois = <PoiMarker>[];

    final features = (geojson['features'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();

    for (final feature in features) {
      final properties =
          (feature['properties'] as Map<String, dynamic>?) ?? const {};
      final geometry = feature['geometry'] as Map<String, dynamic>?;
      if (geometry == null) continue;

      if (properties['type'] == 'corridor') {
        final coordinates = (geometry['coordinates'] as List<dynamic>? ??
                const [])
            .map((c) => _toGeoJsonLatLng(c as List<dynamic>))
            .toList();
        corridors.add(coordinates);
      } else if (properties['type'] == 'poi') {
        final coordinate = geometry['coordinates'] as List<dynamic>;
        pois.add(
          PoiMarker(
            name: properties['name'] as String? ?? '',
            point: _toGeoJsonLatLng(coordinate),
          ),
        );
      }
    }

    return FloorPlan(corridors: corridors, pois: pois);
  }

  static LatLng _toGeoJsonLatLng(List<dynamic> coordinate) {
    // GeoJSON 좌표 순서는 [longitude, latitude]다.
    return LatLng(
      (coordinate[1] as num).toDouble(),
      (coordinate[0] as num).toDouble(),
    );
  }
}
