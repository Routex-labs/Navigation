import '../models/discovery_result.dart';
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

  /// 탐색(Discovery) 질의. 백엔드 `POST /query/ai`를 호출하며, 응답 계약은
  /// [searchDestinations](DestinationResponse, 최대 1건)와 **다르다**
  /// (DiscoveryResponse — mode + 질문/선택지 + 여러 후보). 설계:
  /// docs/backend/native/conversational-discovery.md 8-2·8-3절.
  ///
  /// 백엔드가 경량 1차를 먼저 돌리고, 단일 대상으로 확정하지 못했을 때만
  /// facet 해석 + 임베딩 의미 검색으로 넘어간다. 정확한 이름은 `direct`로
  /// 즉시 오지만, **그 외 경로는 임베딩 모델 로드로 첫 호출이 수 초 걸릴 수
  /// 있다.** 호출부는 반드시 로딩 상태를 노출하고 UI를 막지 않는다.
  ///
  /// [selectedFacets]는 사용자가 이전 clarify 질문에서 고른 값이다(축 이름 →
  /// 선택한 값 목록). 서버가 대화 세션을 유지하지 않으므로(stateless), 매
  /// 요청마다 지금까지의 선택을 다시 실어 보내야 한다 — 비워 두면 첫 질문
  /// 상태로 취급된다.
  ///
  /// 반환값의 `mode`가 화면 분기의 유일한 근거다: `direct`(1건 확정)·
  /// `clarify`(질문 + 초기 후보)·`results`(다양성 보정 후보 목록)·
  /// `no_match`(빈 matches)·`degraded`(의미 검색 불가, 가능하면 matches를
  /// 함께 담아 옴). `matches` 안의 각 건은 [DiscoveryMatch.toPoiSearchResult]로
  /// 기존 [PoiSearchResult] 기반 화면에 얹을 수 있다.
  Future<DiscoveryResult> searchDestinationsAi(
    String buildingId,
    String query, {
    String? currentFloorId,
    Map<String, List<String>>? selectedFacets,
  });
}
