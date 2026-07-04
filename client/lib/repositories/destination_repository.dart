import '../models/poi_search_result.dart';

abstract class DestinationRepository {
  /// query가 비어 있으면 건물의 전체 POI 목록을 반환한다.
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query,
  );
}
