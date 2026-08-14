/// 상단 초안 바의 출발↔도착 맞바꾸기.
///
/// 문제는 **출발지가 "현재 위치"(null)일 때**다. 도착지에는 그런 표현이 없어서
/// (실제 지점이어야 경로가 나온다) 뒤집을 때 **가장 가까운 매장**으로 굳힌다.
/// 여기는 "어느 매장으로"만 정하고, 좌표 붙이기와 재계산은 화면이 한다.
library;

import '../../models/place/store_index_entry.dart';
import 'dijkstra.dart';

/// 현재 위치를 대신할 매장을 고른다. 못 고르면 null이고, 그때 화면은 **뒤집지
/// 않아야 한다** — 아무 매장이나 골라 두면 지정한 적 없는 경로가 조용히 그려진다.
///
/// **null인 경우 셋** — 거리를 모를 때(그래서 [nearestByWalkingDistance]를 쓰지
/// 않는다: 그쪽의 폴백은 목적지를 확정하는 자리에서 위험하다), 도달 가능한 매장이
/// 없을 때, 남는 후보가 [excludeNodeId]뿐일 때.
///
/// [excludeNodeId]는 **뒤집었더니 출발 == 도착**을 막는다 — 도착지 바로 앞에 서
/// 있으면 최근접이 곧 그 도착지라 길이 0인 경로가 된다.
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
