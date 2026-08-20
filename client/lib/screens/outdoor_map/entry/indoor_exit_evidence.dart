/// 실외 이탈의 **약한 근거** — GPS 문턱을 못 넘는 구간에서 쓰는 판정.
///
/// 확정 이탈(앵커 폐기)은 `indoor_entry_gps.dart`의 `outside`가 그대로 맡는다.
/// 여기 있는 것은 되돌리기 쉬운 일(재무장·기본 층 리셋)만 시키는 갈래다.
///
/// 두 상수는 **실측 없이 정한 초안값**이다. 근거는 각 선언 위에, 검증 기준은
/// `test/screens/outdoor_map/entry/indoor_exit_evidence_test.dart`.
library;

import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../domain/geo/geo_transform.dart';
import '../../../domain/guidance/corridor_tracking.dart';
import '../../../domain/route/building_entrances.dart';
import '../../../models/building/floor_graph.dart';
import '../../../models/building/floor_plan.dart';
import 'indoor_entry_gps.dart';

/// 보정된 실내 위치가 **문 앞 좌표**에서 이 거리 안이면 문에 닿았다고 본다(m).
///
/// 문 두께가 아니라 **닿을 수 있는 최단 거리**로 정한 값이다. 화면이 든 층
/// 그래프에는 문 노드가 없고(`domain/route/entrance_door_nodes.dart` 머리 주석의
/// 이유), 복도 보정은 위치를 그 그래프 위에 붙인다. 그래서 통로에서 문 앞
/// 좌표에 가장 가까워질 수 있는 지점은 **문 안쪽 앵커 노드**이고, 둘의 실측
/// 간격이 7~12 m다(`domain/route/building_entrances.dart`의
/// `BuildingEntrance.point` 주석). 12 m보다 작게 잡으면 이 조건은 **영원히 안
/// 걸린다.**
///
/// 15 = 실측 간격 상한 12 + 보정 오차 3. 아래 3 m가 근거 없는 몫이므로 **실측으로
/// 조정해야 한다** — 문을 통과한 실기기 로그(디버그 JSON `indoor_exit_events`의
/// `door_distance_m`)에서 이 거리의 최솟값을 재고 그 값 + 여유로 다시 잡는다.
const kExitDoorReachRadiusMeters = 15.0;

/// unclear가 이어지는 동안 좌표가 계속 바깥에 찍히면, 이만큼 뒤 약한 이탈로 본다.
///
/// **실측 없이 정한 값이다.** 좌표가 1 Hz 안팎이라 20초는 연속 20건쯤에 해당한다 —
/// 벽 옆에서 한두 건이 튀는 것으로는 안 걸리고, 정말 걸어 나갔다면 그 안에 채운다.
/// 틀렸을 때의 비용이 층 하나뿐이라 짧은 쪽으로 잡았다. 실기기 로그에서 문을 지난
/// 시각과 이 값이 걸린 시각의 차를 재서 조정한다.
const kUnclearOutsideExitHold = Duration(seconds: 20);

/// 문 앞 도달 판정 **한 걸음**. 상태를 안 들고 있으니 호출자가 [leftDoorZone]을
/// 보관했다가 돌려받은 값으로 갱신한다.
///
/// [reached]는 **문에서 한 번 멀어졌다가 다시 닿았을 때만** true다. 들어오는
/// 사람도 문 앞을 지나므로, 그 구분이 없으면 진입 직후에 곧바로 이탈로 읽는다.
///
/// 다음 중 하나라도 아니면 판정하지 않는다:
/// - [onDefaultFloor]가 false — 지상 출구는 건물 기본 층에만 있다.
/// - [corridorState]가 null이거나 [CorridorTrackingState.uncertain] — 위치를
///   못 믿는 상태에서 "문에 닿았다"고 말하면 안 된다.
({bool leftDoorZone, bool reached}) stepExitDoorEvidence({
  required bool leftDoorZone,
  required PdrLocalPoint? positionM,
  required bool onDefaultFloor,
  required CorridorTrackingState? corridorState,
  required List<PdrLocalPoint> doorPointsM,
}) {
  if (!onDefaultFloor ||
      corridorState == null ||
      corridorState == CorridorTrackingState.uncertain) {
    return (leftDoorZone: leftDoorZone, reached: false);
  }
  final nearestM = nearestExitDoorDistanceM(positionM, doorPointsM);
  if (nearestM == null) return (leftDoorZone: leftDoorZone, reached: false);
  if (nearestM > kExitDoorReachRadiusMeters) {
    return (leftDoorZone: true, reached: false);
  }
  return (leftDoorZone: leftDoorZone, reached: leftDoorZone);
}

/// 문 앞 좌표까지의 최단 거리(m). 잴 수 없으면 null.
double? nearestExitDoorDistanceM(
  PdrLocalPoint? positionM,
  List<PdrLocalPoint> doorPointsM,
) {
  if (positionM == null || doorPointsM.isEmpty) return null;
  var nearestSquared = double.infinity;
  for (final door in doorPointsM) {
    final dx = positionM.eastM - door.eastM;
    final dy = positionM.northM - door.northM;
    final squared = dx * dx + dy * dy;
    if (squared < nearestSquared) nearestSquared = squared;
  }
  return math.sqrt(nearestSquared);
}

/// 지상 출구들의 **문 앞 좌표**를 층 로컬 m로 옮긴 목록. 못 옮기면 빈 목록.
///
/// 그래프에 노드로 넣지 않는다 — 필요한 것은 거리를 잴 좌표뿐이고, 넣으면 지도
/// 매칭이 사용자를 문 밖으로 스냅한다.
List<PdrLocalPoint> exitDoorPointsFloorLocalM(
  FloorPlan? plan,
  FloorGraph? graph,
) {
  if (plan == null || graph == null || graph.nodes.isEmpty) return const [];
  final entrances = groundEntrancesFrom(plan);
  if (entrances.isEmpty) return const [];
  final transform = fitFloorGeoTransform(graph.nodes);
  final points = <PdrLocalPoint>[];
  for (final entrance in entrances) {
    final local = transform.invert(
      entrance.point.latitude,
      entrance.point.longitude,
    );
    if (local == null) continue;
    points.add(PdrLocalPoint(local.$1, local.$2));
  }
  return points;
}

/// "바깥에 찍히기 시작한 시각"을 좌표 한 건으로 갱신한다.
///
/// - 외곽선을 모르거나 오차가 [outdoorExitAccuracyMeters]를 넘으면 **그대로 둔다.**
///   못 믿는 좌표가 시계를 되돌리면, 오차가 큰 구간이 바로 이 판정이 필요한
///   구간이라 영영 안 걸린다.
/// - 바깥이면 시작 시각을 세우고(이미 있으면 유지), 안쪽이면 null로 되돌린다.
DateTime? nextUnclearOutsideSince({
  required GpsBuildingJudgement judgement,
  required DateTime? since,
  required DateTime now,
}) {
  if (!judgement.hasFootprint) return since;
  if (judgement.accuracyMeters > outdoorExitAccuracyMeters) return since;
  if (judgement.metersOutside > 0) return since ?? now;
  return null;
}

/// 바깥 지속이 [kUnclearOutsideExitHold]를 채웠는지.
bool unclearOutsideExitDue(DateTime? since, DateTime now) =>
    since != null && now.difference(since) >= kUnclearOutsideExitHold;
