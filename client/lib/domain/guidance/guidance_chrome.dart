/// 안내 중에 지도 위 chrome(검색창·카테고리 줄·층 선택기·하단 바)을 접을지.
///
/// **접는 조건은 안내 카드에 "종료" 버튼이 뜨는 조건과 같아야 한다.** 접고 나면
/// 지도와 카드만 남아, 카드에 종료가 없으면 빠져나갈 수단이 없다 — 실제로 목적지만
/// 보고 접었다가 경로 계산 실패로 카드가 안 뜨는 상태로 굳은 적이 있다.
///
/// 실내는 목적지만 있으면(카드가 항상 뜬다), 야외는 **경로가 그려진 뒤에만** 접는다.
/// 목적지 없이 자동으로 그린 걷기 경로는 접지 않는다 — 사용자가 시작한 적이 없다.
bool shouldFoldGuidanceChrome({
  required bool hasUserDestination,
  required bool hasIndoorRouteDestination,
  required bool hasComputedRoute,
}) {
  if (hasIndoorRouteDestination) return true;
  return hasUserDestination && hasComputedRoute;
}
