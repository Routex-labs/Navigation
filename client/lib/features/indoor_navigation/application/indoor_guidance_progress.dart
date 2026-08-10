import '../../../domain/route_checkpoint.dart';
import '../../../domain/route_movement.dart';
import '../../../domain/route_progress.dart';

/// 걸음 한 묶음이 만들어 낸 경로 진행 상태 변화.
///
/// 표시용과 측정용을 **따로** 담는다. 화면이 그리는 값([displayProgress])은
/// 튐·후퇴를 보류한 결과이고, [measuredProgress]는 보류 전 원본이다. 하나로
/// 합치면 "지금 보고 있는 값"과 "센서가 말한 값"을 구분할 수 없어, 진단 로그가
/// 화면과 다른 이야기를 하게 된다.
class GuidanceProgressUpdate {
  const GuidanceProgressUpdate({
    this.displayProgress,
    this.measuredProgress,
    this.holdReason,
    this.stepAdvances = const [],
    this.checkpointEvents = const [],
    this.travelDirectionState = TravelDirectionState.forward,
    this.cleared = false,
    this.routeChanged = false,
    this.shouldReroute = false,
  });

  final RouteProgress? displayProgress;
  final RouteProgress? measuredProgress;

  /// 표시값을 이전 것으로 붙들어 둔 이유. 붙들지 않았으면 null.
  final String? holdReason;

  /// 이번에 처리한 걸음들. 레코더가 그대로 기록한다.
  final List<GuidanceStepAdvance> stepAdvances;

  final List<RouteCheckpointEvent> checkpointEvents;

  final TravelDirectionState travelDirectionState;

  /// 경로도 위치도 없어 진행 상태를 비운 경우.
  final bool cleared;

  /// 이번 갱신에서 세그먼트가 바뀌었는지. 화면이 경로 컨텍스트를 다시 기록한다.
  final bool routeChanged;

  /// 이탈 증거가 임계를 넘겨 재탐색을 걸 때가 됐는지.
  ///
  /// 실제 재탐색은 화면이 한다 — 목적지·그래프·비동기 계산이 화면 몫이다.
  /// 여기서는 "걸어도 된다"까지만 판단한다.
  final bool shouldReroute;

  bool get hasProgress => displayProgress != null;
}

/// 걸음 한 건과 그것이 만든 방향 상태 전이.
class GuidanceStepAdvance {
  const GuidanceStepAdvance({required this.step, this.transition});

  final RouteStepAdvance step;
  final TravelDirectionTransition? transition;
}
