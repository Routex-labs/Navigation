/// 안내 중에 지도 위 chrome(검색창·카테고리 줄·층 선택기·하단 바)을 접을지
/// 판정한다.
///
/// ## 왜 함수로 빼는가
///
/// 접는 조건은 **안내 카드에 "종료" 버튼이 뜨는 조건과 반드시 같아야 한다.**
/// chrome을 접으면 화면에는 지도와 안내 카드만 남는다. 그때 카드에 종료가
/// 없으면 사용자가 이 화면에서 빠져나갈 수단이 하나도 없다 — 검색창도 메뉴도
/// 하단 바도 이미 접힌 뒤다.
///
/// 두 판정을 각자 쓰면 반드시 어긋난다. 실제로 그랬다: "사용자가 고른 목적지가
/// 있으면 안내 중"으로 잡았더니, [showRouteTo]가 목적지를 세팅하고 경로 API를
/// 기다리는 동안 `route`가 아직 없어 카드가 그려지지 않았다. GPS를 못 잡아
/// 경로 계산이 실패하면 그 상태가 **그대로 남는다** — 접힌 chrome, 카드 없음,
/// 탈출구 없음. 그래서 판정을 여기 한 곳에 두고 양쪽이 같이 본다.
///
/// ## 판정
///
/// - [hasIndoorRouteDestination]: 실내 매장 목적지가 잡혀 있으면 안내 중이다.
///   실내 안내 카드는 경로 계산 성공 여부와 무관하게 목적지만 있으면 뜨고,
///   항상 종료 버튼을 단다 — 계산이 실패해도 탈출구가 있다.
/// - [hasUserDestination] + [hasComputedRoute]: 야외는 **경로가 실제로 그려진
///   뒤에만** 안내 중이다. 야외 안내 카드가 경로가 있을 때만 그려지기 때문이다.
/// - 둘 다 아니면 접지 않는다. 특히 목적지 없이 경로만 있는 경우(건물 입구까지
///   자동으로 그리는 걷기 경로)는 카드에 종료 버튼이 없다 — 사용자가 시작한
///   적이 없으니 끝낼 것도 없다는 기획이고, 그래서 chrome을 남겨야 한다.
bool shouldFoldGuidanceChrome({
  required bool hasUserDestination,
  required bool hasIndoorRouteDestination,
  required bool hasComputedRoute,
}) {
  if (hasIndoorRouteDestination) return true;
  return hasUserDestination && hasComputedRoute;
}
