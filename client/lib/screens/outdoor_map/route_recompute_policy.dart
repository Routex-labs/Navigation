/// 걷는 동안 **야외 도보 경로를 언제 다시 계산할지**.
///
/// **위치 스트림 좌표에만 건다.** 사용자가 직접 고른 요청까지 넣으면 제자리에서
/// 도착지를 눌렀을 때 아무 일도 일어나지 않는다. 근거는
/// `docs/client/gps-stream-policy.md`.
library;

import 'package:latlong2/latlong.dart' as ll;

import '../../models/floor_plan.dart';

/// 마지막으로 경로를 요청한 지점에서 이만큼 움직여야 다시 요청한다(m).
///
/// GPS 오차가 만드는 흔들림(5 m 안팎)으로는 넘기 어려운 값이어야 한다.
const routeRecomputeMinMoveMeters = 10.0;

/// [lastRequestedOrigin]이 null이면 무조건 계산한다 — 경로 없는 상태가 더 나쁘다.
bool shouldRecomputeRouteAfterMove({
  required ll.LatLng origin,
  required ll.LatLng? lastRequestedOrigin,
  double minMoveMeters = routeRecomputeMinMoveMeters,
}) {
  if (lastRequestedOrigin == null) return true;
  return wgs84DistanceMeters(lastRequestedOrigin, origin) >= minMoveMeters;
}
