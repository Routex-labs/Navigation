import 'dart:math' as math;

import '../../models/floor_plan.dart';

class CardinalCalibrationResult {
  const CardinalCalibrationResult({
    required this.northMapBearingDeg,
    required this.landmarkCount,
    required this.rmsErrorPx,
    required this.reflected,
  });

  final double northMapBearingDeg;
  final int landmarkCount;
  final double rmsErrorPx;
  final bool reflected;
}

class _LandmarkPair {
  const _LandmarkPair(
    this.name,
    this.floorX,
    this.floorY,
    this.referenceEastPx,
    this.referenceNorthPx,
  );

  final String name;
  final double floorX;
  final double floorY;
  final double referenceEastPx;
  final double referenceNorthPx;
}

/// 현대백화점 1F 원본 도면과 사용자가 제공한 네이버 지도 북고정 캡처에서
/// 동시에 식별되는 비대칭 랜드마크 대응점이다.
///
/// 원본 도면 좌표는 dataset의 store centroid(source), reference 좌표는
/// 3644×2248 캡처에서 인식한 매장명 중심(동쪽=+x, 북쪽=+y)이다. 건물 외곽의
/// 가장 긴 변은 사용하지 않는다. 다섯 점 전체에 orthogonal Procrustes를
/// 적용해 90° 회전과 좌우 반전을 데이터로 결정한다.
const _theHyundaiLandmarks = [
  _LandmarkPair('보테가 베네타', 774.0158477, 1742.6111012, 1512.154324, 1385.826808),
  _LandmarkPair('불가리', 1033.7931184, 1784.6740091, 1602.193920, 1245.499904),
  _LandmarkPair('티파니앤코', 1340.0627900, 1175.3329370, 1999.433648, 1327.886856),
  _LandmarkPair('루이비통', 1757.9107743, 1488.6321912, 2012.675944, 1020.994392),
  _LandmarkPair('프라다', 1646.9228610, 1839.2571944, 1800.813784, 952.001024),
];

CardinalCalibrationResult? cardinalCalibrationForBuilding(
  String buildingId, {
  FloorPlan? floorPlan,
}) {
  if (buildingId != 'thehyundai-seoul') return null;

  // 실제 화면에 그려지는 WGS84 매장 중심을 우선 사용한다. 데이터 생성 과정의
  // x/y 축척이 달라져도 현재 도면 위 방위선이 같은 랜드마크를 기준으로 다시
  // 계산되므로, 별도의 각도 상수를 유지할 필요가 없다.
  final storesByName = {
    for (final store in floorPlan?.stores ?? const <StorePolygon>[])
      store.name: store,
  };
  if (_theHyundaiLandmarks.every(
    (landmark) => storesByName.containsKey(landmark.name),
  )) {
    final meanLatitude =
        _theHyundaiLandmarks
            .map((landmark) => storesByName[landmark.name]!.centroid.latitude)
            .reduce((a, b) => a + b) /
        _theHyundaiLandmarks.length;
    final longitudeScale = math.cos(meanLatitude * math.pi / 180);
    return _fitCardinalCalibration([
      for (final landmark in _theHyundaiLandmarks)
        _LandmarkPair(
          landmark.name,
          storesByName[landmark.name]!.centroid.longitude * longitudeScale,
          -storesByName[landmark.name]!.centroid.latitude,
          landmark.referenceEastPx,
          landmark.referenceNorthPx,
        ),
    ]);
  }

  return _fitCardinalCalibration(_theHyundaiLandmarks);
}

CardinalCalibrationResult _fitCardinalCalibration(
  List<_LandmarkPair> landmarks,
) {
  var floorCenterX = 0.0;
  var floorCenterY = 0.0;
  var referenceCenterX = 0.0;
  var referenceCenterY = 0.0;
  for (final point in landmarks) {
    floorCenterX += point.floorX;
    floorCenterY += point.floorY;
    referenceCenterX += point.referenceEastPx;
    referenceCenterY += point.referenceNorthPx;
  }
  floorCenterX /= landmarks.length;
  floorCenterY /= landmarks.length;
  referenceCenterX /= landmarks.length;
  referenceCenterY /= landmarks.length;

  // C = P^T Q. rotation과 reflection 후보의 닫힌형 해를 각각 구해 더 큰
  // correlation을 고른다. 이 비교가 좌우 반전 모호성을 제거한다.
  var a = 0.0, b = 0.0, c = 0.0, d = 0.0;
  for (final point in landmarks) {
    final px = point.floorX - floorCenterX;
    final py = point.floorY - floorCenterY;
    final qx = point.referenceEastPx - referenceCenterX;
    final qy = point.referenceNorthPx - referenceCenterY;
    a += px * qx;
    b += px * qy;
    c += py * qx;
    d += py * qy;
  }

  final rotationScore = math.sqrt((a + d) * (a + d) + (c - b) * (c - b));
  final reflectionScore = math.sqrt((a - d) * (a - d) + (b + c) * (b + c));
  final reflected = reflectionScore > rotationScore;

  final theta = reflected ? math.atan2(b + c, a - d) : math.atan2(c - b, a + d);
  final cosT = math.cos(theta);
  final sinT = math.sin(theta);
  final r00 = cosT;
  final r01 = reflected ? sinT : -sinT;
  final r10 = sinT;
  final r11 = reflected ? -cosT : cosT;

  var numerator = 0.0;
  var denominator = 0.0;
  for (final point in landmarks) {
    final px = point.floorX - floorCenterX;
    final py = point.floorY - floorCenterY;
    final qx = point.referenceEastPx - referenceCenterX;
    final qy = point.referenceNorthPx - referenceCenterY;
    final rx = px * r00 + py * r10;
    final ry = px * r01 + py * r11;
    numerator += rx * qx + ry * qy;
    denominator += px * px + py * py;
  }
  final scale = numerator / denominator;

  var squaredError = 0.0;
  for (final point in landmarks) {
    final px = point.floorX - floorCenterX;
    final py = point.floorY - floorCenterY;
    final qx = point.referenceEastPx - referenceCenterX;
    final qy = point.referenceNorthPx - referenceCenterY;
    final errorX = scale * (px * r00 + py * r10) - qx;
    final errorY = scale * (px * r01 + py * r11) - qy;
    squaredError += errorX * errorX + errorY * errorY;
  }

  // reference의 진북 (0, +1)을 도면 좌표로 역변환한다. landmark의 floorY는
  // 원본과 WGS84 모두 남쪽을 +방향으로 통일했으므로 atan2(x, -y)가 지도
  // bearing이다.
  final northFloorX = r01;
  final northFloorY = r11;
  final rawBearing = math.atan2(northFloorX, -northFloorY) * 180 / math.pi;
  final northMapBearing = (rawBearing % 360 + 360) % 360;

  return CardinalCalibrationResult(
    northMapBearingDeg: northMapBearing,
    landmarkCount: landmarks.length,
    rmsErrorPx: math.sqrt(squaredError / landmarks.length),
    reflected: reflected,
  );
}
