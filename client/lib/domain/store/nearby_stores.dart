/// **이 매장에서** 걸어서 가까운 다른 매장을 고른다.
///
/// 기준이 사용자가 아니라 **이 매장**인 것이 요점이다. 사용자 기준 거리는 이미 시트
/// 헤더에 있고(`PlaceDetailSheet.reach`), 같은 기준으로 두 번 적으면 두 번째 줄이
/// 알려 주는 것이 없다. "여기 온 김에 옆에 뭐가 있나"에 답하는 자리다.
///
/// **여기서 경로를 새로 계산하지 않는다.** 호출부가 이 매장의 입구 노드에서
/// `reachableFrom`을 한 번 돌려 전 노드 결과를 만들고, 이 함수는 그 맵을 조회만 한다
/// (`nearest_store.dart`·`search_result_order.dart`와 같은 규칙).
///
/// 구현 전에 정한 검증 기준 9건(입구 노드 없음·도달 불가·시설 제외·동거리 고정
/// 정렬 …)은 `test/domain/nearby_stores_test.dart`가 그대로 담고 있다.
library;

import '../../models/store_index_entry.dart';
import '../route/dijkstra.dart';

/// 근처 매장 한 줄. [reach]는 **이 매장에서** 잰 값이다.
typedef NearbyStore = ({StoreIndexEntry store, NodeReach reach});

/// 근처 매장을 [limit]개까지 거리순으로 고른다.
///
/// [reachByNodeId]는 기준 매장의 입구 노드에서 출발한 `reachableFrom` 결과다.
/// [excludePlaceId]는 지금 보고 있는 매장이며, 자기 자신을 "근처"라고 말하지 않기
/// 위해 뺀다.
///
/// **직선거리로 대체하지 않는다.** 입구 노드가 없거나 그래프가 끊긴 매장은 목록에서
/// 뺀다. 실내에서 직선거리는 벽을 뚫고 지나가는 값이라, 30m라고 적어 두고 실제로는
/// 반대편으로 돌아가야 하는 일이 생긴다 — 거리를 모르는 것보다 나쁘다.
List<NearbyStore> nearbyStores({
  required List<StoreIndexEntry> stores,
  required Map<String, NodeReach> reachByNodeId,
  required String excludePlaceId,
  int limit = 5,
}) {
  final candidates = <NearbyStore>[];

  for (final store in stores) {
    if (store.id == excludePlaceId) continue;
    // 상세를 열지 않는 대상(주차·에스컬레이터·엘리베이터)과 시설(화장실·락커)은
    // 뺀다. 판정은 서버가 준 kind로 한다 — 소분류 목록을 여기에 베끼면 서버가
    // 규칙을 고친 날 두 화면이 서로 다른 말을 한다.
    if (store.kind != 'store') continue;

    final nodeId = store.entranceNodeId;
    if (nodeId == null) continue;

    final reach = reachByNodeId[nodeId];
    if (reach == null) continue;

    candidates.add((store: store, reach: reach));
  }

  // 거리 동점은 이름으로 깬다. 동점을 그대로 두면 인덱스 순서(서버가 층 내림차순으로
  // 고정)에 기대게 되어, 같은 데이터에서도 층이 바뀌면 줄 순서가 따라 바뀐다.
  candidates.sort((a, b) {
    final byDistance = a.reach.distanceM.compareTo(b.reach.distanceM);
    return byDistance != 0 ? byDistance : a.store.name.compareTo(b.store.name);
  });

  return candidates.take(limit).toList(growable: false);
}
