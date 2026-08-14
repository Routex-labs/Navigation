/// 지도 위 **텍스트 라벨**의 색·헤일로·크기.
///
/// 위계는 **두 단계뿐이다** — 매장명과 그보다 한 단계 옅은 편의시설·POI 이름.
/// 각 값의 근거는 `docs/client/map-style-rules.md`.
library;

/// 매장명. 도면에서 사용자가 실제로 찾는 대상이다.
const mapLabelStoreColor = '#444846';

/// 편의시설·POI 이름. 한 단계 옅다 — **아이콘이 주 신호이고 이름은 보조**다.
const mapLabelFacilityColor = '#6B706A';

/// 도면 폴리곤·경로선 위에서 글자 획을 살린다.
const mapLabelHaloColor = '#FFFFFF';

/// 실내(1.2)와 야외(1.0)로 갈라져 있던 것을 굵은 쪽으로 맞췄다.
const mapLabelHaloWidth = 1.2;

/// 폴리곤 맞춤을 쓰지 않는 라벨의 **고정** 크기(px). 매장명 밴드(12~17)와 같은
/// 대역이어야 도면이 두 덩어리로 갈라져 보이지 않는다.
const mapLabelFixedTextSize = 13.0;

/// 고정 크기 라벨의 줄바꿈 폭(em). 크기가 고정이면 폭도 고정이다.
const mapLabelFixedMaxWidth = 6.0;

/// 아이콘이 중심을 차지하는 라벨에서 이름을 내리는 오프셋(em).
///
/// **하한은 헤일로다.** 더 줄이려면 오프셋이 아니라 아이콘 크기나 헤일로를
/// 손봐야 한다 — 지금 값이 이미 하한과 같다.
const mapLabelBelowIconOffset = <double>[0, 0.6];
