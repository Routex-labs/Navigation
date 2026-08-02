/// 실내 도면 폴리곤의 색. 실내 화면([FloorPlanView])과 야외 지도의 실내 진입
/// 오버레이([indoor_overlay_layers.dart])가 **같은 도면을 그리므로** 두 곳이
/// 반드시 같은 값을 써야 한다. 예전에는 두 파일에 hex가 따로 박혀 있어, 한쪽만
/// 바꾸면 층을 오가는 사이에 도면 색이 바뀌어 보였다.
///
/// 규칙은 상용 지도와 같다 — **걸을 수 있는 곳은 밝게, 막힌 곳은 어둡게.**
/// 통로(footprint)가 가장 밝고 매장이 한 단계 어둡다. 실내 내비에서 사용자가
/// 가장 먼저 읽어야 하는 정보가 "어디로 걸을 수 있나"이기 때문이다.
///
/// 원래 값은 원본 SVG(`hyundai_floor_map_corrected_v6.svg`)에서 그대로 옮긴
/// `#F3F1EF`/`#D8D4D1`이었는데, 통로(`#FFFFFF`)와 명도 차가 2%도 안 나 통로와
/// 매장이 하나의 흰 덩어리로 보였다. 명도 차를 약 3배로 벌린 값이 아래다.
/// **원본 SVG와는 더 이상 일치하지 않는다** — 의도적으로 깬 것이다.
library;

/// 건물 바닥. 걸어 다니는 공간이라 가장 밝게 둔다.
const mapFootprintFill = '#FFFFFF';
const mapFootprintOutline = '#00000088';

/// 매장 폴리곤. 통로와 구분되도록 한 단계 어둡다.
const mapStoreFill = '#EAE6E1';
const mapStoreOutline = '#CFC9C2';
