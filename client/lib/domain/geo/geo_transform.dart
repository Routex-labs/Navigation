/// local_m(건물 로컬 평면 좌표) <-> WGS84 6-DOF affine 변환.
///
/// 백엔드(`georeference.py`)의 포팅이다. 그래프 노드가 x_m/y_m과 lat/lng을 함께
/// 내려주므로 그 노드를 대응점 삼아 같은 변환을 클라이언트에서 재구성한다 —
/// 새 API 없이 다익스트라 결과를 지도에 그릴 수 있다.
library;

import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../models/building/floor_graph.dart';

/// 실측 wgs84 앵커가 전혀 없는 합성 데이터셋을 임의로 배치할
/// 기준점(서울시청). geo_transform.py의 _SYNTHETIC_ANCHOR_*와 반드시 같은 값을
/// 유지해야 서버가 계산했던 것과 같은 위치에 경로가 그려진다.
const _syntheticAnchorLat = 37.5665;
const _syntheticAnchorLng = 126.9780;
const _metersPerDegreeLat = 111320.0;

class AffineTransform {
  const AffineTransform({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.tx,
    required this.ty,
    this.lngScale = 1.0,
  });

  final double a;
  final double b;
  final double c;
  final double d;
  final double tx;
  final double ty;
  final double lngScale;

  /// local_m 좌표 하나를 (lat, lng)로 변환한다.
  (double, double) apply(double xM, double yM) {
    final u = a * xM + b * yM + tx;
    final v = c * xM + d * yM + ty;
    return (v, u / lngScale);
  }

  /// 지도에서 사용자가 탭한 WGS84 위치를 floor `local_m`으로 되돌린다.
  ///
  /// PDR anchor는 반드시 floor 좌표계에서 보관해야 하므로, UI tap 좌표를
  /// 이 역변환으로 바꾼 뒤 `FloorCoordinateTransform`(features/indoor_navigation/
  /// contract/pdr_anchor.dart)에 넘긴다. 그래프의 대응점이 퇴화해 변환이 특이한
  /// 경우만 null이다.
  ///
  /// **그 경로는 글자로만 적는다.** 대괄호로 걸면 import가 따라붙고, 이 파일은
  /// domain이라 features를 import하는 순간 계층이 거꾸로 선다.
  (double, double)? invert(double lat, double lng) {
    final u = lng * lngScale - tx;
    final v = lat - ty;
    final determinant = a * d - b * c;
    if (determinant.abs() < 1e-12) return null;
    return ((d * u - b * v) / determinant, (-c * u + a * v) / determinant);
  }
}

class _Pair {
  const _Pair(this.x, this.y, this.lat, this.lng);
  final double x;
  final double y;
  final double lat;
  final double lng;
}

/// 노드의 (x_m, y_m, lat, lng) 대응점들로 local_m -> WGS84 affine 변환을 피팅한다.
/// 실측 앵커가 3개 미만이거나(건물에 wgs84 앵커가 없음) 한 직선 위에 몰려 있어
/// 유일해를 구할 수 없으면(예: 노드가 한 방향 복도에만 있는 층) geo_transform.py와
/// 동일한 합성 대응점으로 대체한다 — 그래야 이런 건물도 서버와 같은 위치에 뜬다.
AffineTransform fitFloorGeoTransform(List<GraphNode> nodes) {
  final realPairs = nodes
      .where((node) => node.lat != null && node.lng != null)
      .map((node) => _Pair(node.xM, node.yM, node.lat!, node.lng!))
      .toList();

  if (realPairs.length >= 3) {
    final transform = _fitWgs84Transform(realPairs);
    if (transform != null) return transform;
  }

  // _syntheticPairs()는 한 직선 위에 있지 않은 3점(L자형)이라 항상 풀린다.
  return _fitWgs84Transform(_syntheticPairs())!;
}

/// 자북 기준 PDR의 `(east, north)` 증분을 floor `local_m`의 `(x, y)` 증분으로
/// 바꾸는 2×2 선형 변환이다.
///
/// 기본값은 기존 데이터셋과의 호환을 위한 항등이다. 실제 평면도에서는
/// WGS84 대응점으로부터 [fitPdrToFloorAxes]가 계산한 값을 사용한다. 예를 들어
/// 더현대 1F처럼 `+x=동쪽, +y=남쪽`인 경우 `(east, north) -> (east, -north)`가
/// 되어 북쪽 보행이 지도에서 반대로 표시되는 일을 막는다.
class PdrToFloorAxes {
  const PdrToFloorAxes({
    required this.eastToX,
    required this.northToX,
    required this.eastToY,
    required this.northToY,
  });

  const PdrToFloorAxes.identity()
    : eastToX = 1,
      northToX = 0,
      eastToY = 0,
      northToY = 1;

  final double eastToX;
  final double northToX;
  final double eastToY;
  final double northToY;

  PdrLocalPoint apply(PdrLocalPoint point) => PdrLocalPoint(
    eastToX * point.eastM + northToX * point.northM,
    eastToY * point.eastM + northToY * point.northM,
  );

  /// floor `local_m` 방향을 자북 기준 PDR `(east, north)` 방향으로 되돌린다.
  ///
  /// 실측 affine가 퇴화한 경우 잘못된 방향으로 보정하지 않도록 null을 반환한다.
  PdrLocalPoint? inverseApply(PdrLocalPoint point) {
    final determinant = eastToX * northToY - northToX * eastToY;
    if (determinant.abs() < 1e-12) return null;
    return PdrLocalPoint(
      (northToY * point.eastM - northToX * point.northM) / determinant,
      (-eastToY * point.eastM + eastToX * point.northM) / determinant,
    );
  }
}

/// 자북 기준 PDR 좌표 `(east, north)`를 이 층의 `local_m` 증분으로 바꾼다.
///
/// [AffineTransform]은 `local_m -> (lng*cos(lat), lat)` 선형부를 갖는다.
/// 이를 역행렬로 풀면 실제 동·북쪽 1m가 평면도의 어느 축·부호로 움직이는지
/// 얻을 수 있다. 더현대 1F의 경우 local y가 북쪽이 아니라 남쪽으로 증가하므로
/// 결과는 거의 `(east, north) -> (east, -north)`다.
///
/// 좌표 대응점이 퇴화한 층은 기존 동작을 보존하도록 항등 변환을 쓴다.
PdrToFloorAxes fitPdrToFloorAxes(List<GraphNode> nodes) {
  final transform = fitFloorGeoTransform(nodes);
  final determinant = transform.a * transform.d - transform.b * transform.c;
  if (determinant.abs() < 1e-12) {
    return const PdrToFloorAxes.identity();
  }

  // 역 affine의 두 열은 east/north가 floor에서 향하는 방향이다. local_m이
  // 실제 미터가 된 뒤에는 WGS84 fit의 미세한 scale/shear 오차를 PDR 거리에
  // 섞지 않도록 Gram-Schmidt로 직교 단위축만 남긴다.
  final eastScale = _metersPerDegreeLat * determinant;
  var eastX = transform.d / eastScale;
  var eastY = -transform.c / eastScale;
  final eastNorm = math.sqrt(eastX * eastX + eastY * eastY);
  if (eastNorm < 1e-12) return const PdrToFloorAxes.identity();
  eastX /= eastNorm;
  eastY /= eastNorm;

  var northX = -transform.b / eastScale;
  var northY = transform.a / eastScale;
  final projection = northX * eastX + northY * eastY;
  northX -= projection * eastX;
  northY -= projection * eastY;
  final northNorm = math.sqrt(northX * northX + northY * northY);
  if (northNorm < 1e-12) return const PdrToFloorAxes.identity();
  northX /= northNorm;
  northY /= northNorm;
  return PdrToFloorAxes(
    eastToX: eastX,
    northToX: northX,
    eastToY: eastY,
    northToY: northY,
  );
}

List<_Pair> _syntheticPairs() {
  final lngScale = math.cos(_syntheticAnchorLat * math.pi / 180);
  const localPoints = [(0.0, 0.0), (100.0, 0.0), (0.0, 100.0)];

  return [
    for (final (xM, yM) in localPoints)
      _Pair(
        xM,
        yM,
        _syntheticAnchorLat + yM / _metersPerDegreeLat,
        _syntheticAnchorLng + xM / (_metersPerDegreeLat * lngScale),
      ),
  ];
}

/// (x,y) -> (lng, lat) 대응점들로 6-DOF affine 변환을 최소자승 피팅한다.
/// 위도/경도 1도의 실제 거리가 다른 문제를 보정하기 위해 평균 위도의
/// cos값(lngScale)을 경도에 곱해 등방(isotropic) 공간으로 만든 뒤 피팅한다.
/// 대응점이 한 직선 위에 몰려 있어 유일해가 없으면 null을 반환한다.
AffineTransform? _fitWgs84Transform(List<_Pair> pairs) {
  final meanLat =
      pairs.map((p) => p.lat).reduce((a, b) => a + b) / pairs.length;
  final lngScale = math.cos(meanLat * math.pi / 180);

  // 정규방정식 (X^T X) w = X^T y를 u = a*x+b*y+tx, v = c*x+d*y+ty 각각 풀어
  // 최소자승해를 구한다(대응점이 정확히 3개면 두 시스템 모두 유일해).
  var sxx = 0.0, sxy = 0.0, sx = 0.0, syy = 0.0, sy = 0.0, n = 0.0;
  var sxu = 0.0, syu = 0.0, su = 0.0;
  var sxv = 0.0, syv = 0.0, sv = 0.0;

  for (final pair in pairs) {
    final u = pair.lng * lngScale;
    final v = pair.lat;

    sxx += pair.x * pair.x;
    sxy += pair.x * pair.y;
    sx += pair.x;
    syy += pair.y * pair.y;
    sy += pair.y;
    n += 1;

    sxu += pair.x * u;
    syu += pair.y * u;
    su += u;

    sxv += pair.x * v;
    syv += pair.y * v;
    sv += v;
  }

  final normal = [
    [sxx, sxy, sx],
    [sxy, syy, sy],
    [sx, sy, n],
  ];

  final abTx = _solve3x3(normal, [sxu, syu, su]);
  final cdTy = _solve3x3(normal, [sxv, syv, sv]);
  if (abTx == null || cdTy == null) return null;

  return AffineTransform(
    a: abTx[0],
    b: abTx[1],
    tx: abTx[2],
    c: cdTy[0],
    d: cdTy[1],
    ty: cdTy[2],
    lngScale: lngScale,
  );
}

/// 3x3 선형계 A*w=b를 크라메르 공식으로 푼다. 대응점이 한 직선 위에 몰려
/// 있어 A가 특이행렬이면(det≈0) null을 반환한다.
List<double>? _solve3x3(List<List<double>> a, List<double> b) {
  final det = _det3x3(a);
  if (det.abs() < 1e-9) return null;

  final w = List<double>.filled(3, 0);
  for (var col = 0; col < 3; col++) {
    final replaced = [
      [...a[0]],
      [...a[1]],
      [...a[2]],
    ];
    for (var row = 0; row < 3; row++) {
      replaced[row][col] = b[row];
    }
    w[col] = _det3x3(replaced) / det;
  }
  return w;
}

double _det3x3(List<List<double>> m) {
  return m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
      m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
      m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
}
