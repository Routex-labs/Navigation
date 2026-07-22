import '../models/floor_plan.dart';
import '../models/poi_search_result.dart';
import 'building_repository.dart';
import 'destination_repository.dart';

/// BuildingRepository가 층별로 제공하는 GeoJSON에서 POI를 모아 이름으로 검색한다.
/// 실제 자연어 검색(RAG)이 준비되면 [HttpDestinationRepository]로 교체한다.
class MockDestinationRepository implements DestinationRepository {
  MockDestinationRepository(this._buildingRepository);

  final BuildingRepository _buildingRepository;

  @override
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) async {
    final building = await _buildingRepository.getBuilding(buildingId);
    if (building == null) return [];

    // currentFloorId가 주어지면 그 층만 로드해서 훑는다 — 화장실/엘리베이터처럼
    // 층마다 같은 이름이 여러 개 있는 시설을 다른 층 결과와 섞어 내보내지
    // 않기 위해서. 값이 실제 이 건물의 층 목록에 있을 때만 필터로 취급하고,
    // 없으면(층 이름이 바뀌었거나 아직 로드 전인 경우) 안전하게 전체 검색으로
    // 폴백해서 기존 흐름을 깨뜨리지 않는다.
    final floorsToScan = (currentFloorId != null &&
            building.floors.contains(currentFloorId))
        ? [currentFloorId]
        : building.floors;

    final results = <PoiSearchResult>[];
    for (final floor in floorsToScan) {
      final geojson = await _buildingRepository.getFloorGeoJson(
        buildingId,
        floor,
      );
      if (geojson == null) continue;

      final floorPlan = FloorPlan.fromJson(geojson);
      for (final store in floorPlan.stores) {
        results.add(
          PoiSearchResult(
            name: store.name,
            floor: floor,
            point: store.centroid,
            nodeId: store.entranceNodeId,
          ),
        );
      }
      for (final poi in floorPlan.pois) {
        results.add(
          PoiSearchResult(name: poi.name, floor: floor, point: poi.point),
        );
      }
    }

    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return results;

    return results
        .where((poi) => poi.name.toLowerCase().contains(normalizedQuery))
        .toList();
  }
}
