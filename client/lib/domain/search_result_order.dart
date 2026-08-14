/// 검색 결과를 **보행 거리** 오름차순으로 다시 세운다.
///
/// 실외 지도의 "가까운 순"은 직선거리다. 실내에서 직선거리는 자주 거짓말을
/// 한다 — 벽 하나 사이로 10m인 매장이 반대편 에스컬레이터를 돌아 120m일 수
/// 있다. 우리는 온디바이스 다익스트라가 있으므로 실제 보행 비용으로 세운다.
///
/// **여기서 경로를 새로 계산하지 않는다.** 화면은 이미 `reachableFrom`을 한 번
/// 돌려 전 노드 결과를 들고 있고(`SearchPanel.reachByNodeId`), 이 함수는 그
/// 맵을 조회만 한다. 그래서 추가 계산 비용이 0이다. 결과 수만큼 다익스트라를
/// 되돌리는 구현으로 바꾸지 마라.
///
/// 정렬을 **사용자가 고를 수 있게** 된 근거와 검증 기준은
/// `docs/client/search-result-list-ux.md` P절이, 거리순 자체의 근거는
/// `docs/client/search-input-assist.md` M절이 단일 출처다.
library;

import '../models/poi_search_result.dart';
import 'dijkstra.dart';
import 'nearest_store.dart';
import 'store_suggestions.dart';

/// 목록을 어느 축으로 세울 것인가.
///
/// **둘뿐이고, 「추천순」은 만들지 않는다.** 방문·클릭 로그가 없어 추천 순위를
/// 만들 근거가 자체가 없다(`naver-map-ui-ux-analysis.md` J절과 같은 이유).
/// 없는 걸 있는 척하는 정렬은 순위가 아니라 거짓말이다.
enum SearchSortOrder {
  /// 보행 거리 오름차순. 실외 지도의 "가까운 순"은 직선거리지만 우리는 실제
  /// 보행 비용을 쓴다.
  nearest,

  /// 매칭 품질순 — 서버·온디바이스가 준 순서를 그대로 둔다. 이름을 정확히
  /// 아는 사용자에게는 "얼마나 잘 맞는가"가 "얼마나 가까운가"보다 중요하다.
  bestMatch,
}

/// [SearchSortOrder.nearest]를 고를 수 있는 상태인가.
///
/// 거리를 아무도 모르면(PDR 미시작·측위 실패) 고르게 두면 안 된다 — 눌러도
/// 순서가 안 바뀌는 선택지가 되고, 사용자는 정렬이 고장 났다고 읽는다. 화면은
/// 이 값이 false일 때 항목을 비활성으로 두고 이유를 적는다.
bool canSortByNearest(Map<String, NodeReach>? reachByNodeId) =>
    reachByNodeId != null && reachByNodeId.isNotEmpty;

/// 정렬 컨트롤을 화면에 띄울 상태인가.
///
/// - **[itemCount]가 2 미만이면** 누를 이유가 없는 버튼이다.
/// - **[fromSemantic]이면** 유사도순이라 사용자가 고를 수 있는 축이 아니다.
///   "뜻이 가장 잘 맞는 순서"를 거리로 갈아치우면 위쪽이 무엇을 뜻하는지
///   알 수 없게 된다(아래 [sortedSearchResults] 주석과 같은 근거).
bool canChooseSortOrder({required int itemCount, required bool fromSemantic}) =>
    itemCount >= 2 && !fromSemantic;

/// 사용자가 아직 고르지 않았을 때의 순서.
///
/// 위치를 알면 가까운 순, 모르면 이름 맞춤 순이다. 선택은 **세션에 저장하지
/// 않는다** — 저장하면 다음 검색이 사용자가 기억 못 하는 순서로 시작한다.
SearchSortOrder defaultSortOrder(Map<String, NodeReach>? reachByNodeId) =>
    canSortByNearest(reachByNodeId)
    ? SearchSortOrder.nearest
    : SearchSortOrder.bestMatch;

/// [results]를 [reachByNodeId]의 거리 오름차순으로 정렬한 **새 목록**을 만든다.
///
/// [reachByNodeId]는 사용자 현재 위치에서 출발한 `reachableFrom` 결과다.
/// 입력 목록은 건드리지 않는다.
///
/// 정렬하지 않기로 판단한 경우에는 사본을 만들지 않고 [results]를 그대로
/// 돌려준다 — "순서를 손대지 않았다"를 가장 싸고 분명하게 표현하는 방법이다.
///
/// **정렬하지 않는 경우 셋** — [order]가 `bestMatch`일 때(사용자가 골랐다),
/// [fromSemantic]이 true일 때(유사도순과 거리순은 우열이 아니라 의미가 다른
/// 순서다), [reachByNodeId]를 모를 때. 마지막은 **전부 정렬하거나 전혀 정렬하지
/// 않는다**는 뜻이다 — 아는 몇 건만 위로 올리면 정렬 안 한 목록보다 나쁘다.
///
/// **거리를 모르는 매장**(`nodeId`가 null이거나 그래프가 끊김)은 정렬에서 빼고
/// 목록 끝에 원래 상대 순서로 붙인다. 0으로 치면 맨 앞, 무한대로 치면 가장 먼
/// 매장이 되는데 둘 다 거짓이다.
///
/// [fromSemantic]을 **필수 인자로 받는 것이 요점이다.** "의미 검색이면 안 부른다"로
/// 두면 규칙이 위젯의 `if` 한 줄로만 존재해, 두 번째 호출부가 그것을 모른 채
/// 조용히 틀린다. 필수 인자면 새 호출부는 이 질문에 답하지 않고는 컴파일되지 않는다.
List<PoiSearchResult> sortedSearchResults({
  required List<PoiSearchResult> results,
  required Map<String, NodeReach>? reachByNodeId,
  required bool fromSemantic,
  required SearchSortOrder order,
}) {
  if (order == SearchSortOrder.bestMatch) return results;
  if (fromSemantic) return results;
  final reach = reachByNodeId;
  if (reach == null || reach.isEmpty) return results;

  // 거리를 아는 것만 정렬 대상으로 뽑는다. index는 아래 동점 처리에 쓴다.
  final ranked = <({int index, PoiSearchResult store, double distanceM})>[];
  // 거리를 모르는 것은 여기 모았다가 뒤에 그대로 붙인다. 훑는 순서가 곧 입력
  // 순서라, 따로 정렬하지 않는 것만으로 상대 순서가 보존된다.
  final unknown = <PoiSearchResult>[];

  for (var index = 0; index < results.length; index++) {
    final store = results[index];
    final nodeId = store.nodeId;
    final found = nodeId == null ? null : reach[nodeId];
    if (found == null) {
      unknown.add(store);
      continue;
    }
    ranked.add((index: index, store: store, distanceM: found.distanceM));
  }

  // **Dart의 `List.sort`는 안정 정렬이 아니다.** 같은 노드를 공유하는 인접
  // 매장(푸드코트 한 줄처럼)은 거리가 정확히 같아서, 그대로 두면 호출할
  // 때마다 순서가 뒤바뀔 수 있다. 원래 인덱스를 2차 기준으로 넣어 동점을
  // 입력 순서로 깨면, 정렬 알고리즘이 무엇이든 결과가 하나로 정해진다.
  //
  // 표시하는 값이 `distanceM`이므로 정렬 기준도 `distanceM`이다. `costM`은
  // 수직 전이 선호가 인코딩된 튜닝값이라, 그걸로 세우면 화면에 적힌 거리가
  // 뒤죽박죽인 목록이 나온다.
  ranked.sort((a, b) {
    final byDistance = a.distanceM.compareTo(b.distanceM);
    if (byDistance != 0) return byDistance;
    return a.index.compareTo(b.index);
  });

  return [for (final entry in ranked) entry.store, ...unknown];
}

/// 자동완성 후보를 [order]대로 세운 **새 목록**을 만든다.
///
/// 후보 목록은 서버가 한 곳을 지목하지 못한 질의(`구찌` → 3건)에서 **최종 결과
/// 화면**이 된다. 그때 사용자가 고르는 기준은 결과 목록과 같아야 한다 — 같은
/// 화면에서 같은 조작이 다르게 동작하면 그건 두 개의 앱이다.
///
/// ## 거리는 **그룹 대표**의 거리다
///
/// 후보 한 줄은 같은 이름의 매장 여럿일 수 있다(화장실 19곳). 화면에 적히는
/// 거리는 [nearestByWalkingDistance]가 고른 대표의 것이므로, 정렬도 같은 값을
/// 써야 한다. 다른 값으로 세우면 **화면에 적힌 숫자가 오름차순이 아닌 목록**이
/// 나온다.
///
/// ## 정렬하지 않는 경우
///
/// - [order]가 [SearchSortOrder.bestMatch]일 때. 이게 **기본이자 원래 순서**다
///   — K절의 매칭 우선순위(종류 → 일치 위치 → 이름 길이 → 입력 순서)를 그대로
///   둔다. 타이핑 중에는 이 순서만 쓴다(화면 쪽 규칙).
/// - [reachByNodeId]가 null이거나 비었을 때. 거리를 아무도 모른다.
///
/// 거리를 모르는 후보(그룹 전원이 도달 불가)는 **정렬에서 빼고 목록 끝에**
/// 원래 상대 순서를 유지한 채 붙인다. [sortedSearchResults]와 같은 규칙이다.
List<StoreSuggestion> sortedSuggestions({
  required List<StoreSuggestion> suggestions,
  required Map<String, NodeReach>? reachByNodeId,
  required SearchSortOrder order,
}) {
  if (order == SearchSortOrder.bestMatch) return suggestions;
  final reach = reachByNodeId;
  if (reach == null || reach.isEmpty) return suggestions;

  final ranked =
      <({int index, StoreSuggestion suggestion, double distanceM})>[];
  final unknown = <StoreSuggestion>[];

  for (var index = 0; index < suggestions.length; index++) {
    final suggestion = suggestions[index];
    final nearest = nearestByWalkingDistance(
      stores: suggestion.stores,
      reachByNodeId: reach,
    );
    final found = nearest.reach;
    if (found == null) {
      unknown.add(suggestion);
      continue;
    }
    ranked.add((
      index: index,
      suggestion: suggestion,
      distanceM: found.distanceM,
    ));
  }

  // 동점을 입력 순서로 깨는 이유는 위와 같다 — Dart의 `List.sort`는 안정
  // 정렬이 아니다.
  ranked.sort((a, b) {
    final byDistance = a.distanceM.compareTo(b.distanceM);
    if (byDistance != 0) return byDistance;
    return a.index.compareTo(b.index);
  });

  return [for (final entry in ranked) entry.suggestion, ...unknown];
}
