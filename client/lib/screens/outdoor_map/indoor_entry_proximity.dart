/// 야외 지도 위 "실내 진입 오버레이"의 **위치** 정책.
///
/// zoom 정책([indoor_entry_zoom.dart])과 짝을 이룬다. 확대만으로 실내 모드를
/// 켜면 건물이 없는 엉뚱한 지역(예: 서울 반대편)을 확대했을 때도 층 선택기와
/// 위치 지정 버튼이 뜬다 — 도면은 한 장도 없는데 실내 UI만 올라오는 상태다.
/// 그래서 "카메라가 실내 도면이 있는 건물 근처인지"를 여기서 따로 판정하고,
/// 그 결과를 zoom 판정과 AND로 묶는다.
///
/// 화면 코드에서 분리한 이유는 zoom 정책과 같다. 판정이 지도 컨트롤러에 묶여
/// 있으면 위젯 테스트(MapLibre 플랫폼 뷰가 없어 컨트롤러가 null)에서 검증할 수
/// 없고, 그러면 "확대했더니 아무것도 없는 실내 모드" 증상이 조용히 되살아난다.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart' as ll;

/// 위도 1도의 미터. 클라이언트의 다른 좌표 계산(`domain/geo_transform.dart`)과
/// 같은 값을 쓴다 — 두 곳이 다른 상수를 쓰면 같은 좌표를 놓고 거리가 어긋난다.
const _metersPerDegreeLat = 111320.0;

/// 카메라 중심이 건물 footprint에서 이 거리 안이면 "건물이 주변에 있다"고 본다.
///
/// 값의 근거: 진입 임계값 zoom 17.5에서 폭 360 px 화면에 담기는 실제 폭은 약
/// 121 m이므로 화면 중심에서 좌우 테두리까지가 약 60 m다. 80 m는 거기에 약간의
/// 여유를 준 값이라 "건물이 화면 안에 있거나, 벽 바로 밖 인도를 확대한" 경우를
/// 덮는다. 데모 건물(더현대 서울, 약 180 x 190 m)은 중심에서 벽까지가 90 m 이상
/// 이므로, 건물을 확대하면 애초에 footprint **내부**라 거리가 0이 된다. 즉 이
/// 80 m는 건물 밖을 확대했을 때만 의미가 있는 톨러런스다.
///
/// 일부러 넉넉하게 잡지 않았다. 과잉 진입(건물이 없는데 실내 모드)은 이번에
/// 고치려는 버그 자체이고, 반대로 과소 진입은 사용자가 **건물을 직접 탭**하면
/// 바로 복구되기 때문이다. 애매하면 좁게 잡는 쪽이 안전하다.
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
