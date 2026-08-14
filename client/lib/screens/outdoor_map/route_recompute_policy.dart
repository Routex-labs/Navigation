/// 걷는 동안 **야외 도보 경로를 언제 다시 계산할지** 정하는 정책.
///
/// 위치 스트림(`core/service_locator.dart`)과 짝을 이룬다 — 그쪽은 좌표를 1초에
/// 한 번 받고, 여기서는 그 좌표 전부로 TMAP을 부르지 않도록 막는다.
///
/// **위치 스트림에서 들어온 좌표에만 건다.** 사용자가 목적지를 직접 고른 요청까지
/// 여기로 넣으면, 제자리에 선 채로 도착지를 눌렀을 때 "아무 일도 일어나지 않는"
/// 화면이 된다. 호출부에서 그 둘을 구분해야 한다.
///
/// 왜 둘을 나눠야 하는지는 `docs/client/gps-stream-policy.md`.
library;

import 'package:latlong2/latlong.dart' as ll;

import '../../models/floor_plan.dart';

/// 마지막으로 경로를 요청한 지점에서 이만큼 움직여야 다시 요청한다(m).
///
/// GPS 오차가 만드는 흔들림(5 m 안팎)으로는 넘기 어려운 값이어야 한다.
const routeRecomputeMinMoveMeters = 10.0;

/// [origin]에서 도보 경로를 다시 계산해야 하는지.
///
/// [lastRequestedOrigin]이 null이면(이번이 첫 좌표거나 아직 한 번도 요청하지
/// 않았으면) 무조건 계산한다 — 경로가 없는 상태를 유지하는 것이 더 나쁘다.
bool shouldRecomputeRouteAfterMove({
  required ll.LatLng origin,
  required ll.LatLng? lastRequestedOrigin,
  double minMoveMeters = routeRecomputeMinMoveMeters,
}) {
  if (lastRequestedOrigin == null) return true;
  return wgs84DistanceMeters(lastRequestedOrigin, origin) >= minMoveMeters;
}
