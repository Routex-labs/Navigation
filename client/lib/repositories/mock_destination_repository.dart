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
    String query,
  ) async {
    final building = await _buildingRepository.getBuilding(buildingId);
    if (building == null) return [];

    final results = <PoiSearchResult>[];
    for (final floor in building.floors) {
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
