/// 검색 결과를 **보행 거리** 오름차순으로 다시 세운다. 실내에서 직선거리는 자주
/// 거짓말을 한다 — 벽 하나 사이로 10m인 매장이 돌아서 120m일 수 있다.
///
/// **여기서 경로를 새로 계산하지 않는다** — 화면이 이미 들고 있는 `reachableFrom`
/// 결과를 조회만 한다. 결과 수만큼 다익스트라를 되돌리는 구현으로 바꾸지 마라.
///
/// 근거는 `search-result-list-ux.md` P절과 `search-input-assist.md` M절.
library;

import '../../models/poi_search_result.dart';
import '../route/dijkstra.dart';
import '../store/nearest_store.dart';
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

/// 정렬 컨트롤을 띄울 상태인가. [itemCount]가 2 미만이면 누를 대상이 없고,
/// [fromSemantic]이면 유사도순이라 사용자가 고를 수 있는 축이 아니다.
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

/// [results]를 거리 오름차순으로 정렬한 **새 목록**을 만든다. 입력은 건드리지
/// 않고, 정렬하지 않기로 하면 사본도 만들지 않고 [results]를 그대로 돌려준다.
///
/// **정렬하지 않는 경우 셋** — [order]가 `bestMatch`, [fromSemantic]이 true,
/// [reachByNodeId]를 모를 때. 마지막은 **전부 정렬하거나 전혀 정렬하지 않는다**는
/// 뜻이다(아는 몇 건만 올리면 정렬 안 한 목록보다 나쁘다).
///
/// 거리를 모르는 매장은 정렬에서 빼고 목록 끝에 원래 순서로 붙인다 — 0도 무한대도
/// 거짓이다. [fromSemantic]이 **필수 인자인 것이 요점이다**: 규칙이 위젯의 `if`
/// 한 줄로만 존재하면 두 번째 호출부가 모른 채 틀린다.
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

  // **Dart의 `List.sort`는 안정 정렬이 아니다** — 같은 노드를 공유하는 매장은
  // 거리가 같아 호출마다 순서가 뒤바뀐다. 원래 인덱스로 동점을 깬다.
  // 기준이 `costM`이 아니라 `distanceM`인 이유는 화면에 적히는 값이 그것이라서다.
  ranked.sort((a, b) {
    final byDistance = a.distanceM.compareTo(b.distanceM);
    if (byDistance != 0) return byDistance;
    return a.index.compareTo(b.index);
  });

  return [for (final entry in ranked) entry.store, ...unknown];
}

/// 자동완성 후보를 [order]대로 세운 **새 목록**을 만든다. 후보 목록은 서버가 한
/// 곳을 지목하지 못한 질의에서 최종 결과 화면이 되므로 결과 목록과 같은 기준을 쓴다.
///
/// **거리는 그룹 대표의 거리다** — 화면에 적히는 값이 [nearestByWalkingDistance]가
/// 고른 대표의 것이라, 다른 값으로 세우면 적힌 숫자가 오름차순이 아니게 된다.
///
/// 정렬하지 않는 경우와 거리를 모르는 후보 처리는 [sortedSearchResults]와 같다.
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
