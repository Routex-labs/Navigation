import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/floor_graph.dart';
import 'route_progress.dart';

enum RouteGuidanceAction {
  straight,
  turnLeft,
  turnRight,
  escalator,
  elevator,
  arrived,
}

class RouteGuidanceInstruction {
  const RouteGuidanceInstruction({
    required this.action,
    required this.primaryText,
    required this.distanceToActionM,
  });

  final RouteGuidanceAction action;
  final String primaryText;
  final double distanceToActionM;
}

class RoutePolylineSplit {
  const RoutePolylineSplit({required this.completed, required this.remaining});

  final List<LocalPoint> completed;
  final List<LocalPoint> remaining;
}

/// 현재 투영점에서 경로를 지나온 구간과 남은 구간으로 나눈다.
RoutePolylineSplit? splitRouteAtProgress(
  List<LocalPoint> points,
  RouteProgress? progress,
) {
  final projected = progress?.projectedPoint;
  if (points.length < 2 || progress == null || projected == null) return null;
  final segment = progress.segmentIndex.clamp(0, points.length - 2);
  return RoutePolylineSplit(
    completed: [...points.take(segment + 1), projected],
    remaining: [projected, ...points.skip(segment + 1)],
  );
}

/// 현재 위치 뒤에서 첫 의미 있는 회전이나 층 이동을 찾아 한 줄 안내를 만든다.
RouteGuidanceInstruction buildRouteGuidance({
  required List<LocalPoint> localPoints,
  required List<LatLng> wgs84Points,
  required RouteProgress? progress,
  String? transferMode,
  bool allowArrival = true,
}) {
  final remainingM = progress?.remainingM ?? _polylineLength(localPoints);
  if (remainingM <= 3) {
    if (transferMode == 'escalator') {
      return const RouteGuidanceInstruction(
        action: RouteGuidanceAction.escalator,
        primaryText: '에스컬레이터를 탑승하세요',
        distanceToActionM: 0,
      );
    }
    if (transferMode == 'elevator') {
      return const RouteGuidanceInstruction(
        action: RouteGuidanceAction.elevator,
        primaryText: '엘리베이터를 탑승하세요',
        distanceToActionM: 0,
      );
    }
    if (allowArrival) {
      return const RouteGuidanceInstruction(
        action: RouteGuidanceAction.arrived,
        primaryText: '목적지에 도착했습니다',
        distanceToActionM: 0,
      );
    }
    return const RouteGuidanceInstruction(
      action: RouteGuidanceAction.straight,
      primaryText: '다음 층 이동 지점입니다',
      distanceToActionM: 0,
    );
  }

  if (progress != null &&
      localPoints.length == wgs84Points.length &&
      localPoints.length >= 3) {
    var distanceM = _distance(
      progress.projectedPoint ?? localPoints[progress.segmentIndex],
      localPoints[(progress.segmentIndex + 1).clamp(0, localPoints.length - 1)],
    );
    for (
      var vertex = progress.segmentIndex + 1;
      vertex < localPoints.length - 1;
      vertex++
    ) {
      final beforeM = _distance(localPoints[vertex - 1], localPoints[vertex]);
      final afterM = _distance(localPoints[vertex], localPoints[vertex + 1]);
      if (beforeM >= 1.5 && afterM >= 1.5) {
        final incoming = _bearing(wgs84Points[vertex - 1], wgs84Points[vertex]);
        final outgoing = _bearing(wgs84Points[vertex], wgs84Points[vertex + 1]);
        final turn = _signedTurn(outgoing - incoming);
        if (turn.abs() >= 35 && turn.abs() <= 150) {
          final right = turn > 0;
          final actionText = right ? '우회전' : '좌회전';
          return RouteGuidanceInstruction(
            action: right
                ? RouteGuidanceAction.turnRight
                : RouteGuidanceAction.turnLeft,
            primaryText: _actionDistanceText(distanceM, actionText),
            distanceToActionM: distanceM,
          );
        }
      }
      distanceM += afterM;
    }
  }

  if (transferMode == 'escalator') {
    return RouteGuidanceInstruction(
      action: RouteGuidanceAction.escalator,
      primaryText: _actionDistanceText(remainingM, '에스컬레이터 탑승'),
      distanceToActionM: remainingM,
    );
  }
  if (transferMode == 'elevator') {
    return RouteGuidanceInstruction(
      action: RouteGuidanceAction.elevator,
      primaryText: _actionDistanceText(remainingM, '엘리베이터 탑승'),
      distanceToActionM: remainingM,
    );
  }
  final rounded = _roundedGuidanceMeters(remainingM);
  return RouteGuidanceInstruction(
    action: RouteGuidanceAction.straight,
    primaryText: '$rounded미터 직진',
    distanceToActionM: remainingM,
  );
}

String _actionDistanceText(double distanceM, String action) {
  if (distanceM <= 7) return '잠시 후 $action';
  return '${_roundedGuidanceMeters(distanceM)}미터 후 $action';
}

int _roundedGuidanceMeters(double distanceM) {
  final unit = distanceM < 50 ? 5 : 10;
  return math.max(unit, (distanceM / unit).round() * unit);
}

double _polylineLength(List<LocalPoint> points) {
  var total = 0.0;
  for (var index = 1; index < points.length; index++) {
    total += _distance(points[index - 1], points[index]);
  }
  return total;
}

double _distance(LocalPoint a, LocalPoint b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  return math.sqrt(dx * dx + dy * dy);
}

double _bearing(LatLng from, LatLng to) {
  final meanLat = (from.latitude + to.latitude) * math.pi / 360;
  final east = (to.longitude - from.longitude) * math.cos(meanLat) * 111320.0;
  final north = (to.latitude - from.latitude) * 111320.0;
  return math.atan2(east, north) * 180 / math.pi;
}

double _signedTurn(double degrees) {
  var value = degrees % 360;
  if (value > 180) value -= 360;
  if (value < -180) value += 360;
  return value;
}
