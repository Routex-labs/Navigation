/// 건물을 세로로 세워 화면에 담기 위한 기하 계산.
///
/// 지도는 기본이 정북 정렬인데 건물은 아무 방향으로나 앉아 있다. 더현대 서울은
/// 정북 기준 약 53도 돌아가 있어서, 북쪽을 위로 둔 채 확대하면 건물이 화면에
/// **비스듬히 누워** 들어온다. 세로로 긴 폰 화면에 가로로 누운 사각형을 담는
/// 꼴이라 좌우에 빈 공간이 남고 도면은 그만큼 작아진다.
///
/// 그래서 건물의 **긴 축을 화면 세로에 맞춰** 지도를 돌린다. 같은 배율에서
/// 도면이 훨씬 크게 들어오고, 사용자가 보는 방향(폰을 든 방향)과 건물 축이
/// 나란해져 "이 건물 안에 있다"는 감각도 맞는다.
///
/// 화면 코드에서 분리한 이유는 [indoor_entry_zoom.dart]와 같다 — 지도 컨트롤러에
/// 묶여 있으면 위젯 테스트에서 검증할 수 없고, 각도 계산은 부호 하나만 틀려도
/// 조용히 90도씩 어긋난다.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart' as ll;

/// 위도 1도의 미터. 다른 좌표 계산과 같은 값을 쓴다
/// (`indoor_entry_proximity.dart`, `domain/geo_transform.dart`).
const _metersPerDegreeLat = 111320.0;

/// 건물을 감싸는 **최소 넓이 직사각형**.
///
/// 축 정렬 경계 상자(`polygonWidthMeters`)와 다르다. 그쪽은 정북 기준이라 돌아앉은
/// 건물에서는 실제보다 훨씬 큰 상자가 나온다 — 더현대 서울은 로컬 295 x 148 m가
/// 정북 정렬로는 286 x 305 m가 된다. 여기서 구하는 것은 건물에 **딱 맞게 돌아간**
/// 상자이고, 그 상자의 긴 변이 곧 건물의 긴 축이다.
typedef BuildingBox = ({
  /// 긴 변의 길이(m).
  double longSideM,

  /// 짧은 변의 길이(m).
  double shortSideM,

  /// 긴 변이 향하는 방위각(북쪽 기준 시계방향, 0~180 미만).
  ///
  /// 축은 선이라 방향이 둘이다(θ와 θ+180). 여기서는 0~180으로 정규화해 두고,
  /// 어느 쪽을 위로 둘지는 [portraitBearingFor]가 정한다.
  double longAxisAzimuthDeg,
});

/// 각도 탐색 간격(도). 0.5도면 방위가 최대 0.25도 어긋나는데, 그 정도는 화면에서
/// 구분되지 않는다. 더 촘촘히 훑어도 결과가 눈에 띄게 좋아지지 않고 계산만 는다
/// (20점 x 360스텝이라 지금도 무시할 수준이다).
const _sweepStepDeg = 0.5;

/// [footprint]를 감싸는 최소 넓이 직사각형을 구한다. 점이 3개 미만이면 null.
///
/// 회전 캘리퍼스 대신 **각도를 훑는다.** 0~180도를 [_sweepStepDeg]씩 돌려 가며
/// 축 정렬 상자의 넓이를 재고 가장 작은 것을 고른다. 볼록 껍질을 먼저 구하는
/// 정석보다 코드가 짧고, 이 규모(수십 점)에서는 비용도 문제가 되지 않는다.
/// 무엇보다 **틀리기 어렵다** — 최소 넓이라는 정의를 그대로 옮긴 것이라, 부호나
/// 순회 방향 실수로 조용히 90도 어긋날 여지가 없다.
BuildingBox? minAreaBoxFor(List<ll.LatLng> footprint) {
  if (footprint.length < 3) return null;

  // 위경도를 미터 평면으로 편다. 경도 축은 cos(위도)로 줄여야 서울 위도에서
  // 동서 거리가 26% 부풀지 않는다(`metersToPolygon`과 같은 근사).
  var latSum = 0.0;
  var lngSum = 0.0;
  for (final p in footprint) {
    latSum += p.latitude;
    lngSum += p.longitude;
  }
  final lat0 = latSum / footprint.length;
  final lng0 = lngSum / footprint.length;
  final mPerDegLng = _metersPerDegreeLat * math.cos(lat0 * math.pi / 180);

  final xs = <double>[];
  final ys = <double>[];
  for (final p in footprint) {
    xs.add((p.longitude - lng0) * mPerDegLng); // 동쪽 +
    ys.add((p.latitude - lat0) * _metersPerDegreeLat); // 북쪽 +
  }

  var bestArea = double.infinity;
  var bestU = 0.0;
  var bestV = 0.0;
  var bestDeg = 0.0;
  for (var deg = 0.0; deg < 180.0; deg += _sweepStepDeg) {
    final rad = deg * math.pi / 180;
    final c = math.cos(rad);
    final s = math.sin(rad);
    var minU = double.infinity;
    var maxU = double.negativeInfinity;
    var minV = double.infinity;
    var maxV = double.negativeInfinity;
    for (var i = 0; i < xs.length; i++) {
      final u = xs[i] * c + ys[i] * s;
      final v = -xs[i] * s + ys[i] * c;
      if (u < minU) minU = u;
      if (u > maxU) maxU = u;
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final w = maxU - minU;
    final h = maxV - minV;
    final area = w * h;
    // 엄격한 `<`라서 동점이면 먼저 훑은 각이 남는다 — 같은 건물에서 매번 같은
    // 결과가 나와야 한다(정사각형에 가까운 건물이 두 축 사이를 오가면 안 된다).
    if (area < bestArea) {
      bestArea = area;
      bestU = w;
      bestV = h;
      bestDeg = deg;
    }
  }

  // u축은 (동, 북) 평면에서 방향 (cos deg, sin deg)이다. 방위각은 북쪽 기준
  // 시계방향이므로 atan2(동, 북) = atan2(cos deg, sin deg) = 90 - deg.
  // v축은 그와 직교하므로 방위각이 -deg다.
  final uAzimuth = _normalize180(90 - bestDeg);
  final vAzimuth = _normalize180(-bestDeg);

  return bestU >= bestV
      ? (longSideM: bestU, shortSideM: bestV, longAxisAzimuthDeg: uAzimuth)
      : (longSideM: bestV, shortSideM: bestU, longAxisAzimuthDeg: vAzimuth);
}

/// 긴 축이 화면 **세로**로 서도록 하는 카메라 bearing(0~360 미만).
///
/// MapLibre의 bearing은 "화면 위쪽에 오는 나침반 방향"이다(카메라가 바라보는
/// 방향, 북쪽 기준 시계방향). 그래서 긴 축의 방위각을 그대로 주면 그 축이 위를
/// 향하고, 건물이 세로로 선다.
///
/// 축은 선이라 [longAxisAzimuthDeg]와 그 반대편(+180) 둘 다 세로로 세운다.
/// 둘 중 **지금 카메라에서 덜 도는 쪽**을 고른다 — 어느 쪽을 위로 두든 화면
/// 모양은 같은데, 굳이 170도를 돌면 지도가 한 바퀴 도는 것처럼 보인다.
/// [currentBearing]을 모르면 정북(0)에서 시작한다고 본다.
double portraitBearingFor({
  required double longAxisAzimuthDeg,
  double? currentBearing,
}) {
  final from = (currentBearing != null && currentBearing.isFinite)
      ? currentBearing
      : 0.0;
  final a = _normalize360(longAxisAzimuthDeg);
  final b = _normalize360(longAxisAzimuthDeg + 180);
  return _turnMagnitude(from, a) <= _turnMagnitude(from, b) ? a : b;
}

/// 경로 폴리라인을 감싸는 최소 넓이 상자. [minAreaBoxFor]와 같은 상자를 구하되
/// **퇴화한 입력을 견딘다.**
///
/// 경로는 건물 외곽선과 달리 넓이가 없을 수 있다. 그대로 [minAreaBoxFor]에
/// 넣으면 두 곳에서 깨진다.
///
/// 1. **점이 둘뿐인 곧은 경로**(복도 한 구간)는 3점 미만이라 null이 나온다.
///    중점을 끼워 3점으로 만든다 — 어차피 일직선이라 상자 모양은 그대로다.
/// 2. **일직선 경로**는 짧은 변이 0으로 수렴한다. `zoomToFitWidth`가
///    `log(가용폭 / 폭)`이라, 그 상자를 카메라에 넘기면 zoom이 무한대로
///    발산해 지도가 사라진다. 그래서 두 변 모두 [minSideM]으로 받친다.
///
/// 점이 2개 미만이면 담을 것이 없으므로 null.
///
/// **긴 축 방위각은 손대지 않는다.** 변 길이만 받치므로, 곧은 경로에서도 갈
/// 방향은 그대로 나온다 — 그 값이 곧 카메라를 세우는 기준이다
/// ([portraitBearingFor]).
BuildingBox? routeBoxFor(
  List<ll.LatLng> points, {
  required double minSideM,
}) {
  if (points.length < 2) return null;
  final dense = points.length >= 3
      ? points
      : <ll.LatLng>[
          points.first,
          ll.LatLng(
            (points.first.latitude + points.last.latitude) / 2,
            (points.first.longitude + points.last.longitude) / 2,
          ),
          points.last,
        ];
  final box = minAreaBoxFor(dense);
  if (box == null) return null;
  return (
    longSideM: math.max(box.longSideM, minSideM),
    shortSideM: math.max(box.shortSideM, minSideM),
    longAxisAzimuthDeg: box.longAxisAzimuthDeg,
  );
}

/// [origin]에서 방위각 [azimuthDeg](북 기준 시계방향) 쪽으로 [meters]만큼
/// 떨어진 지점.
///
/// 카메라 목표점을 화면 위/아래로 밀어 도면을 chrome이 가리지 않는 띠 한가운데에
/// 놓을 때 쓴다. 지도가 돌아가 있으면 "화면 위"가 곧 북쪽이 아니므로, 방위각을
/// 받아 그 방향으로 밀어야 한다.
ll.LatLng offsetByMeters(
  ll.LatLng origin, {
  required double azimuthDeg,
  required double meters,
}) {
  final rad = azimuthDeg * math.pi / 180;
  // 방위각 0이 북(+lat), 90이 동(+lng)이다.
  final north = meters * math.cos(rad);
  final east = meters * math.sin(rad);
  final mPerDegLng =
      _metersPerDegreeLat * math.cos(origin.latitude * math.pi / 180);
  return ll.LatLng(
    origin.latitude + north / _metersPerDegreeLat,
    // 극점 근처에서는 cos이 0으로 수렴해 발산한다. 실내 도면이 있는 건물에서는
    // 생기지 않지만, 0으로 나누는 것보다 제자리에 두는 편이 안전하다.
    mPerDegLng.abs() < 1e-9
        ? origin.longitude
        : origin.longitude + east / mPerDegLng,
  );
}

/// [from]에서 [to]까지의 최단 회전량(0~180).
double _turnMagnitude(double from, double to) {
  final diff = (_normalize360(to - from)).abs();
  return diff > 180 ? 360 - diff : diff;
}

double _normalize360(double deg) {
  final r = deg % 360;
  return r < 0 ? r + 360 : r;
}

/// 축(선)의 방위각을 0~180으로 접는다. 180도는 0도와 같은 축이다.
double _normalize180(double deg) {
  final r = deg % 180;
  return r < 0 ? r + 180 : r;
}
