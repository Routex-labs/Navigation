/// 위치에 **반영되지 않은** 원시 움직임 신호.
///
/// `steps`는 위치에 적용된 걸음이라 탑승 중 멈추면 "하차해서 걷기 시작했다"를 볼 수
/// 없다. 그래서 native가 pause와 무관하게 보내는 이 신호를 따로 둔다.
///
/// 판정기는 **수직 속도가 충분히 낮을 때만** 이걸 하차 근거로 쓴다 — 에스컬레이터
/// 중간의 진동 peak로 재개되지 않는 이유가 그 조건이다.
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
