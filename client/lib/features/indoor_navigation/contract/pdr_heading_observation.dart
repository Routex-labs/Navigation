/// 네이티브 모션 센서가 실시간으로 보고한 휴대폰 방위와 품질.
///
/// 경로 스냅샷은 걸음이 생길 때 갱신되므로 나침반 UI에는 충분히 빠르지 않다.
/// 이 타입은 위치·경로와 분리된 진단 전용 스트림으로 최대 20Hz만 노출한다.
class PdrHeadingObservation {
  const PdrHeadingObservation({
    required this.measuredBearingDeg,
    required this.walkingBearingDeg,
    required this.stable,
    required this.source,
    required this.magneticAccuracy,
    required this.motionTimestampMs,
  });

  /// 휴대폰 상단이 향하는 센서 원본 방위. 0°=자북, 90°=동쪽.
  final double measuredBearingDeg;

  /// smoothing과 보행축 보정까지 적용된 PDR 진행 방위. 비교·진단용이다.
  final double walkingBearingDeg;

  final bool stable;
  final String source;
  final String magneticAccuracy;
  final int motionTimestampMs;
}
