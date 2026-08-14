/// 상단 초안 바의 출발↔도착 맞바꾸기.
///
/// 대부분은 두 값을 그냥 바꾸면 끝난다. 문제는 **출발지가 "현재 위치"일 때**다.
/// 화면은 출발지가 비어 있는 것(`null`)을 "현재 위치에서 출발"로 읽는데, 도착지
/// 쪽에는 그런 표현이 없다 — 도착지는 실제 지점(노드·층)이어야 경로를 계산할 수
/// 있기 때문이다. 그래서 뒤집을 때 현재 위치를 **가장 가까운 매장**으로 굳힌다.
///
/// 이 파일은 "어느 매장으로 굳힐지"만 정한다. 좌표를 붙여 후보로 만드는 일과
/// 실제 경로 재계산은 화면이 한다.
library;

import '../../models/store_index_entry.dart';
import 'dijkstra.dart';

/// 현재 위치를 대신할 매장을 고른다. 못 고르면 null이고, 그때 화면은 **뒤집지
/// 않아야 한다** — 아무 매장이나 골라 두면 사용자가 지정한 적 없는 곳으로
/// 가는 경로가 조용히 그려진다.
///
/// ## null을 돌려주는 경우 (실패 조건을 먼저 정한 것)
///
/// - **[reachByNodeId]가 null이거나 비었을 때.** 현재 위치를 모른다는 뜻이다
///   (야외이거나 PDR 측위 전). 거리를 모르면 "가장 가까운"을 주장할 수 없다.
///   여기서 [nearestByWalkingDistance]를 그대로 쓰지 않는 이유가 이것이다 —
///   그쪽은 거리를 모를 때 같은 층 첫 매장으로 물러서는데, 그건 후보 한 줄에
///   층을 적는 자리에서나 안전한 선택이지 **목적지를 확정하는 자리**에서는
///   사용자가 고르지도 않은 곳을 도착지로 만든다.
/// - **도달 가능한 매장이 하나도 없을 때.** 그래프가 끊겼거나 색인의 매장에
///   `entranceNodeId`가 없다.
/// - **남는 후보가 [excludeNodeId]뿐일 때.** 아래 참고.
///
/// ## [excludeNodeId] — 뒤집었더니 출발 == 도착
///
/// 지금 도착지 바로 앞에 서 있으면 최근접 매장이 곧 그 도착지다. 그대로 뒤집으면
/// 출발지와 도착지가 같아져 길이 0인 경로가 된다. 그래서 지금 도착지의 노드는
/// 후보에서 뺀다 — 뒤집기는 "왔던 길을 되돌아간다"는 뜻이지 제자리에 머무는
/// 조작이 아니다.
StoreIndexEntry? nearestStoreForCurrentLocation({
  required List<StoreIndexEntry> stores,
  required Map<String, NodeReach>? reachByNodeId,
  String? excludeNodeId,
}) {
  final reach = reachByNodeId;
  if (reach == null || reach.isEmpty) return null;

  StoreIndexEntry? best;
  NodeReach? bestReach;
  for (final store in stores) {
    final nodeId = store.entranceNodeId;
    if (nodeId == null) continue;
    if (excludeNodeId != null && nodeId == excludeNodeId) continue;
    final found = reach[nodeId];
    if (found == null) continue;
    // 엄격한 `<`라서 동점이면 갱신하지 않는다 — 같은 입력이면 같은 결과가
    // 나와야 한다(`nearest_store.dart`의 「결정성」과 같은 규칙).
    if (bestReach == null || found.distanceM < bestReach.distanceM) {
      best = store;
      bestReach = found;
    }
  }
  return best;
}
