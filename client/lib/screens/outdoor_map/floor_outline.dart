/// 야외 지도 위에 그리는 "지금 보고 있는 층의 외곽선" 규칙.
///
/// 지키는 규칙은 둘이다.
///
/// 1. **실내에 들어가 있지 않으면 선을 그리지 않는다.**
/// 2. **어느 층이든 그 층 도면의 외곽선을 따른다.** 건물 외곽선은 쓰지 않고,
///    층 도면이 없으면 폴백 없이 아무것도 그리지 않는다.
///
/// 왜 지상층까지 건물 외곽선을 버렸는지, 왜 타일에 LineLayer를 얹지 않았는지는
/// `docs/client/indoor-entry-rules.md`.
library;

import 'package:latlong2/latlong.dart';

/// 지금 그려야 하는 외곽선 링. 그리지 않아야 하면 null.
///
/// 링으로 쓸 수 있는 최소 조건은 점 3개다. 그보다 적으면 폴리곤이 되지 않으므로
/// 없는 것으로 본다.
///
/// [floorFootprint]는 지금 보고 있는 층 도면의 외곽선이다(`FloorPlan.footprint`).
/// 건물 외곽선은 **일부러 받지 않는다** — 받을 수 있으면 언젠가 폴백에 쓰게 된다.
List<LatLng>? floorOutlineRing({
  required bool indoorEntered,
  required List<LatLng>? floorFootprint,
}) {
  if (!indoorEntered) return null;
  if (floorFootprint == null || floorFootprint.length < 3) return null;
  return floorFootprint;
}
