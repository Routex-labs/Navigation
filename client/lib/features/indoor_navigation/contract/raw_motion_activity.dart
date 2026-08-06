/// 위치에 **반영되지 않은** 원시 움직임 신호.
///
/// 층 전이 판정기가 받던 `steps`는 PDR 위치에 실제로 적용된 걸음 수다. 탑승 중
/// 걸음 적용을 멈추면 그 값이 증가하지 않아서, 정작 "하차해서 걷기 시작했다"는
/// 가장 빠른 근거를 판정기가 볼 수 없다(빠른 확정 경로가 동작하지 않아 iOS
/// 1Hz 기압 샘플 두 개를 더 기다렸다).
///
/// 그래서 위치 적용과 무관한 계약을 따로 둔다. native는 pause 여부와 상관없이
/// accel peak와 pedometer 이벤트를 계속 보내고, PDR core는 그것을 경로에
/// 반영하지 않으며, 판정기는 **수직 속도가 충분히 낮을 때만** 이 신호를
/// 하차 보조 근거로 쓴다. 에스컬레이터 중간의 진동 peak로 재개되지 않는
/// 이유가 그 조건이다.
class RawMotionActivity {
  const RawMotionActivity({
    required this.timestampMs,
    required this.accelPeakDelta,
    this.nativeStepDelta,
  });

  final int timestampMs;

  /// 직전 관측 이후 늘어난 accel peak 수.
  final int accelPeakDelta;

  /// 직전 관측 이후 늘어난 native pedometer 걸음 수. 이벤트에 없으면 null.
  final int? nativeStepDelta;

  /// 이번 관측에 실제 움직임 근거가 있는지.
  bool get hasMotion => accelPeakDelta > 0 || (nativeStepDelta ?? 0) > 0;
}
