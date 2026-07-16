import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import '../domain/floor_router.dart';
import '../models/building.dart';
import '../models/floor_graph.dart';
import '../models/indoor_route.dart';
import 'building_repository.dart';

/// api/app/routers/buildings.py의 /buildings 엔드포인트를 그대로 호출한다.
///
/// 건물/층 데이터는 자주 안 바뀌므로 한 번 받아온 응답은 메모리에 캐싱해서
/// 같은 건물·같은 층을 다시 요청할 때 네트워크를 다시 타지 않는다.
class HttpBuildingRepository implements BuildingRepository {
  HttpBuildingRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  List<Building>? _allBuildingsCache;
  final Map<String, Building> _buildingCache = {};
  final Map<String, Map<String, dynamic>> _floorGeoJsonCache = {};
  final Map<String, FloorGraph> _floorGraphCache = {};
  final Map<String, IndoorRoute> _routeCache = {};

  @override
  Future<List<Building>> getAllBuildings() async {
    final cached = _allBuildingsCache;
    if (cached != null) return cached;

    final response = await _client.get(Uri.parse('$apiBaseUrl/buildings'));
    final list = jsonDecode(response.body) as List<dynamic>;
    final buildings = list
        .map((item) => Building.fromJson(item as Map<String, dynamic>))
        .toList();

    _allBuildingsCache = buildings;
    for (final building in buildings) {
      _buildingCache[building.id] = building;
    }
    return buildings;
  }

  @override
  Future<Building?> getBuilding(String buildingId) async {
    final cached = _buildingCache[buildingId];
    if (cached != null) return cached;

    final response = await _client.get(
      Uri.parse('$apiBaseUrl/buildings/$buildingId'),
    );
    if (response.statusCode == 404) return null;

    final building = Building.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    _buildingCache[buildingId] = building;
    return building;
  }

  @override
  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  ) async {
    final cacheKey = '$buildingId/$floor';
    final cached = _floorGeoJsonCache[cacheKey];
    if (cached != null) return cached;

    final response = await _client.get(
      Uri.parse('$apiBaseUrl/buildings/$buildingId/floors/$floor'),
    );
    if (response.statusCode == 404) return null;

    final geojson = jsonDecode(response.body) as Map<String, dynamic>;
    final navigationGraph = geojson['navigation_graph'] as Map<String, dynamic>?;

    // /floors/{floor}는 매장 폴리곤이 없는(점 정보만 있는) 건물에서는 지도가
    // 텅 비어 보인다. 응답에 함께 내려오는 navigation_graph의 간선 geometry를
    // 복도선으로 얹어서 FloorPlan._fromApiResponse가 그대로 그릴 수 있게 한다.
    final corridors = _corridorsFromNavigationGraph(navigationGraph);
    if (corridors != null) geojson['corridors_local_m'] = corridors;

    // navigation_graph가 이 응답에 이미 포함돼 있으므로, 최단 경로 계산용
    // nodes/edges도 여기서 함께 캐싱해둔다 — getShortestRoute가 별도로
    // /floors/{floor}/graph를 다시 호출하지 않게 하기 위함이다.
    if (navigationGraph != null) {
      _floorGraphCache[cacheKey] = FloorGraph.fromJson(navigationGraph);
    }

    _floorGeoJsonCache[cacheKey] = geojson;
    return geojson;
  }

  List<List<dynamic>>? _corridorsFromNavigationGraph(
    Map<String, dynamic>? navigationGraph,
  ) {
    if (navigationGraph == null) return null;

    final edges = (navigationGraph['edges'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return edges
        .map((edge) => edge['geometry_local_m'] as List<dynamic>? ?? const [])
        .where((points) => points.length >= 2)
        .toList();
  }

  @override
  Future<IndoorRoute?> getShortestRoute(
    String buildingId,
    String floor,
    String startNodeId,
    String endNodeId,
  ) async {
    final cacheKey = '$buildingId/$floor/$startNodeId/$endNodeId';
    final cached = _routeCache[cacheKey];
    if (cached != null) return cached;

    // 다익스트라 입력(nodes+edges)은 별도 /graph 엔드포인트가 아니라
    // /floors/{floor} 응답의 navigation_graph에서만 얻는다. 아직 그 응답을
    // 받은 적이 없으면(캐시 미스) getFloorGeoJson이 한 번 받아와 채워준다 —
    // 이미 캐시돼 있으면 getFloorGeoJson 자체가 네트워크를 타지 않는다.
    final graphCacheKey = '$buildingId/$floor';
    var graph = _floorGraphCache[graphCacheKey];
    if (graph == null) {
      await getFloorGeoJson(buildingId, floor);
      graph = _floorGraphCache[graphCacheKey];
    }
    if (graph == null) return null;

    // 다익스트라는 그래프에 없는 노드 ID를 ArgumentError로 거부한다(백엔드가
    // 이 경우를 400으로 응답하던 것과 동일하게 "경로 없음"으로 단순화한다).
    IndoorRoute? route;
    try {
      route = computeShortestRoute(graph, startNodeId, endNodeId);
    } on ArgumentError {
      return null;
    }
    if (route == null) return null;

    _routeCache[cacheKey] = route;
    return route;
  }
}
