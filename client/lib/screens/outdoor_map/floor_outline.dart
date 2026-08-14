/// 야외 지도 위에 그리는 "지금 보고 있는 층의 외곽선" 규칙.
///
/// 규칙은 둘 — **실내가 아니면 안 그린다**, **어느 층이든 그 층 도면의 외곽선을
/// 따른다**(건물 외곽선으로 폴백하지 않는다).
///
/// 그 두 결정의 근거는 `docs/client/indoor-entry-rules.md` 4절.
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
