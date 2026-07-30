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

  return RouteProgress(
    traveledM: chosen.traveledM,
    remainingM: math.max(0.0, totalLengthM - chosen.traveledM),
    offsetM: chosen.offsetM,
    onRouteEdge: currentEdgeId != null && routeEdgeIds.contains(currentEdgeId),
    reacquired: reacquired,
    segmentIndex: chosen.segmentIndex,
    projectedPoint: LocalPoint(chosen.footX, chosen.footY),
  );
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
