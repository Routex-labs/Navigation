import 'package:latlong2/latlong.dart';

import '../models/directions_route.dart';

/// 이 거리보다 멀리 떨어져 끝나면 도착점까지 선을 이어 붙인다(m).
///
/// 3 m보다 가까우면 사실상 같은 점이라 이어 붙여 봐야 화면에서 보이지 않고,
/// 좌표만 하나 늘어난다.
const _minGapMeters = 3.0;

/// 이보다 멀면 잇지 않는다(m).
///
/// 이어 붙이는 선은 **직선**이라, 길면 길수록 실제 걸을 수 있는 길과 달라진다.
/// 건물 입구까지의 마지막 몇십 미터를 메우자고 200 m짜리 직선을 그으면 건물이나
/// 도로를 관통하는 안내가 되는데, 그건 끊긴 선보다 나쁘다 — 끊긴 선은 사용자가
/// "여기부터는 알아서 가야겠구나"로 읽지만, 그어진 직선은 길이라고 읽는다.
const _maxGapMeters = 150.0;

const _distance = Distance();

/// 도로 경로의 끝을 실제 도착점까지 이어 붙인다.
///
/// TMAP 보행자 경로는 **가장 가까운 보행 가능 도로**에서 끝난다. 도착점이 건물
/// 출입구처럼 도로에서 떨어진 자리면 선이 도로에서 뚝 끊기고, 화면에는 길이
/// 건물 앞 도로까지만 그려진다. 실기기에서 "북동쪽 출구 경유" 안내를 받았는데
/// 정작 그 출구 앞 구간이 비어 있던 것이 이 경우다.
///
/// [route]가 null이거나 좌표가 부족하면 그대로 돌려준다. 거리·시간은 **건드리지
/// 않는다** — 메우는 구간이 수십 미터라 총계에 의미 있는 차이를 만들지 않고,
/// 여기서 더하기 시작하면 화면에 적히는 숫자의 출처가 둘로 갈린다.
DirectionsRoute? extendRouteToDestination(
  DirectionsRoute? route,
  LatLng? destination,
) {
  if (route == null || destination == null) return route;
  if (route.points.length < 2) return route;

  final gap = _distance.as(LengthUnit.Meter, route.points.last, destination);
  if (gap < _minGapMeters || gap > _maxGapMeters) return route;

  return DirectionsRoute(
    points: [...route.points, destination],
    distanceMeters: route.distanceMeters,
    durationSeconds: route.durationSeconds,
    tollFareWon: route.tollFareWon,
    taxiFareWon: route.taxiFareWon,
  );
}
