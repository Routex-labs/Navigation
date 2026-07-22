import '../models/poi_search_result.dart';

abstract class DestinationRepository {
  /// query가 비어 있으면 건물의 전체 POI 목록을 반환한다.
  ///
  /// [currentFloorId]가 주어지면 그 층 안의 결과만 반환한다. 실내 지도에서
  /// 현재 층 시설(엘리베이터·화장실 등)만 골라 보여줄 때 이 파라미터를 채워
  /// 넘긴다. null이면 예전처럼 건물 전체를 검색한다 — 야외 모드나 아직
  /// 층이 로드되지 않은 경우, 또는 사용자가 "전체 층에서 찾기"를 켠 경우.
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  });
}
