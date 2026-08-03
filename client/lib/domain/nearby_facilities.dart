/// 어떤 지점에서 가장 가까운 편의시설을 고른다.
///
/// 매장 상세가 "이 매장에서 화장실이 얼마나 가까운가"를 적는 데 쓴다. **기준이
/// 사용자 위치가 아니라 그 매장이다** — 내 위치에서 매장까지의 거리는 이미 바로
/// 윗줄에 있어서, 같은 기준을 한 번 더 적으면 알려 주는 게 없다.
library;

import 'dijkstra.dart';

/// 상세에 적을 시설 종류. 종류마다 아이콘·라벨이 정해져 있어 문자열이 아니라
/// 열거형으로 받는다 — 호출부가 임의의 이름을 넣으면 아이콘이 폴백으로 떨어진다.
enum FacilityKind {
  restroom('화장실'),
  elevator('엘리베이터');

  const FacilityKind(this.label);

  /// 화면에 그대로 적는 이름.
  final String label;
}

/// [FacilityKind]로 분류된 후보 하나. `nodeId`는 그래프에서 그 시설로 들어가는
/// 노드다(매장의 `entrance_node_id`).
typedef FacilityCandidate = ({FacilityKind kind, String nodeId});

/// 종류별로 가장 가까운 시설 하나씩.
typedef NearbyFacility = ({FacilityKind kind, NodeReach reach});

/// 이 건물 데이터에서 시설을 가리키는 소분류 값.
///
/// 백엔드가 한글 소분류로 내려주고(`화장실`·`엘리베이터`), 옛 시드에는 영어
/// 열거값이 남아 있다. 둘 다 받는다 — `category_icon.dart`의
/// `subcategoryLabelFor`가 표시용으로 같은 변환을 하고 있다.
const _subcategoriesByKind = <FacilityKind, List<String>>{
  FacilityKind.restroom: ['화장실', 'restroom'],
  FacilityKind.elevator: ['엘리베이터', 'elevator'],
};

/// 매장 소분류를 시설 종류로 바꾼다. 시설이 아니면 null.
FacilityKind? facilityKindForSubcategory(String? subcategory) {
  if (subcategory == null) return null;
  final normalized = subcategory.trim().toLowerCase();
  for (final entry in _subcategoriesByKind.entries) {
    for (final value in entry.value) {
      if (value.toLowerCase() == normalized) return entry.key;
    }
  }
  return null;
}

/// [reach]에서 종류별로 가장 가까운 후보를 하나씩 고른다.
///
/// [reach]는 **기준 지점에서 출발한** `reachableFrom` 결과다. 후보의 노드가
/// 거기 없으면(그래프가 끊겼거나 다른 컴포넌트) 그 후보는 버린다 — 도달할 수
/// 없는 화장실을 "가장 가깝다"고 적으면 안 된다.
///
/// 결과는 [FacilityKind] 선언 순서로 정렬한다. 화면에서 화장실이 늘 먼저 와야
/// 매장마다 줄 순서가 바뀌지 않는다.
///
/// 같은 거리의 후보가 여럿이면 먼저 온 것을 쓴다. 어느 쪽을 골라도 사용자가
/// 걷는 거리는 같아서 굳이 정하지 않는다.
List<NearbyFacility> nearestFacilities({
  required Map<String, NodeReach> reach,
  required Iterable<FacilityCandidate> candidates,
}) {
  final best = <FacilityKind, NodeReach>{};
  for (final candidate in candidates) {
    final found = reach[candidate.nodeId];
    if (found == null) continue;
    final current = best[candidate.kind];
    if (current == null || found.distanceM < current.distanceM) {
      best[candidate.kind] = found;
    }
  }
  return [
    for (final kind in FacilityKind.values)
      if (best[kind] case final reach?) (kind: kind, reach: reach),
  ];
}
