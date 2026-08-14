import '../../models/place/discovery_result.dart';
import '../../models/building/floor_plan.dart';
import '../../models/place/poi_search_result.dart';
import '../building/building_repository.dart';
import 'destination_repository.dart';

/// BuildingRepository가 층별로 제공하는 GeoJSON에서 POI를 모아 이름으로 검색한다.
/// 실제 자연어 검색(RAG)이 준비되면 [HttpDestinationRepository]로 교체한다.
class MockDestinationRepository implements DestinationRepository {
  MockDestinationRepository(this._buildingRepository);

  final BuildingRepository _buildingRepository;

  /// Mock에는 임베딩 인덱스도 facet 로더도 없으므로, 이름 부분 일치 검색
  /// 결과를 최상위 1건으로 감싸 `direct`로 돌려준다. clarify·results·
  /// degraded 판정과 matched_facets/reason 조립은 재현하지 않는다 — 흉내 낸
  /// 되물음·추천 이유로 테스트를 통과시키면 실제 연동에서만 깨지는 차이가
  /// 숨는다.
  @override
  Future<DiscoveryResult> searchDestinationsAi(
    String buildingId,
    String query, {
    String? currentFloorId,
    Map<String, List<String>>? selectedFacets,
    bool showAll = false,
  }) async {
    final results = await searchDestinations(
      buildingId,
      query,
      currentFloorId: currentFloorId,
    );
    if (results.isEmpty) {
      return DiscoveryResult(mode: DiscoveryMode.noMatch, query: query);
    }
    return DiscoveryResult(
      mode: DiscoveryMode.direct,
      query: query,
      matches: [_toDiscoveryMatch(results.first)],
    );
  }

  /// Mock 데이터에는 백엔드의 store_id/floor_id 구분이 없으므로(아래 참고)
  /// 층 라벨과 이름을 이어붙인 placeholder를 쓴다. 실제 백엔드 id 형식과
  /// 다르므로 이 값 자체를 단정적으로(equality 등) 검증하는 테스트를 짜면 안 된다.
  DiscoveryMatch _toDiscoveryMatch(PoiSearchResult result) => DiscoveryMatch(
    storeId: '${result.floor}:${result.name}',
    name: result.name,
    category: result.category,
    subcategory: result.subcategory,
    floorId: result.floor,
    floorName: result.floor,
    entranceNodeId: result.nodeId,
    point: result.point,
    matchedFacets: const {},
    reason: null,
  );

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
    final floorsToScan =
        (currentFloorId != null && building.floors.contains(currentFloorId))
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
            // 층 지도 응답의 매장 id라 백엔드 Store.id와 같은 값이다 —
            // 바로 위 _toDiscoveryMatch의 합성 placeholder와 달리 실제 키다.
            placeId: store.id,
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
