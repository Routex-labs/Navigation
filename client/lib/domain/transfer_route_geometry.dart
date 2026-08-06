import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/building_graph.dart';
import '../models/floor_graph.dart';
import '../models/floor_plan.dart';

/// 선택된 층간 전이와 연결된 에스컬레이터 폴리곤의 긴 중심축을 반환한다.
///
/// 그래프의 층간 노드 좌표와 지도에 그린 에스컬레이터 폴리곤은 별도 데이터다.
/// 노드 두 점만 이으면 초록 구조물과 어긋날 수 있다. 서버 데이터에서 에스컬레이터
/// 도형의 `entranceNodeId`는 실제 탑승 노드가 아니라 주변 junction을 가리키므로,
/// ID가 아닌 동일 로컬 좌표계에서 가장 가까운 도형을 고르고 그 중심축을 표시한다.
List<LatLng> transferRoutePointsOnFloor(
  IndoorRouteSegment segment,
  FloorPlan? floorPlan,
  FloorGraph? floorGraph,
) {
  final nodeId = segment.transferFromNodeId;
  if (segment.transferModeToNext != 'escalator' ||
      nodeId == null ||
      floorPlan == null ||
      floorGraph == null) {
    return segment.transferPointsToNext;
  }
  final transferNode = floorGraph.nodes
      .where((node) => node.id == nodeId)
      .firstOrNull;
  if (transferNode == null) return segment.transferPointsToNext;

  final candidates = floorPlan.stores
      .where(
        (store) =>
            store.subcategory == '에스컬레이터' &&
            store.polygon.length >= 4 &&
            store.polygonLocalM.length >= 4,
      )
      .toList();
  if (candidates.isEmpty) return segment.transferPointsToNext;

  candidates.sort((a, b) {
    final aDistance = _distanceToPolygon(
      transferNode.xM,
      transferNode.yM,
      a.polygonLocalM,
    );
    final bDistance = _distanceToPolygon(
      transferNode.xM,
      transferNode.yM,
      b.polygonLocalM,
    );
    return aDistance.compareTo(bDistance);
  });

  final selected = candidates.first;
  final selectedDistance = _distanceToPolygon(
    transferNode.xM,
    transferNode.yM,
    selected.polygonLocalM,
  );
  // 폴리곤 데이터가 누락되거나 좌표계가 어긋난 층에서 멀리 떨어진 아무
  // 에스컬레이터나 고르는 것보다 그래프의 원래 전이선을 유지하는 편이 안전하다.
  if (selectedDistance > 12) return segment.transferPointsToNext;

  final polygon = selected.polygon;
  final centerLat =
      polygon.map((p) => p.latitude).reduce((a, b) => a + b) / polygon.length;
  final centerLng =
      polygon.map((p) => p.longitude).reduce((a, b) => a + b) / polygon.length;
  final lngScale = math.cos(centerLat * math.pi / 180);
  var xx = 0.0;
  var xy = 0.0;
  var yy = 0.0;
  for (final point in polygon) {
    final x = (point.longitude - centerLng) * lngScale;
    final y = point.latitude - centerLat;
    xx += x * x;
    xy += x * y;
    yy += y * y;
  }
  final angle = 0.5 * math.atan2(2 * xy, xx - yy);
  final axisX = math.cos(angle);
  final axisY = math.sin(angle);
  var minProjection = double.infinity;
  var maxProjection = double.negativeInfinity;
  for (final point in polygon) {
    final x = (point.longitude - centerLng) * lngScale;
    final y = point.latitude - centerLat;
    final projection = x * axisX + y * axisY;
    minProjection = math.min(minProjection, projection);
    maxProjection = math.max(maxProjection, projection);
  }
  LatLng at(double projection) => LatLng(
    centerLat + axisY * projection,
    centerLng + axisX * projection / lngScale,
  );
  final a = at(minProjection);
  final b = at(maxProjection);
  final routeEnd = segment.route.points.lastOrNull;
  if (routeEnd == null) return [a, b];
  const distance = Distance();
  final axis = distance(a, routeEnd) <= distance(b, routeEnd) ? [a, b] : [b, a];

  // 보행선의 탑승 노드에서 에스컬레이터 축이 끊겨 보이지 않게 연결한다.
  // 선택된 축 자체는 실제 초록 폴리곤의 긴 방향을 그대로 유지한다.
  return distance(routeEnd, axis.first) < 0.15 ? axis : [routeEnd, ...axis];
}

double _distanceToPolygon(double x, double y, List<LocalFloorPoint> polygon) {
  var inside = false;
  var nearestSquared = double.infinity;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[j];
    final b = polygon[i];
    final crosses =
        ((a.y > y) != (b.y > y)) &&
        (x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x);
    if (crosses) inside = !inside;
    nearestSquared = math.min(
      nearestSquared,
      _distanceToSegmentSquared(x, y, a.x, a.y, b.x, b.y),
    );
  }
  return inside ? 0 : math.sqrt(nearestSquared);
}

double _distanceToSegmentSquared(
  double x,
  double y,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final dx = bx - ax;
  final dy = by - ay;
  if (dx == 0 && dy == 0) {
    return math.pow(x - ax, 2).toDouble() + math.pow(y - ay, 2).toDouble();
  }
  final t = (((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)).clamp(
    0.0,
    1.0,
  );
  final nearestX = ax + t * dx;
  final nearestY = ay + t * dy;
  return math.pow(x - nearestX, 2).toDouble() +
      math.pow(y - nearestY, 2).toDouble();
}
