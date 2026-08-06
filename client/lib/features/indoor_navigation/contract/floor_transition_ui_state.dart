/// 층 전환 UI가 그리는 것 전부.
///
/// 판정기의 단계(`EscalatorPhase`)를 화면이 다시 해석하지 않게 하려고 둔
/// 계약이다. UI는 여기 담긴 값을 문구와 애니메이션으로만 바꾼다 — 고도
/// 임계값이나 노드 근접을 UI에서 다시 계산하지 않는다.
///
/// 지도 본문이 아니라 **앱 셸의 최상위 Stack**이 이 상태를 그린다. 배너를
/// 지도 안에 두면 상위 셸이 나중에 그리는 검색창·카테고리 줄 뒤로 깔린다
/// (자식의 top 상수를 아무리 조정해도 부모 sibling 위로 올라갈 수 없다).
library;

/// 층 전환 UI 상태가 바뀔 때 상위 셸에 알리는 계약.
///
/// [banner]가 null이면 배너를 감춘다. [veilOpacity]는 실제 도면 swap 구간에만
/// 0이 아니며, 그때는 뒤쪽 입력도 함께 막아야 한다.
typedef FloorTransitionUiChanged =
    void Function(FloorTransitionUiState? banner, double veilOpacity);

/// 사용자에게 보이는 층 전환 진행 단계.
enum FloorTransitionStage {
  /// 탑승점에 접근했다. 배너만 뜨고 지도·걸음은 그대로다.
  boarding,

  /// 실제로 오르내리는 중이다. 걸음 적용은 멈췄고 지도는 아직 출발 층이다.
  moving,

  /// 목적 층 도면으로 바뀌었고 하차를 기다린다.
  swapping,

  /// 하차가 확정돼 위치를 옮겼다. 되돌리기를 제공한다.
  arrived,
}

class FloorTransitionUiState {
  const FloorTransitionUiState({
    required this.stage,
    required this.fromFloorLabel,
    required this.toFloorLabel,
    required this.goingUp,
    this.canUndo = false,
  });

  final FloorTransitionStage stage;
  final String fromFloorLabel;
  final String toFloorLabel;
  final bool goingUp;

  /// 되돌리기(`아니에요`)를 노출할지. 층을 실제로 옮긴 뒤에만 true다.
  final bool canUndo;

  /// 이 단계의 배너 문구.
  String get message => switch (stage) {
    FloorTransitionStage.boarding => '에스컬레이터 탑승을 감지했습니다',
    FloorTransitionStage.moving =>
      '에스컬레이터로 이동 중 · $fromFloorLabel → $toFloorLabel',
    FloorTransitionStage.swapping => '$toFloorLabel 지도로 전환하는 중',
    FloorTransitionStage.arrived => '$toFloorLabel에 도착한 것으로 보여 위치를 옮겼습니다',
  };

  @override
  bool operator ==(Object other) =>
      other is FloorTransitionUiState &&
      other.stage == stage &&
      other.fromFloorLabel == fromFloorLabel &&
      other.toFloorLabel == toFloorLabel &&
      other.goingUp == goingUp &&
      other.canUndo == canUndo;

  @override
  int get hashCode =>
      Object.hash(stage, fromFloorLabel, toFloorLabel, goingUp, canUndo);
}
