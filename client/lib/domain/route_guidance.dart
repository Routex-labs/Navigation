import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/floor_graph.dart';
import 'route_progress.dart';

enum RouteGuidanceAction {
  wrongWay,
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

/// 도착 안내가 뜬 뒤 경로를 스스로 지울지에 대한 결정.
enum ArrivalAutoClearDecision {
  /// 지금부터 [arrivalAutoClearDelay]를 세고 그 뒤에 경로를 지운다.
  schedule,

  /// 이미 세고 있다. 다시 걸지 않는다 — 매 걸음마다 다시 걸면 사용자가
  /// 도착 지점에서 제자리걸음만 해도 카운트다운이 영원히 처음으로 돌아간다.
  keep,

  /// 도착 상태가 아니다. 세고 있던 것이 있으면 취소한다.
  cancel,
}

/// 도착 안내를 읽을 시간을 준 뒤 경로를 지우기까지의 대기 시간.
///
/// 0으로 두면 "목적지에 도착했습니다"가 뜨는 프레임과 카드가 사라지는 프레임이
/// 같아져, 사용자는 안내를 못 본 채 경로만 사라진 것으로 읽는다. 반대로 너무
/// 길면 도착 뒤에도 남은 카드가 지도를 가린다. 한 줄 안내를 읽기에 충분한
/// 정도로 잡은 임의값이다.
const Duration arrivalAutoClearDelay = Duration(seconds: 5);

/// 지금 안내 상태에서 "안내를 자동으로 끝낼지"를 판단한다.
///
/// [hasMeasuredProgress]는 **실제로 측정된 진행률이 있는지**다. 이 값이 없으면
/// [buildRouteGuidance]는 남은거리를 폴리라인 전체 길이로 대신 계산하므로, 총
/// 길이가 도착 임계값보다 짧은 경로(바로 옆 매장)는 그리는 순간 `arrived`가
/// 된다. 그대로 자동 삭제를 걸면 사용자는 도착지를 고르자마자 경로가 사라지는
/// 것을 본다. 걸어서 도착한 것과 애초에 가까운 것은 다르므로, 자동 종료는
/// 측정된 진행률이 있을 때만 한다.
ArrivalAutoClearDecision decideArrivalAutoClear({
  required RouteGuidanceAction? action,
  required bool hasMeasuredProgress,
  required bool alreadyScheduled,
}) {
  if (action != RouteGuidanceAction.arrived || !hasMeasuredProgress) {
    return ArrivalAutoClearDecision.cancel;
  }
  return alreadyScheduled
      ? ArrivalAutoClearDecision.keep
      : ArrivalAutoClearDecision.schedule;
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
  double arrivalThresholdM = 5,
}) {
  if (progress?.wrongWay ?? false) {
    return const RouteGuidanceInstruction(
      action: RouteGuidanceAction.wrongWay,
      primaryText: '반대 방향입니다 · 뒤로 돌아가세요',
      distanceToActionM: 0,
    );
  }
  final remainingM = progress?.remainingM ?? _polylineLength(localPoints);
  if (remainingM <= arrivalThresholdM) {
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
