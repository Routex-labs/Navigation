import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/floor_graph.dart';
import 'route_movement.dart';
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
  TravelDirectionState travelDirectionState = TravelDirectionState.forward,
  String? transferMode,
  bool allowArrival = true,
  double arrivalThresholdM = 5,
}) {
  if (travelDirectionState == TravelDirectionState.reverseConfirmed) {
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

// ---------------------------------------------------------------------------
// 경로 전체 단계 목록
// ---------------------------------------------------------------------------

/// 단계 목록의 한 줄. 지도앱의 "직진 40m → 우회전 → …" 목록에서 한 행이다.
///
/// [action]은 실시간 안내([RouteGuidanceInstruction])와 같은 enum을 쓴다 —
/// 목록의 아이콘·용어가 걷는 중 배너와 어긋나면 같은 지시를 두 이름으로
/// 부르게 된다.
class RouteStep {
  const RouteStep({
    required this.action,
    this.distanceM = 0,
    this.fromFloor,
    this.toFloor,
  });

  final RouteGuidanceAction action;

  /// [RouteGuidanceAction.straight]에서만 의미 있다 — 이 직진 구간의 길이(m).
  final double distanceM;

  /// 층 이동([RouteGuidanceAction.escalator]/[elevator])의 출발·도착 층 라벨.
  final String? fromFloor;
  final String? toFloor;
}

/// [buildRouteStepList]의 입력 한 조각 — 한 층 안에서 이어지는 폴리라인과
/// 다음 층으로 넘어가는 수단.
///
/// [IndoorRouteSegment]를 그대로 받지 않는 이유: 그 모델은 다층 경로 전용이라
/// 단일 층 경로는 이 함수를 못 쓰게 된다. 필요한 필드만 뽑은 record면 단일 층
/// 호출부는 transferModeToNext에 null을 주면 된다.
typedef RouteStepLeg = ({
  List<LatLng> wgs84Points,
  List<LocalPoint> localPoints,
  String floorLabel,
  String? transferModeToNext,
  String? nextFloorLabel,
});

/// 경로 전체를 "직진 N미터 → 우회전 → … → 에스컬레이터 → … → 도착" 단계
/// 목록으로 편다.
///
/// 회전 판정은 실시간 안내([buildRouteGuidance])와 **같은 임계값**을 쓴다 —
/// 변 1.5 m 이상, 회전각 35~150도. 목록에는 회전으로 적혔는데 걷다 보니
/// 배너에는 안 나오는(또는 반대) 어긋남을 만들지 않기 위해서다.
///
/// 거리는 층 로컬 좌표(m)로 재고, 로컬 좌표가 없으면([IndoorRoute.fromJson]
/// 직후) wgs84 근사로 잰다. 둘의 오차는 목록에 적는 반올림 단위(5 m) 아래다.
List<RouteStep> buildRouteStepList(List<RouteStepLeg> legs) {
  final steps = <RouteStep>[];
  for (final leg in legs) {
    final wgs84 = leg.wgs84Points;
    if (wgs84.length >= 2) {
      final useLocal = leg.localPoints.length == wgs84.length;
      double edgeM(int from, int to) => useLocal
          ? _distance(leg.localPoints[from], leg.localPoints[to])
          : _wgs84DistanceMeters(wgs84[from], wgs84[to]);

      var straightM = 0.0;
      for (var vertex = 0; vertex < wgs84.length - 1; vertex++) {
        straightM += edgeM(vertex, vertex + 1);
        final isLast = vertex + 2 >= wgs84.length;
        if (isLast) break;
        final beforeM = edgeM(vertex, vertex + 1);
        final afterM = edgeM(vertex + 1, vertex + 2);
        if (beforeM < 1.5 || afterM < 1.5) continue;
        final incoming = _bearing(wgs84[vertex], wgs84[vertex + 1]);
        final outgoing = _bearing(wgs84[vertex + 1], wgs84[vertex + 2]);
        final turn = _signedTurn(outgoing - incoming);
        if (turn.abs() < 35 || turn.abs() > 150) continue;
        steps.add(
          RouteStep(action: RouteGuidanceAction.straight, distanceM: straightM),
        );
        steps.add(
          RouteStep(
            action: turn > 0
                ? RouteGuidanceAction.turnRight
                : RouteGuidanceAction.turnLeft,
          ),
        );
        straightM = 0.0;
      }
      // 1 m 미만 꼬리는 버린다 — "0미터 직진" 행은 정보가 아니라 소음이다.
      if (straightM >= 1.0) {
        steps.add(
          RouteStep(action: RouteGuidanceAction.straight, distanceM: straightM),
        );
      }
    }
    final transfer = leg.transferModeToNext;
    if (transfer == 'escalator' || transfer == 'elevator') {
      steps.add(
        RouteStep(
          action: transfer == 'escalator'
              ? RouteGuidanceAction.escalator
              : RouteGuidanceAction.elevator,
          fromFloor: leg.floorLabel,
          toFloor: leg.nextFloorLabel,
        ),
      );
    }
  }
  if (steps.isNotEmpty) {
    steps.add(const RouteStep(action: RouteGuidanceAction.arrived));
  }
  return steps;
}

/// 단계 한 줄의 표시 문구. 걷는 중 배너와 같은 반올림 규칙을 쓴다.
String routeStepText(RouteStep step) => switch (step.action) {
  RouteGuidanceAction.straight =>
    '${_roundedGuidanceMeters(step.distanceM)}미터 직진',
  RouteGuidanceAction.turnLeft => '좌회전',
  RouteGuidanceAction.turnRight => '우회전',
  RouteGuidanceAction.escalator => _transferText('에스컬레이터', step),
  RouteGuidanceAction.elevator => _transferText('엘리베이터', step),
  RouteGuidanceAction.arrived => '도착',
  RouteGuidanceAction.wrongWay => '',
};

String _transferText(String mode, RouteStep step) {
  final from = step.fromFloor;
  final to = step.toFloor;
  if (from == null || to == null) return '$mode 탑승';
  return '$mode 탑승 · $from → $to';
}

/// wgs84 두 점 사이 거리(m) — 로컬 좌표가 없는 경로의 폴백. [_bearing]과 같은
/// 평면 근사라, 두 계산이 같은 왜곡을 공유한다.
double _wgs84DistanceMeters(LatLng a, LatLng b) {
  final meanLat = (a.latitude + b.latitude) * math.pi / 360;
  final east = (b.longitude - a.longitude) * math.cos(meanLat) * 111320.0;
  final north = (b.latitude - a.latitude) * 111320.0;
  return math.sqrt(east * east + north * north);
}
