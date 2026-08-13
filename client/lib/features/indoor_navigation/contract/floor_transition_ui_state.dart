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

/// 스크림이 짙어지는/걷히는 시간.
///
/// **일부러 느리다.** 층 전환은 사용자가 알아채야 하는 사건이다. 빠른 페이드는
/// 지도가 "깜빡"한 것처럼 보여서, 화면이 바뀐 줄도 모르고 다른 층 도면을 읽는
/// 일이 생긴다. 천천히 덮였다가 천천히 걷히면 그 사이에 뭔가 일어났다는 것이
/// 눈에 남는다. 걷히는 쪽을 더 길게 둔 이유는, 그때 사용자가 이미 새 도면을
/// 보고 있어서 서두를 이유가 없기 때문이다.
const floorTransitionScrimFadeIn = Duration(milliseconds: 520);
const floorTransitionScrimFadeOut = Duration(milliseconds: 700);

/// 층 전환 UI 상태가 바뀔 때 상위 셸에 알리는 계약.
///
/// [banner]가 null이면 배너를 감춘다. [scrimOpacity]는 탑승이 잡힌 구간에서 1이
/// 되며, 그동안 뒤쪽 입력을 막는다.
typedef FloorTransitionUiChanged =
    void Function(FloorTransitionUiState? banner, double scrimOpacity);

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

  /// 이 단계의 배너 문구. 스크림이 덮인 동안에는 배너를 접으므로, 실제로 이
  /// 문장이 보이는 것은 덮기 전(접근)과 걷힌 뒤(도착) 구간이다.
  String get message => switch (stage) {
    FloorTransitionStage.boarding => '에스컬레이터 탑승을 감지했습니다',
    FloorTransitionStage.moving =>
      '에스컬레이터로 이동 중 · $fromFloorLabel → $toFloorLabel',
    FloorTransitionStage.swapping => '$toFloorLabel 지도로 전환하는 중',
    FloorTransitionStage.arrived => '$toFloorLabel로 이동했습니다',
  };

  /// 화면을 덮는 스크림 안에 쓰는 한 줄.
  ///
  /// 층 라벨은 스크림이 큰 글씨로 따로 그리므로 여기서는 **지금 무슨 일이
  /// 일어나는지**만 말한다. 라벨을 문구에 또 넣으면 같은 글자가 카드 안에 두
  /// 번 나온다.
  String get scrimCaption => switch (stage) {
    FloorTransitionStage.boarding => '에스컬레이터 탑승을 기다리는 중',
    FloorTransitionStage.moving => '에스컬레이터로 이동 중',
    FloorTransitionStage.swapping => '지도를 전환하는 중',
    FloorTransitionStage.arrived => '도착했습니다',
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
