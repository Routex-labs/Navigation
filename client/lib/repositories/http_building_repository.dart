import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import '../models/building.dart';
import '../models/indoor_route.dart';
import 'building_repository.dart';

/// api/app/routers/buildings.py의 /buildings 엔드포인트를 그대로 호출한다.
///
/// 건물/층 데이터는 자주 안 바뀌므로 한 번 받아온 응답은 메모리에 캐싱해서
/// 같은 건물·같은 층을 다시 요청할 때 네트워크를 다시 타지 않는다.
class HttpBuildingRepository implements BuildingRepository {
  HttpBuildingRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  List<Building>? _allBuildingsCache;
  final Map<String, Building> _buildingCache = {};
  final Map<String, Map<String, dynamic>> _floorGeoJsonCache = {};
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

    // /floors/{floor}는 매장 폴리곤이 없는(점 정보만 있는) 건물에서는 지도가
    // 텅 비어 보인다. /floors/{floor}/graph의 간선 geometry를 복도선으로
    // 얹어서 FloorPlan._fromApiResponse가 그대로 그릴 수 있게 한다.
    final corridors = await _fetchCorridors(buildingId, floor);
    if (corridors != null) geojson['corridors_local_m'] = corridors;

    _floorGeoJsonCache[cacheKey] = geojson;
    return geojson;
  }

  Future<List<List<Map<String, dynamic>>>?> _fetchCorridors(
    String buildingId,
    String floor,
  ) async {
    final response = await _client.get(
      Uri.parse('$apiBaseUrl/buildings/$buildingId/floors/$floor/graph'),
    );
    if (response.statusCode != 200) return null;

    final graph = jsonDecode(response.body) as Map<String, dynamic>;
    final edges = (graph['edges'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return edges
        .map(
          (edge) => (edge['geometry_local_m'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>(),
        )
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

    final uri = Uri.parse(
      '$apiBaseUrl/buildings/$buildingId/floors/$floor/route',
    ).replace(
      queryParameters: {'start_node_id': startNodeId, 'end_node_id': endNodeId},
    );
    final response = await _client.get(uri);
    // 404(층/경로 없음)와 400(잘못된 노드 ID) 둘 다 "경로 없음"으로 단순화한다.
    if (response.statusCode == 404 || response.statusCode == 400) return null;

    final route = IndoorRoute.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    _routeCache[cacheKey] = route;
    return route;
  }
}
