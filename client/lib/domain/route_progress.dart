/// 길찾기 경로를 기준으로 현재 위치를 해석한다 — 얼마나 왔고, 얼마나 남았고,
/// 지금 경로 위에 있는지.
///
/// **경로는 위치 추정에 개입하지 않는다.** 이 계산은 이미 확정된 보정 위치를
/// 입력으로 받아 경로 기준 값만 만들어 내는 단방향 소비자다. 반대 방향(경로
/// 간선을 우선해 위치를 끌어당기는 것)을 허용하면, 사용자가 실제로 다른 길로
/// 갔을 때도 화면상 위치는 경로 위에 얌전히 붙어 있어 앱이 거짓 안내를 계속
/// 하게 된다. 잘못된 이탈 판정은 사용자가 알아채지만, 조용히 틀린 위치는
/// 아무도 알아채지 못한다.
///
/// HTTP·Repository·PDR 패키지를 알지 못하는 순수 함수다.
library;

import 'dart:math' as math;

import '../models/floor_graph.dart';

/// 경로 기준으로 해석한 현재 위치.
class RouteProgress {
  const RouteProgress({
    required this.traveledM,
    required this.remainingM,
    required this.offsetM,
    required this.onRouteEdge,
    required this.reacquired,
    required this.segmentIndex,
    this.projectedPoint,
    this.headingErrorDeg,
    this.wrongWay = false,
  });

  /// 경로 시작점부터 투영점까지의 폴리라인 거리.
  final double traveledM;

  /// 투영점부터 경로 끝점까지의 폴리라인 거리.
  ///
  /// [traveledM] + [remainingM]은 폴리라인 전체 길이다. 간선 `lengthM` 합인
  /// `IndoorRoute.distanceMeters`와는 소수점 수준에서 다를 수 있으므로, 두
  /// 값을 섞어 쓰지 않고 진행률 표시는 이 쌍만 쓴다.
  final double remainingM;

  /// 현재 위치에서 경로 폴리라인까지의 수직 거리.
  ///
  /// **이탈 판정 근거로 쓰지 않는다.** 경로와 나란한 옆 복도에 잘못 붙으면 이
  /// 값은 1~2m로 작게 나오지만 실제로는 완전한 이탈이다. 판정은
  /// [onRouteEdge]로 하고 이 값은 진단용으로만 본다.
  final double offsetM;

  /// 확정된 현재 간선이 경로 간선 집합에 속하는지.
  ///
  /// 간선 동일성으로만 판정하므로 옆 복도 오매칭이 그대로 드러난다. 현재
  /// 간선이 아직 확정되지 않았으면(교차로 통과 중 등) false다.
  final bool onRouteEdge;

  /// 이전 진행거리 근처에서 후보를 찾지 못해 전역 재획득한 결과인지.
  ///
  /// 경로를 크게 벗어났다 돌아온 경우이거나, 위치 추정이 크게 튄 경우다. 이
  /// 값이 자주 켜지면 진행거리 시계열을 그대로 신뢰할 수 없다는 신호다.
  final bool reacquired;

  /// 투영된 폴리라인 구간 번호(0-based). 진단·회귀 테스트용.
  final int segmentIndex;

  /// 경로 폴리라인 위에 투영된 현재 위치. 남은 파란선을 이 점부터 그리고,
  /// 지나온 구간을 회색으로 나눌 때 쓴다. 예전 진단 로그를 만드는 테스트와의
  /// 호환을 위해 직접 생성 시에는 null일 수 있다.
  final LocalPoint? projectedPoint;

  /// 현재 진행 heading과 목적지 방향 경로 접선의 차이(0~180°).
  final double? headingErrorDeg;

  /// 경로 위에 있지만 목적지 반대 방향으로 진행 중인지.
  ///
  /// 코너 한 프레임의 흔들림보다 명확한 역주행만 알리기 위해 120° 이상을
  /// 사용한다. 화면은 이 값을 경로 재탐색보다 먼저 사용자에게 보여준다.
  final bool wrongWay;
}

/// 현재 위치를 새 경로의 첫 점에 붙여 만든 진행률 기준점.
///
/// 재탐색 직후 일반 투영을 바로 실행하면, 물리적으로 가까운 뒷 구간을 골라
/// 이미 걸은 것처럼 시작할 수 있다. 새 경로가 현재 위치를 첫 점으로 붙였다는
/// 전제에서 진행거리는 항상 0으로 시작하고 이후 걸음만 누적한다.
RouteProgress? seedRouteProgressAtRouteStart({
  required List<LocalPoint> routePointsLocalM,
  required Set<String> routeEdgeIds,
  required String? currentEdgeId,
  double? headingDeg,
}) {
  if (routePointsLocalM.length < 2) return null;
  var firstSegmentIndex = -1;
  var totalLengthM = 0.0;
  for (var index = 0; index < routePointsLocalM.length - 1; index++) {
    final start = routePointsLocalM[index];
    final end = routePointsLocalM[index + 1];
    final lengthM = math.sqrt(
      math.pow(end.x - start.x, 2) + math.pow(end.y - start.y, 2),
    );
    if (lengthM > 0 && firstSegmentIndex < 0) firstSegmentIndex = index;
    totalLengthM += lengthM;
  }
  if (firstSegmentIndex < 0) return null;
  final first = routePointsLocalM.first;
  final routeBearingDeg = _bearingForSegment(
    routePointsLocalM[firstSegmentIndex],
    routePointsLocalM[firstSegmentIndex + 1],
  );
  final headingErrorDeg = headingDeg == null
      ? null
      : _bearingError(headingDeg, routeBearingDeg);
  final onRouteEdge =
      currentEdgeId != null && routeEdgeIds.contains(currentEdgeId);
  return RouteProgress(
    traveledM: 0,
    remainingM: totalLengthM,
    offsetM: 0,
    onRouteEdge: onRouteEdge,
    reacquired: false,
    segmentIndex: firstSegmentIndex,
    projectedPoint: first,
    headingErrorDeg: headingErrorDeg,
    wrongWay: onRouteEdge && headingErrorDeg != null && headingErrorDeg >= 120,
  );
}

/// 새 진행점이 마지막으로 받아들인 진행점에서 실제 걸음으로 설명할 수 없을
/// 만큼 멀리 튀었는지 판단한다.
///
/// PDR의 복도 매칭이 교차점이나 평행 통로에서 순간적으로 다른 구간을 고르면
/// 현재 간선이 여전히 경로 간선인 채로도 진행거리가 수십 m 바뀔 수 있다.
/// 마지막 채택 뒤 늘어난 걸음마다 [maxStepLengthM]를 허용하고, 투영·보폭
/// 오차를 위한 [baseSlackM]만 추가한다. 걸음 없는 위치 점프는 표시에서
/// 제외되지만, 걸음이 계속 늘면 실제 빠른 이동은 자연스럽게 받아들인다.
bool shouldHoldImplausibleRouteJump({
  required RouteProgress? previous,
  required RouteProgress candidate,
  required int? acceptedAtSteps,
  required int? currentSteps,
  double maxStepLengthM = 1.2,
  double baseSlackM = 3.0,
}) {
  if (previous == null || acceptedAtSteps == null || currentSteps == null) {
    return false;
  }
  final stepDelta = math.max(0, currentSteps - acceptedAtSteps);
  final plausibleDistanceM = baseSlackM + stepDelta * maxStepLengthM;
  return (candidate.traveledM - previous.traveledM).abs() > plausibleDistanceM;
}

/// 걸음으로 설명되지 않는 **경로상 후퇴**인지 판단한다.
///
/// [shouldHoldImplausibleRouteJump]는 앞·뒤를 가리지 않고 큰 점프만 막는다.
/// 그런데 실제로 눈에 거슬리는 것은 크기가 작은 후퇴다 — 빔 1등이 옆 간선으로
/// 재배치되거나 초록 보폭이 주황보다 커서 선행분이 깎일 때, 마커가 걸은 적
/// 없는 방향으로 몇 미터 밀린다. 사용자에게는 "뒤로 튀었다"로 보인다.
///
/// 되돌아 걷는 것은 정상이므로 후퇴 자체를 막으면 안 된다. 문제는 **무엇이
/// 되돌아 걸었다는 증거인가**다.
///
/// 걸음 수는 증거가 못 된다. pedometer는 방향을 모르기 때문에, 앞으로 걸은
/// 걸음이 그대로 "뒤로 갈 여유"로 계산된다 — 앞으로 5걸음 걸었더니 6m 뒤로
/// 튀는 것이 허용되는 식이다. 실제로 그렇게 동작했다.
///
/// 그래서 사용자가 향한 방향을 쓴다. 경로 방위와 [reverseHeadingErrorDeg] 이상
/// 어긋나 있으면 몸을 돌린 것이므로 후퇴를 그대로 받아들이고, 아니면
/// [freeRegressionM](투영 오차 수준)까지만 참고 그 이상은 보류한다.
bool shouldHoldRouteRegression({
  required RouteProgress? previous,
  required RouteProgress candidate,
  required double? deviceHeadingErrorDeg,
  double freeRegressionM = 2.0,
  double reverseHeadingErrorDeg = 100,
}) {
  if (previous == null) return false;
  final regressionM = previous.traveledM - candidate.traveledM;
  if (regressionM <= freeRegressionM) return false;
  // 방향을 모르면 후퇴를 정당화할 수 없다. 모르는 채로 마커를 뒤로 보내는
  // 것보다 이번 갱신을 넘기는 쪽이 낫다.
  if (deviceHeadingErrorDeg == null) return true;
  return deviceHeadingErrorDeg < reverseHeadingErrorDeg;
}

/// [previousTraveledM] 주변에서 후보를 찾는 기본 탐색 창(±m).
///
/// 임의값이다. 실측 진행거리 분포를 보고 조정해야 하며, 현재는 한 걸음
/// (약 0.7m)과 1Hz 갱신 간 이동량에 비해 넉넉하되 ㄷ자 경로의 마주보는
/// 구간까지는 닿지 않는 값으로 잡았다.
const double defaultRouteSearchWindowM = 15.0;

/// 경로 폴리라인에 [position]을 투영해 진행률을 계산한다.
///
/// 폴리라인 점이 2개 미만이면(그릴 경로가 없음) null.
///
/// [previousTraveledM]을 주면 그 값 ±[searchWindowM] 안의 후보만 본다. 경로가
/// ㄷ자로 겹치면 시작 구간과 끝 구간이 물리적으로 가까워지는데, 전역 최소만
/// 쓰면 이때 진행거리가 경로 끝에서 시작으로 순간이동한다. 창 안에 후보가
/// 없으면 전역 최소로 재획득하고 [RouteProgress.reacquired]를 켠다.
RouteProgress? computeRouteProgress({
  required List<LocalPoint> routePointsLocalM,
  required Set<String> routeEdgeIds,
  required LocalPoint position,
  required String? currentEdgeId,
  double? headingDeg,
  double? previousTraveledM,
  double searchWindowM = defaultRouteSearchWindowM,
}) {
  if (routePointsLocalM.length < 2) return null;

  final candidates = <_Projection>[];
  var cumulativeM = 0.0;

  for (var index = 0; index < routePointsLocalM.length - 1; index++) {
    final start = routePointsLocalM[index];
    final end = routePointsLocalM[index + 1];
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final lengthSq = dx * dx + dy * dy;

    // 같은 좌표가 연달아 들어온 구간(간선 이어붙이기 경계에서 생길 수 있다)은
    // 투영할 방향이 없어 건너뛴다. 누적 거리도 늘지 않는다.
    if (lengthSq == 0) continue;

    final segmentLengthM = math.sqrt(lengthSq);
    final t =
        (((position.x - start.x) * dx + (position.y - start.y) * dy) / lengthSq)
            .clamp(0.0, 1.0);
    final footX = start.x + t * dx;
    final footY = start.y + t * dy;
    final offsetM = math.sqrt(
      math.pow(position.x - footX, 2) + math.pow(position.y - footY, 2),
    );

    candidates.add(
      _Projection(
        segmentIndex: index,
        traveledM: cumulativeM + t * segmentLengthM,
        offsetM: offsetM,
        footX: footX,
        footY: footY,
      ),
    );
    cumulativeM += segmentLengthM;
  }

  if (candidates.isEmpty) return null;
  final totalLengthM = cumulativeM;

  _Projection? chosen;
  var reacquired = false;

  if (previousTraveledM != null) {
    chosen = _nearestOffset(
      candidates.where(
        (candidate) =>
            (candidate.traveledM - previousTraveledM).abs() <= searchWindowM,
      ),
    );
    // 창 안에 아무것도 없다 = 이전 진행거리와 이어지지 않는 위치다. 진행거리를
    // 억지로 유지하는 대신 전역 최소로 다시 잡고, 그 사실을 표시한다.
    reacquired = chosen == null;
  }
  chosen ??= _nearestOffset(candidates)!;
  final routeBearingDeg = _bearingForSegment(
    routePointsLocalM[chosen.segmentIndex],
    routePointsLocalM[chosen.segmentIndex + 1],
  );
  final headingErrorDeg = headingDeg == null
      ? null
      : _bearingError(headingDeg, routeBearingDeg);

  return RouteProgress(
    traveledM: chosen.traveledM,
    remainingM: math.max(0.0, totalLengthM - chosen.traveledM),
    offsetM: chosen.offsetM,
    onRouteEdge: currentEdgeId != null && routeEdgeIds.contains(currentEdgeId),
    reacquired: reacquired,
    segmentIndex: chosen.segmentIndex,
    projectedPoint: LocalPoint(chosen.footX, chosen.footY),
    headingErrorDeg: headingErrorDeg,
    wrongWay:
        currentEdgeId != null &&
        routeEdgeIds.contains(currentEdgeId) &&
        headingErrorDeg != null &&
        headingErrorDeg >= 120,
  );
}

double _bearingForSegment(LocalPoint start, LocalPoint end) {
  final east = end.x - start.x;
  final north = end.y - start.y;
  final bearing = math.atan2(east, north) * 180 / math.pi;
  return bearing < 0 ? bearing + 360 : bearing;
}

double _bearingError(double a, double b) {
  final delta = ((a - b + 540) % 360) - 180;
  return delta.abs();
}

_Projection? _nearestOffset(Iterable<_Projection> candidates) {
  _Projection? best;
  for (final candidate in candidates) {
    if (best == null || candidate.offsetM < best.offsetM) best = candidate;
  }
  return best;
}

class _Projection {
  const _Projection({
    required this.segmentIndex,
    required this.traveledM,
    required this.offsetM,
    required this.footX,
    required this.footY,
  });

  final int segmentIndex;
  final double traveledM;
  final double offsetM;
  final double footX;
  final double footY;
}
