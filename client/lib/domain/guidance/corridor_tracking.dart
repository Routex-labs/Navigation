/// 복도 보정이 만들어 내는 **말**(vocabulary) — 확신도와 걸음 하나의 이동 사건.
///
/// 만드는 쪽은 `features/indoor_navigation/application/corridor_position_tracker.dart`
/// 이고, 소비하는 쪽은 경로 진행·체크포인트 판정([route_movement.dart]·
/// [route_checkpoint.dart])이다. 두 쪽이 모두 여기를 보게 두는 이유는 계층 방향
/// 때문이다 — 이 타입들이 tracker 파일에 있으면 domain이 features를 import하게
/// 되어 화살표가 거꾸로 선다.
///
/// **여기 있는 것은 값뿐이다.** tracker의 전체 출력([CorridorTrackingResult])은
/// 30개 필드로 그쪽 내부 사정에 묶여 있으므로 내려오지 않는다. domain은 자기가
/// 실제로 읽는 값만 받는다.
library;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

/// 보정 결과의 확신도.
///
/// 예전 구현의 상태기(직선/회전대기/노드확정/불확실) 이름을 유지하지만 의미가
/// 다르다. 지금은 상태가 동작을 바꾸지 않는다 — 빔이 항상 모든 가설을 들고
/// 있고, 이 값은 **그 빔이 지금 얼마나 갈렸는지**를 표시할 뿐이다.
enum CorridorTrackingState {
  /// 1등 가설이 뚜렷하다.
  straightTracking,

  /// 1·2등이 다른 간선인데 점수 차가 작다. 표시는 공통 지점에서 멈춘다.
  turnPending,

  /// 이번 갱신에서 1등 가설이 노드를 넘었다.
  nodeConfirmed,

  /// 모든 가설이 그래프로 설명되지 않는다(막다른 곳 등).
  uncertain,
}

/// accepted preview peak 하나가 graph 위에서 실제로 지난 간선 조각.
class OptimisticEdgeTraversal {
  const OptimisticEdgeTraversal({
    required this.edgeId,
    required this.fromProgressM,
    required this.toProgressM,
  });

  final String edgeId;
  final double fromProgressM;
  final double toProgressM;

  double get distanceM => (toProgressM - fromProgressM).abs();
  int get edgeDirectionSign => toProgressM >= fromProgressM ? 1 : -1;
}

/// accepted preview peak 하나가 선택된 optimistic 가설 안에서 만든 이동 사건.
///
/// 공개 leader의 전후 좌표 차이가 아니라, 선택된 가설이 자기 parent에서 실제로
/// 전진한 조각을 보존한다. 그래서 node를 넘거나 graph 저장 방향이 반대여도 한
/// 걸음의 거리와 부호를 잃지 않는다.
class OptimisticStepAdvance {
  const OptimisticStepAdvance({
    required this.peakId,
    required this.occurredAtMs,
    required this.hypothesisId,
    required this.parentHypothesisId,
    required this.distanceM,
    required this.edgeId,
    required this.mapMatchedHeadingDeg,
    required this.previewIsAmbiguous,
    required this.position,
    required this.traversals,
    required this.crossedNodeIds,
    required this.leaderRelocated,
  });

  final int peakId;
  final int occurredAtMs;
  final String hypothesisId;
  final String parentHypothesisId;
  final double distanceM;
  final String edgeId;
  final double mapMatchedHeadingDeg;
  final bool previewIsAmbiguous;
  final PdrLocalPoint position;
  final List<OptimisticEdgeTraversal> traversals;
  final List<String> crossedNodeIds;

  /// 이 peak를 적용하는 동안 공개 leader의 lineage가 바뀌었는지.
  ///
  /// traversal은 진단·표시에 남기되 실제 이동 방향 확정 증거에서는 제외한다.
  final bool leaderRelocated;
}
