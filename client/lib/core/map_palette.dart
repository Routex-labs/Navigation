/// 실내 도면 폴리곤의 색. 실내 화면과 야외 지도의 실내 오버레이가 함께 쓴다.
///
/// 규칙은 **걸을 수 있는 곳은 밝게, 막힌 곳은 어둡게** — 통로(footprint)가 가장
/// 밝고 매장이 한 단계 어둡다. 구분은 면이 아니라 **경계선이 만든다.**
///
/// 원본 SVG와 일치하지 않으며 의도적이다. 그 사정과 색조를 따뜻하게 유지하는
/// 이유는 `docs/client/map-style-rules.md`.
library;

/// 건물 바닥. 걸어 다니는 공간이라 가장 밝게 둔다.
const mapFootprintFill = '#FFFFFF';

/// 통로 외곽선. 검정 반투명은 iOS MapLibre에서 예상보다 진하게 합성돼 도면을
/// 격자처럼 보이게 했으므로 따뜻한 회색으로 낮춘다.
const mapFootprintOutline = '#C8C1B8';

/// 매장 폴리곤 면. 경계선이 얹힐 바탕을 주는 정도로만 낮춘다.
const mapStoreFill = '#F1EEEA';

/// 매장 경계선. 도면에서 실제로 구분을 만드는 값이라 면과 명도를 크게 벌린다.
///
/// `fillOutlineColor`는 **두께가 1px 고정**이라, 색으로 모자랄 때만 line 레이어를
/// 따로 얹는 비용을 낸다.
const mapStoreOutline = '#A69C90';

/// 선택(포커스)된 매장 강조 fill·테두리.
///
/// **`AppColors.primary`와 같은 값이어야 한다** — 다르면 같은 "선택됨"이 화면
/// 요소마다 다른 색으로 말해진다. MapLibre는 hex 문자열만 받아 다시 적는다.
const mapSelectionColor = '#4A87F1';
