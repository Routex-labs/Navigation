import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import '../models/building.dart';
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
    int floor,
  ) async {
    final cacheKey = '$buildingId/$floor';
    final cached = _floorGeoJsonCache[cacheKey];
    if (cached != null) return cached;

    final response = await _client.get(
      Uri.parse('$apiBaseUrl/buildings/$buildingId/floors/$floor'),
    );
    if (response.statusCode == 404) return null;

    final geojson = jsonDecode(response.body) as Map<String, dynamic>;
    _floorGeoJsonCache[cacheKey] = geojson;
    return geojson;
  }
}
