/// 같은 이름으로 묶인 매장 여럿 중 **현재 위치에서 가장 가까운 하나**를 고른다.
///
/// 자동완성 후보는 이름이 같은 매장을 한 줄로 묶는다(화장실 19곳 → 1줄,
/// `store_suggestions.dart`). 그러면 그 한 줄에 **어느 매장의 층을 적을 것인가**를
/// 누군가 정해야 하는데, 예전에는 "인덱스에서 처음 나온 것"이었다. 인덱스 순서는
/// 서버가 `Floor.level DESC, Store.id`로 못박아 두므로(`building_queries.py`),
/// 결과적으로 **항상 꼭대기 층이 대표**였다 — B2에 서 있어도 `화장실 · 6F 등 19곳`.
/// 정보가 없는 게 아니라 틀린 정보였다.
///
/// **여기서 경로를 새로 계산하지 않는다.** 화면은 이미 `reachableFrom`을 한 번 돌려
/// 전 노드 결과를 들고 있고(`SearchPanel.reachByNodeId`), 이 함수는 그 맵을 조회만
/// 한다. 결과 목록의 거리순 정렬(`search_result_order.dart`)과 같은 근거다.
///
/// 설계 근거와 검증 기준은 `docs/client/search-result-list-ux.md` O절이 단일 출처다.
library;

import '../models/store_index_entry.dart';
import 'dijkstra.dart';

/// 고른 대표와 그 매장까지의 도달 정보.
///
/// [reach]가 null이면 **거리를 모른다**는 뜻이고, 그때 [store]는 입력 순서 첫 번째다
/// — 지금까지의 동작 그대로다. 화면은 이 null을 보고 거리 줄을 생략한다.
typedef NearestStore = ({StoreIndexEntry store, NodeReach? reach});

/// [stores] 중 [reachByNodeId] 기준 보행 거리가 가장 짧은 매장을 고른다.
///
/// [stores]는 비어 있으면 안 된다. 후보 한 줄은 최소 한 매장에서 나오므로, 빈 목록은
/// 호출부의 버그이지 이 함수가 처리할 상태가 아니다.
///
/// ## 거리를 모를 때 (실패 조건을 먼저 정한 것)
///
/// - **[reachByNodeId]가 null이거나 비었을 때.** PDR 미시작·측위 실패다. 이때 억지로
///   고르면 기준 없는 값이 되므로 **입력 첫 번째를 그대로** 돌려준다. 거리 줄이 아예
///   안 뜨는 것이 A절이 정한 규칙이고, 후보 목록도 같게 둔다.
/// - **일부만 도달 가능할 때.** `entranceNodeId`가 null이거나 그래프가 끊겨
///   [reachByNodeId]에 키가 없는 매장이 섞인다. → **도달 가능한 것 중 최근접**을
///   고른다. 도달 못 하는 곳을 "가장 가깝다"고 적지 않는다.
/// - **전원 도달 불가일 때.** 입력 첫 번째 + [reach] null. 위와 같다.
///
/// **묶인 개수는 이 함수가 손대지 않는다.** 19곳 중 3곳만 거리를 안다고 해서 `등 3곳`이
/// 되면 없는 사실을 만들어 내는 것이다 — 19곳이 있는 건 사실이고, 우리가 거리를 아는
/// 게 3곳일 뿐이다.
///
/// ## 결정성
///
/// 거리가 정확히 같은 매장(같은 입구 노드를 공유하는 인접 매장)이 있을 때 매 호출
/// 같은 쪽이 뽑혀야 한다. 여기서는 정렬을 쓰지 않고 **엄격한 부등호(`<`)로만 갱신**해
/// 동점이면 먼저 훑은 쪽이 남게 한다 — 입력 순서가 곧 tie-breaker다. `List.sort`가
/// 안정 정렬이 아닌 Dart에서 정렬로 같은 일을 하려면 인덱스를 2차 키로 넣어야 하는데
/// (`search_result_order.dart`), 최솟값 하나만 필요한 자리에 정렬을 쓸 이유가 없다.
NearestStore nearestByWalkingDistance({
  required List<StoreIndexEntry> stores,
  required Map<String, NodeReach>? reachByNodeId,
}) {
  assert(stores.isNotEmpty, '후보 한 줄은 최소 한 매장에서 나온다');
  final first = stores.first;
  final reach = reachByNodeId;
  if (reach == null || reach.isEmpty) return (store: first, reach: null);

  StoreIndexEntry? best;
  NodeReach? bestReach;
  for (final store in stores) {
    final nodeId = store.entranceNodeId;
    if (nodeId == null) continue;
    final found = reach[nodeId];
    if (found == null) continue;
    // 엄격한 `<`라서 동점이면 갱신하지 않는다 — 위 「결정성」 참고.
    if (bestReach == null || found.distanceM < bestReach.distanceM) {
      best = store;
      bestReach = found;
    }
  }

  if (best == null) return (store: first, reach: null);
  return (store: best, reach: bestReach);
}
