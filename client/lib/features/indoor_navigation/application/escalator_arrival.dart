import '../../../models/floor_graph.dart';
import '../contract/floor_transition_ui_state.dart';
import 'escalator_node_naming.dart';
import 'escalator_transition_detector.dart';

/// 확정된 층 이동의 **도착 노드**를 새 층 그래프에서 찾는다.
///
/// 이 값이 새 층의 앵커가 된다. 못 찾으면 사용자는 하차한 자리를 앱이 모르는
/// 상태가 되므로, 세 단계로 물러서며 찾는다.
///
/// 1. **길찾기가 지목한 노드**([EscalatorTransition.expectedArrivalNodeId]).
///    붙어 있는 레인 중 어느 것을 탔는지는 센서로 못 가르고 경로만 안다.
/// 2. **이름이 맞는 도착 노드** — `{그룹}-UP(FR2F)`처럼 출발 층까지 일치.
/// 3. **같은 뱅크·같은 방향의 아무 노드** — 이름 규칙이 깨진 데이터에서도
///    같은 에스컬레이터 근처에는 세워 준다. 정확하진 않아도 반대편 건물에
///    떨어뜨리는 것보다 낫다.
GraphNode? findEscalatorArrivalNode(
  FloorGraph? graph,
  EscalatorTransition transition,
) {
  if (graph == null) return null;
  final expectedArrivalNodeId = transition.expectedArrivalNodeId;
  if (expectedArrivalNodeId != null) {
    for (final node in graph.nodes) {
      if (node.id == expectedArrivalNodeId && node.type == 'escalator') {
        return node;
      }
    }
  }
  GraphNode? sameGroupFallback;
  for (final node in graph.nodes) {
    if (node.type != 'escalator') continue;
    final parsed = EscalatorNodeName.tryParse(node.name);
    if (parsed == null) continue;
    if (parsed.isArrivalOf(
      group: transition.group,
      direction: transition.direction,
      fromFloorLabel: transition.fromFloorLabel,
    )) {
      return node;
    }
    if (sameGroupFallback == null &&
        parsed.group == transition.group &&
        parsed.direction == transition.direction) {
      sameGroupFallback = node;
    }
  }
  return sameGroupFallback;
}

/// 지금 화면이 그려야 하는 층 전환 배너 상태. 없으면 null.
///
/// 판정 단계를 UI 문구로 **한 번만** 옮긴다. 화면은 여기서
/// 나온 값만 보고 그린다 — 임계값이나 노드 근접을 다시 계산하지 않는다.
///
/// 우선순위가 이 함수의 전부다. 도착 → 탑승 중 → 접근 순으로 보며, 앞의 것이
/// 있으면 뒤는 보지 않는다. 뒤집으면 하차 직후에도 "이동 중"이 떠 있다.
FloorTransitionUiState? floorTransitionUiState({
  required EscalatorTransition? arrival,
  required EscalatorTransition? ride,
  required EscalatorPhaseChange? stage,
}) {
  if (arrival != null && ride == null) {
    return FloorTransitionUiState(
      stage: FloorTransitionStage.arrived,
      fromFloorLabel: arrival.fromFloorLabel,
      toFloorLabel: arrival.toFloorLabel,
      goingUp: arrival.direction == EscalatorDirection.up,
    );
  }
  if (ride != null) {
    return FloorTransitionUiState(
      stage: FloorTransitionStage.swapping,
      fromFloorLabel: ride.fromFloorLabel,
      toFloorLabel: ride.toFloorLabel,
      goingUp: ride.direction == EscalatorDirection.up,
    );
  }
  // 도착 층을 모르면 배너에 쓸 문장이 없다. `{출발}→{도착}`이 문구의 뼈대다.
  if (stage == null || stage.toFloorLabel == null) return null;
  return FloorTransitionUiState(
    stage: stage.phase == EscalatorPhase.verticalMotionDetected
        ? FloorTransitionStage.moving
        : FloorTransitionStage.boarding,
    fromFloorLabel: stage.fromFloorLabel,
    toFloorLabel: stage.toFloorLabel!,
    goingUp: stage.direction == EscalatorDirection.up,
  );
}
