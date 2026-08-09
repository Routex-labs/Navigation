/// 건물 외곽선을 놓고 좌표 하나를 재는 **기하 유틸**.
///
/// 안팎 판정([isPointInPolygon])과 경계선까지의 거리([metersToPolygon],
/// [metersInsidePolygon]), 그리고 외곽선의 폭([polygonWidthMeters])을 여기에
/// 모아 둔다. 실제 정책은 이 값을 읽어 가는 쪽에 있다 — GPS 진입/이탈 판정은
/// [indoor_entry_gps.dart], 도면 페이드·이탈 zoom은 [indoor_entry_zoom.dart]다.
///
/// 화면 코드에서 분리한 이유는 검증이다. 계산이 지도 컨트롤러에 묶여 있으면
/// 위젯 테스트(MapLibre 플랫폼 뷰가 없어 컨트롤러가 null)에서 확인할 수 없고,
/// 그러면 "건물 안인데 실내로 안 들어간다" 같은 증상이 실기기에서만 보인다.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart' as ll;

/// 위도 1도의 미터. 클라이언트의 다른 좌표 계산(`domain/geo_transform.dart`)과
/// 같은 값을 쓴다 — 두 곳이 다른 상수를 쓰면 같은 좌표를 놓고 거리가 어긋난다.
const _metersPerDegreeLat = 111320.0;

/// [point]가 [polygon] 내부인지 ray-casting으로 판정한다.
///
/// 백엔드가 자기 참조 없이 단일 외곽선만 내려주므로 hole/멀티 폴리곤은 다루지
/// 않는다. 링이 닫혀 있어도(첫 점 == 끝 점) 결과는 같다.
bool isPointInPolygon(ll.LatLng point, List<ll.LatLng> polygon) {
  if (polygon.length < 3) return false;
  var inside = false;
  final n = polygon.length;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    final xi = polygon[i].longitude;
    final yi = polygon[i].latitude;
    final xj = polygon[j].longitude;
    final yj = polygon[j].latitude;
    final intersect = ((yi > point.latitude) != (yj > point.latitude)) &&
        (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

/// [polygon]의 동서 방향 폭(m).
///
/// 실내 진입 임계값을 화면 폭에 맞출 때(`indoorEntryZoomThresholdFor`) "이 건물이
/// 화면에 담기는 zoom"의 입력으로 쓴다.
///
/// 회전을 고려하지 않은 **축 정렬 경계 상자**의 폭이다. 지도는 기본이 정북
/// 정렬이라 사용자가 실제로 보는 가로 폭과 같고, 사용자가 지도를 돌린 경우에도
/// 회전한 건물의 실제 가로 폭보다 크거나 같게 나와 임계값이 보수적으로
/// (=진입이 조금 늦게) 움직일 뿐이라 과잉 진입 쪽으로는 새지 않는다.
///
/// 점이 3개 미만이면 0을 돌려준다. 호출부는 이때 보정 없이 기본 임계값을 쓴다.
double polygonWidthMeters(List<ll.LatLng> polygon) {
  if (polygon.length < 3) return 0;
  var minLng = polygon.first.longitude;
  var maxLng = minLng;
  var latSum = 0.0;
  for (final p in polygon) {
    if (p.longitude < minLng) minLng = p.longitude;
    if (p.longitude > maxLng) maxLng = p.longitude;
    latSum += p.latitude;
  }
  // 경도 1도의 미터는 위도에 따라 줄어든다. 건물 규모에서는 평균 위도 하나로
  // 근사해도 오차가 무시할 수준이다([metersToPolygon]과 같은 근사).
  final meanLat = latSum / polygon.length;
  final mPerDegLng = _metersPerDegreeLat * math.cos(meanLat * math.pi / 180);
  return (maxLng - minLng) * mPerDegLng;
}

/// [point]에서 [polygon]까지의 거리(m). 내부면 0이다.
///
/// 외곽선의 **변**까지의 거리를 재므로, 꼭짓점만 비교할 때와 달리 긴 벽면
/// 가운데를 확대한 경우도 올바르게 가깝다고 판정한다.
double metersToPolygon(ll.LatLng point, List<ll.LatLng> polygon) {
  if (polygon.length < 3) return double.infinity;
  if (isPointInPolygon(point, polygon)) return 0;
  return _metersToBoundary(point, polygon);
}

/// [point]가 [polygon] **안쪽으로** 얼마나 들어와 있는지(m). 밖이면 0이다.
///
/// [metersToPolygon]의 짝이다. 두 값 중 하나는 항상 0이고, 둘을 함께 쓰면
/// "벽에서 안으로 5 m 이상 / 밖으로 20 m 이상"처럼 안팎을 비대칭 임계값으로
/// 가를 수 있다([indoor_entry_gps.dart]의 진입/이탈 판정).
double metersInsidePolygon(ll.LatLng point, List<ll.LatLng> polygon) {
  if (polygon.length < 3) return 0;
  if (!isPointInPolygon(point, polygon)) return 0;
  return _metersToBoundary(point, polygon);
}

/// [point]에서 외곽선까지의 거리(m). 안팎을 가리지 않고 **경계선까지**만 잰다.
///
/// 계산은 [point] 주변을 평면으로 근사(equirectangular)해서 한다. 건물 크기
/// (수백 m) 규모에서 오차는 무시할 수 있고, 대신 위경도 차이를 미터로 바꿀 때
/// 경도 축을 `cos(위도)`로 줄여야 한다 — 안 그러면 서울 위도에서 동서 거리가
/// 실제보다 약 26% 크게 나온다. 자오선/극점을 넘는 폴리곤은 다루지 않는다
/// (실내 도면이 있는 건물에서는 생기지 않는다).
double _metersToBoundary(ll.LatLng point, List<ll.LatLng> polygon) {
  final mPerDegLng =
      _metersPerDegreeLat * math.cos(point.latitude * math.pi / 180);
  double toLocalX(ll.LatLng p) => (p.longitude - point.longitude) * mPerDegLng;
  double toLocalY(ll.LatLng p) => (p.latitude - point.latitude) * _metersPerDegreeLat;

  var best = double.infinity;
  final n = polygon.length;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    final distance = _pointToSegmentMeters(
      toLocalX(polygon[j]),
      toLocalY(polygon[j]),
      toLocalX(polygon[i]),
      toLocalY(polygon[i]),
    );
    if (distance < best) best = distance;
  }
  return best;
}

/// 원점에서 선분 (ax, ay)-(bx, by)까지의 거리. 좌표는 이미 미터 평면이다.
/// 길이 0인 변(중복 좌표)에서 0으로 나누지 않도록 먼저 걸러낸다.
double _pointToSegmentMeters(double ax, double ay, double bx, double by) {
  final dx = bx - ax;
  final dy = by - ay;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared < 1e-12) return math.sqrt(ax * ax + ay * ay);
  // 원점을 변에 투영한 위치. 변 밖으로 나가면 끝점으로 잘라낸다.
  var t = -(ax * dx + ay * dy) / lengthSquared;
  t = t.clamp(0.0, 1.0);
  final px = ax + dx * t;
  final py = ay + dy * t;
  return math.sqrt(px * px + py * py);
}

