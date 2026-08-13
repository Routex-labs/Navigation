/// 층 전환 UI가 그리는 것 전부.
///
/// 판정기의 단계(`EscalatorPhase`)를 화면이 다시 해석하지 않게 하려고 둔
/// 계약이다. UI는 여기 담긴 값을 문구와 애니메이션으로만 바꾼다 — 고도
/// 임계값이나 노드 근접을 UI에서 다시 계산하지 않는다.
///
/// 지도 본문이 아니라 **앱 셸의 최상위 Stack**이 이 상태를 그린다. 배너를
/// 지도 안에 두면 상위 셸이 나중에 그리는 검색창·카테고리 줄 뒤로 깔린다
/// (자식의 top 상수를 아무리 조정해도 부모 sibling 위로 올라갈 수 없다).
///
/// **화면을 덮는 스크림은 없다.** 한때 도면 교체 구간을 불투명 스크림으로
/// 덮었는데, 실기기에서 그것은 전환이 아니라 깜빡임으로 보였다 — 지도가 한 번
/// 하얗게 날아가고 그 사이 마커가 사라졌다 다른 자리에 나타난다. 지금은 이전
/// 층 도면을 그대로 둔 채 새 층을 크로스페이드하고, 마커는 에스컬레이터를 타고
/// 흘러간다. 전환이 일어나고 있다는 사실은 이 배너가 말한다.
library;

/// 층 전환 UI 상태가 바뀔 때 상위 셸에 알리는 계약.
///
/// [banner]가 null이면 배너를 감춘다.
typedef FloorTransitionUiChanged =
    void Function(FloorTransitionUiState? banner);

/// 사용자에게 보이는 층 전환 진행 단계.
enum FloorTransitionStage {
  /// 탑승점에 접근했다. 배너만 뜨고 지도·걸음은 그대로다.
  boarding,

  /// 실제로 오르내리는 중이다. 걸음 적용은 멈췄고 지도는 아직 출발 층이다.
  moving,

  /// 목적 층 도면으로 바뀌었고 하차를 기다린다.
  swapping,

  /// 하차가 확정돼 위치를 옮겼다.
  arrived,
}

class FloorTransitionUiState {
  const FloorTransitionUiState({
    required this.stage,
    required this.fromFloorLabel,
    required this.toFloorLabel,
    required this.goingUp,
  });

  final FloorTransitionStage stage;
  final String fromFloorLabel;
  final String toFloorLabel;
  final bool goingUp;

  /// 이 단계의 배너 문구. 층 전환 구간에서 화면이 말하는 **유일한** 문장이라,
  /// 단계마다 지금 무슨 일이 일어나는지가 여기서 다 읽혀야 한다.
  String get message => switch (stage) {
    FloorTransitionStage.boarding => '에스컬레이터 탑승을 감지했습니다',
    FloorTransitionStage.moving =>
      '에스컬레이터로 이동 중 · $fromFloorLabel → $toFloorLabel',
    FloorTransitionStage.swapping => '$toFloorLabel 지도로 전환하는 중',
    FloorTransitionStage.arrived => '$toFloorLabel로 이동했습니다',
  };

  @override
  bool operator ==(Object other) =>
      other is FloorTransitionUiState &&
      other.stage == stage &&
      other.fromFloorLabel == fromFloorLabel &&
      other.toFloorLabel == toFloorLabel &&
      other.goingUp == goingUp;

  @override
  int get hashCode => Object.hash(stage, fromFloorLabel, toFloorLabel, goingUp);
}
