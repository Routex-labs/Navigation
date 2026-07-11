import '../models/building.dart';
import '../models/indoor_route.dart';

abstract class BuildingRepository {
  Future<List<Building>> getAllBuildings();

  Future<Building?> getBuilding(String buildingId);

  Future<Map<String, dynamic>?> getFloorGeoJson(String buildingId, String floor);

  /// 두 노드 사이 최단 경로. 경로가 없거나 층/노드를 찾을 수 없으면 null.
  Future<IndoorRoute?> getShortestRoute(
    String buildingId,
    String floor,
    String startNodeId,
    String endNodeId,
  );
}
