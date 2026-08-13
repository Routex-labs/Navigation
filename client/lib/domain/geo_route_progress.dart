import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// 위경도 경로를 미터 좌표에서 투영한 결과.
class GeoRouteProgress {
  const GeoRouteProgress({
    required this.traveledM,
    required this.remainingM,
    required this.offsetM,
    required this.segmentIndex,
    required this.projectedPoint,
    required this.reacquired,
  });

  final double traveledM;
  final double remainingM;
  final double offsetM;
  final int segmentIndex;
  final LatLng projectedPoint;

  /// 이전 진행거리 주변에서 후보를 찾지 못해 전역 후보로 되돌렸는지 여부.
  /// 야외 표시에서는 이 값을 받은 틱을 채택하지 않고 직전 표시를 유지한다.
  final bool reacquired;
}

/// GPS 위치를 위경도 폴리라인에 미터 단위로 투영한다.
///
/// 단순히 latitude/longitude 차이를 비교하지 않고, 경로 첫 점을 기준으로 한
/// 국소 동-북 좌표계에서 투영한다. 도심 도보 경로에서는 이 방식으로 진행거리,
/// 경로 이탈 거리, 회색/파란 분할점이 같은 미터 기준을 공유한다.
GeoRouteProgress? computeGeoRouteProgress({
  required List<LatLng> routePoints,
  required LatLng position,
  double? previousTraveledM,
  double searchWindowM = 30.0,
}) {
  if (routePoints.length < 2) return null;

  final reference = routePoints.first;
  final projectedPosition = _toMetric(position, reference);
  final candidates = <_Projection>[];
  var cumulativeM = 0.0;

  for (var index = 0; index < routePoints.length - 1; index++) {
    final start = _toMetric(routePoints[index], reference);
    final end = _toMetric(routePoints[index + 1], reference);
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final lengthSq = dx * dx + dy * dy;
    if (lengthSq == 0) continue;

    final lengthM = math.sqrt(lengthSq);
    final t =
        ((projectedPosition.x - start.x) * dx +
            (projectedPosition.y - start.y) * dy) /
        lengthSq;
    final clampedT = t.clamp(0.0, 1.0);
    final footX = start.x + clampedT * dx;
    final footY = start.y + clampedT * dy;
    final offsetX = projectedPosition.x - footX;
    final offsetY = projectedPosition.y - footY;

    candidates.add(
      _Projection(
        segmentIndex: index,
        traveledM: cumulativeM + clampedT * lengthM,
        offsetM: math.sqrt(offsetX * offsetX + offsetY * offsetY),
        x: footX,
        y: footY,
      ),
    );
    cumulativeM += lengthM;
  }

  if (candidates.isEmpty) return null;

  final inWindow = previousTraveledM == null
      ? candidates
      : candidates
            .where(
              (candidate) =>
                  (candidate.traveledM - previousTraveledM).abs() <=
                  searchWindowM,
            )
            .toList(growable: false);
  final reacquired = previousTraveledM != null && inWindow.isEmpty;
  final pool = inWindow.isEmpty ? candidates : inWindow;
  pool.sort((a, b) => a.offsetM.compareTo(b.offsetM));
  final best = pool.first;
  final projectedPoint = _fromMetric(_MetricPoint(best.x, best.y), reference);

  return GeoRouteProgress(
    traveledM: best.traveledM,
    remainingM: math.max(0.0, cumulativeM - best.traveledM),
    offsetM: best.offsetM,
    segmentIndex: best.segmentIndex,
    projectedPoint: projectedPoint,
    reacquired: reacquired,
  );
}

class _Projection {
  const _Projection({
    required this.segmentIndex,
    required this.traveledM,
    required this.offsetM,
    required this.x,
    required this.y,
  });

  final int segmentIndex;
  final double traveledM;
  final double offsetM;
  final double x;
  final double y;
}

class _MetricPoint {
  const _MetricPoint(this.x, this.y);

  final double x;
  final double y;
}

_MetricPoint _toMetric(LatLng point, LatLng reference) {
  final meanLat = (point.latitude + reference.latitude) * math.pi / 360.0;
  return _MetricPoint(
    (point.longitude - reference.longitude) * math.cos(meanLat) * 111320.0,
    (point.latitude - reference.latitude) * 111320.0,
  );
}

LatLng _fromMetric(_MetricPoint point, LatLng reference) {
  final latitude = reference.latitude + point.y / 111320.0;
  final meanLat = (latitude + reference.latitude) * math.pi / 360.0;
  final metersPerLongitudeDegree = math.cos(meanLat) * 111320.0;
  final longitude = metersPerLongitudeDegree == 0
      ? reference.longitude
      : reference.longitude + point.x / metersPerLongitudeDegree;
  return LatLng(latitude, longitude);
}
