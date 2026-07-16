/// local_m(건물 로컬 평면 좌표) <-> WGS84 6-DOF affine 변환.
///
/// api/app/domain/georeference.py, api/app/queries/geo_transform.py의 포팅이다.
/// 백엔드는 건물 Node들의 (x_m, y_m, lat, lng) 실측 대응점으로 이 변환을
/// 요청마다 즉석 피팅해서 /route 응답의 path_points_wgs84를 만든다.
///
/// GraphNodeResponse(= [GraphNode])가 x_m/y_m과 lat/lng을 이미 함께 내려주므로,
/// 그래프 노드 자체를 대응점 삼아 클라이언트에서 같은 변환을 재구성할 수 있다.
/// 이러면 클라이언트가 새 API 없이도 다익스트라로 구한 local_m 경로를 지도에
/// 그릴 WGS84 폴리라인으로 바꿀 수 있다.
library;

import 'dart:math' as math;

import '../models/floor_graph.dart';

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
  (double lat, double lng) apply(double xM, double yM) {
    final u = a * xM + b * yM + tx;
    final v = c * xM + d * yM + ty;
    return (v, u / lngScale);
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
  final meanLat = pairs.map((p) => p.lat).reduce((a, b) => a + b) / pairs.length;
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
