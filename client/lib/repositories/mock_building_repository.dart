import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';

import '../models/building.dart';
import '../models/floor_plan.dart';
import '../models/indoor_route.dart';
import 'building_repository.dart';

/// api/app/data/sample_building.json과 동일한 형태를 assets/mock/sample_building.json에
/// 미러링해두고 읽는다. 백엔드가 준비되면 [HttpBuildingRepository]로 교체한다.
class MockBuildingRepository implements BuildingRepository {
  MockBuildingRepository({
    this.assetPath = 'assets/mock/sample_building.json',
  });

  final String assetPath;
  Map<String, dynamic>? _cache;

  Future<Map<String, dynamic>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _cache = decoded;
    return decoded;
  }

  @override
  Future<List<Building>> getAllBuildings() async {
    final data = await _load();
    return [Building.fromJson(data)];
  }

  @override
  Future<Building?> getBuilding(String buildingId) async {
    final data = await _load();
    if (data['id'] != buildingId) return null;
    return Building.fromJson(data);
  }

  @override
  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  ) async {
    final data = await _load();
    if (data['id'] != buildingId) return null;
    final floorData = data['floor_data'] as Map<String, dynamic>;
    final geojson = floorData[floor];
    return geojson == null ? null : geojson as Map<String, dynamic>;
  }

  @override
  Future<IndoorRoute?> getShortestRoute(
    String buildingId,
    String floor,
    String startNodeId,
    String endNodeId,
  ) async {
    // mock 데이터엔 그래프가 없다. 매장의 entranceNodeId로 두 지점을 찾아
    // 직선으로 잇는 정도로만 흉내 낸다 (실제 다익스트라 그래프는 백엔드에서만 존재).
    final geojson = await getFloorGeoJson(buildingId, floor);
    if (geojson == null) return null;

    final floorPlan = FloorPlan.fromJson(geojson);
    final start = _findEntrance(floorPlan, startNodeId);
    final end = _findEntrance(floorPlan, endNodeId);
    if (start == null || end == null) return null;

    return IndoorRoute(
      points: [start, end],
      distanceMeters: wgs84DistanceMeters(start, end),
    );
  }

  LatLng? _findEntrance(FloorPlan floorPlan, String nodeId) {
    for (final store in floorPlan.stores) {
      if (store.entranceNodeId == nodeId) return store.centroid;
    }
    return null;
  }
}
