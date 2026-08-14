/// 야외 지도 위 "실내 진입 오버레이"의 **위치** 정책.
///
/// zoom 정책([indoor_entry_zoom.dart])과 AND로 묶인다 — 확대만으로 켜면 건물이
/// 없는 엉뚱한 지역을 확대했을 때도 실내 UI가 올라온다.
///
/// 톨러런스의 근거는 `docs/client/indoor-entry-rules.md`.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart' as ll;

/// 위도 1도의 미터. 클라이언트의 다른 좌표 계산(`domain/geo_transform.dart`)과
/// 같은 값을 쓴다 — 두 곳이 다른 상수를 쓰면 같은 좌표를 놓고 거리가 어긋난다.
const _metersPerDegreeLat = 111320.0;

/// 카메라 중심이 건물 footprint에서 이 거리 안이면 "건물이 주변에 있다"고 본다.
///
/// **일부러 넉넉하게 잡지 않았다.** 과잉 진입(건물이 없는데 실내 모드)은 이 판정이
/// 고치려는 버그 자체이고, 과소 진입은 건물을 직접 탭하면 바로 복구된다.
const indoorEntryProximityMeters = 80.0;

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
    final intersect =
        ((yi > point.latitude) != (yj > point.latitude)) &&
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
  double toLocalY(ll.LatLng p) =>
      (p.latitude - point.latitude) * _metersPerDegreeLat;

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

/// 카메라 중심 [camera]가 실내 도면이 있는 건물([footprint]) 주변인지.
///
/// 다음 두 경우는 false다. 둘 다 "확대해도 실내로 들어가지 않는다"가 맞는
/// 상황이다.
///   - [footprint]가 null이거나 점이 3개 미만 — 건물을 아직 로드하지 못했거나
///     외곽선이 없다. 실내 UI를 켜도 보여줄 도면이 없다.
///   - [camera]가 null — 지도가 아직 카메라를 보고하지 않았다. 판정할 근거가
///     없으면 진입하지 않는 쪽으로 기운다.
bool isIndoorBuildingNearCamera({
  required ll.LatLng? camera,
  required List<ll.LatLng>? footprint,
  double radiusMeters = indoorEntryProximityMeters,
}) {
  if (camera == null || footprint == null || footprint.length < 3) return false;
  return metersToPolygon(camera, footprint) <= radiusMeters;
}

/// 실내에서 **건물 밖을 탭해 야외로 나가는** 판정의 여유 폭(m).
///
/// 외곽선 바로 바깥은 이탈로 치지 않는다. 벽에 붙은 매장을 누르거나 도면
/// 가장자리를 짚을 때 손가락이 외곽선을 몇 미터 넘기는 일은 흔한데, 그때마다
/// 실내가 통째로 닫히면 사용자는 매장을 누르려다 건물에서 쫓겨난다 — 되돌리려면
/// 건물을 다시 찾아 탭해야 하는, 비용이 큰 오조작이다.
///
/// 반대로 너무 넓게 잡으면 진짜 나가려는 탭이 안 먹는다. 15 m는 이 건물 폭
/// (약 180 m)의 8% 남짓이라, 화면에 건물이 꽉 찬 상태에서 손가락 두어 개
/// 폭이다 — 가장자리를 스친 오탭은 걸러내고, 건물에서 눈에 띄게 떨어진 곳을
/// 누른 탭은 그대로 통과한다.
const indoorExitTapMarginMeters = 15.0;

/// 이 탭이 **야외로 나가겠다는 뜻**인지. 실내 상태에서만 묻는다.
///
/// 외곽선 안이면 당연히 아니고, 바깥이어도 [marginMeters] 안쪽이면 오탭으로
/// 보고 아니라고 답한다. 외곽선을 모르면(아직 로드 전) 판정 근거가 없으므로
/// **나가지 않는 쪽**으로 기운다 — 잘못 나가는 비용이 잘못 머무는 비용보다
/// 크다(다시 들어오려면 건물을 찾아 탭해야 한다).
bool isTapOutsideBuildingForExit({
  required ll.LatLng point,
  required List<ll.LatLng>? footprint,
  double marginMeters = indoorExitTapMarginMeters,
}) {
  if (footprint == null || footprint.length < 3) return false;
  return metersToPolygon(point, footprint) > marginMeters;
}
