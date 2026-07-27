import '../models/poi_search_result.dart';

abstract class DestinationRepository {
  /// query가 비어 있으면 건물의 전체 POI 목록을 반환한다.
  ///
  /// [currentFloorId]가 주어지면 그 층 안의 결과만 반환한다. 실내 지도에서
  /// 현재 층 시설(엘리베이터·화장실 등)만 골라 보여줄 때 이 파라미터를 채워
  /// 넘긴다. null이면 예전처럼 건물 전체를 검색한다 — 야외 모드나 아직
  /// 층이 로드되지 않은 경우, 또는 사용자가 "전체 층에서 찾기"를 켠 경우.
  ///
  /// 값은 사용자에게 보이는 층 라벨(예: "B2") 또는 내부 floor id 둘 다 허용
  /// 된다 — 백엔드 query_search._load_stores가 두 형태 모두 처리한다.
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  });

  /// FAISS 하이브리드 자연어 질의. 응답 계약은 [searchDestinations]와 같지만
  /// 사전에 없는 표현("밥 먹을 곳", "애들 신발")도 의미로 찾는다.
  ///
  /// 백엔드가 경량 1차를 먼저 돌리고, 확정하지 못했을 때만 임베딩 의미 검색
  /// 2차로 넘어간다(설계: docs/backend/native/FAISS.md). 즉 정확한 이름은
  /// 즉시 오지만, **2차로 넘어가는 자연어는 임베딩 모델 로드로 첫 호출이 수 초
  /// 걸릴 수 있다.** 호출부는 반드시 로딩 상태를 노출하고 UI를 막지 않는다.
  ///
  /// 결과는 [searchDestinations]와 같은 "최대 1건" 규약이다 — 백엔드가
  /// 안내 대상 매장 1건만 확정해 주기 때문이다. 빈 리스트는 no_match,
  /// `nodeId`가 null인 1건은 ok_no_route(위치는 알지만 입구 노드가 없어 경로
  /// 안내 불가)를 뜻한다.
  Future<List<PoiSearchResult>> searchDestinationsAi(
    String buildingId,
    String query, {
    String? currentFloorId,
  });
}
