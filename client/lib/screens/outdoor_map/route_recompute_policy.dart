/// 걷는 동안 **야외 도보 경로를 언제 다시 계산할지** 정하는 정책.
///
/// 위치 스트림과 짝을 이룬다([`core/service_locator.dart`]의
/// `positionStreamSettings`). 그쪽은 좌표를 1초에 한 번 받도록 열어 두었고,
/// 여기서는 그 좌표 전부로 TMAP을 부르지 않도록 막는다. 둘을 한 곳에서 처리하면
/// "위치를 자주 받는 것"과 "경로를 자주 부르는 것"이 다시 한 덩어리가 되고,
/// 그러면 네트워크를 아끼려고 좌표를 줄이는 예전 실수로 돌아간다.
///
/// ## 왜 나눠야 하는가
///
/// 위치 아이콘은 좌표가 오는 즉시 옮겨야 한다 — 그게 늦으면 사용자는 앱이 자기
/// 위치를 모른다고 느낀다. 반면 도보 경로는 몇 걸음 사이에 바뀌지 않는데,
/// 매 좌표마다 다시 부르면 1초에 한 번 외부 API를 두드리게 된다. 요금과
/// 호출 한도는 둘째 치고, 응답이 도착할 때마다 화면의 선이 미세하게 다시
/// 그려져 오히려 불안정해 보인다.
///
/// ## 실패하는 쪽
///
/// 이 정책은 **위치 스트림에서 들어온 좌표에만** 건다. 사용자가 목적지를 직접
/// 고른 요청까지 여기로 넣으면, 제자리에 선 채로 도착지를 눌렀을 때 "아무 일도
/// 일어나지 않는" 화면이 된다. 호출부에서 그 둘을 구분해야 한다.
library;

import 'package:latlong2/latlong.dart' as ll;

import '../../models/floor_plan.dart';

/// 마지막으로 경로를 요청한 지점에서 이만큼 움직여야 다시 요청한다(m).
///
/// 예전 위치 스트림의 거리 필터(5 m)보다 크게 잡았다. 5 m는 GPS 오차가 만드는
/// 흔들림과 구분되지 않아, 서 있기만 해도 좌표가 그 폭으로 튀면서 요청이
/// 나갔다. 10 m는 보통 걸음으로 8초 남짓이라 경로가 낡았다고 느낄 만큼 길지
/// 않으면서, 제자리에서 흔들리는 좌표로는 넘기 어렵다.
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
