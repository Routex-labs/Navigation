/// 안내 중에 지도 위 chrome(검색창·카테고리 줄·층 선택기·하단 바)을 접을지
/// 판정한다.
///
/// **접는 조건은 안내 카드에 "종료" 버튼이 뜨는 조건과 반드시 같아야 한다.**
/// 접고 나면 화면에 지도와 카드만 남으므로, 카드에 종료가 없으면 빠져나갈 수단이
/// 하나도 없다. 두 판정을 각자 쓰면 반드시 어긋난다 — 실제로 목적지만 보고 접었다가,
/// 경로 계산이 실패해 카드가 안 뜨는 상태로 굳은 적이 있다.
///
/// - 실내 매장 목적지가 있으면 안내 중이다. 실내 카드는 경로 계산 성공 여부와
///   무관하게 뜨고 항상 종료 버튼을 단다.
/// - 야외는 **경로가 실제로 그려진 뒤에만** 안내 중이다. 야외 카드가 그때만 뜬다.
/// - 목적지 없이 경로만 있는 경우(건물 입구까지 자동으로 그리는 걷기 경로)는 접지
///   않는다. 사용자가 시작한 적이 없으니 카드에 종료 버튼도 없다.
bool shouldFoldGuidanceChrome({
  required bool hasUserDestination,
  required bool hasIndoorRouteDestination,
  required bool hasComputedRoute,
}) {
  if (hasIndoorRouteDestination) return true;
  return hasUserDestination && hasComputedRoute;
}
