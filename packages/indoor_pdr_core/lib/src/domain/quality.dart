/// 품질 상태. UI는 이 값으로 표시를 결정하고, 로직은 config 임계로 판정한다.
enum PdrQualityState { healthy, caution, degraded }

/// 품질 판정과 future fusion 학습에 공통으로 쓰는 feature 원자료(§5).
///
/// 이 스키마는 fusion 라벨 데이터의 feature와 동일하게 유지한다.
class PdrQualityFeatures {
  const PdrQualityFeatures({
    required this.greenOrangeDistanceDivergencePct,
    required this.orangeStepRatio,
    required this.orangeOvercountLikely,
    required this.pedometerUndercountSuspected,
    required this.pedometerFlaggedSpanS,
    required this.headingStable,
    required this.headingSource,
    required this.magneticAccuracy,
    required this.rotationHeadingAccuracyDeg,
    required this.cadenceHz,
    required this.pitchDeg,
    required this.rollDeg,
    required this.headingReferenceIsMagneticNorth,
    required this.peakRejectHistogram,
    required this.fusedHeadingDeg,
    required this.walkOffsetDeg,
    required this.walkOffsetActive,
    required this.deviceHeadingDeg,
    required this.gyroHeadingDeg,
    required this.walkDirDeg,
    required this.walkDirConfidence,
    required this.headingConverged,
    required this.headingSpreadDeg,
  });

  /// |orange−green| / green (초록 거리 대비 주황 거리 괴리, %).
  final double greenOrangeDistanceDivergencePct;

  /// orangeSteps / greenSteps.
  final double orangeStepRatio;

  /// accel 과검출 의심(임계 1.3× — 잠정, Phase 5에서 재보정).
  final bool orangeOvercountLikely;

  /// CMPedometer 침묵 의심(진단 전용. 초록→주황 자동 전환에 쓰지 않는다).
  final bool pedometerUndercountSuspected;
  final double pedometerFlaggedSpanS;

  final bool headingStable;
  final String headingSource;
  final String magneticAccuracy;
  final double rotationHeadingAccuracyDeg;
  final double cadenceHz;
  final double pitchDeg;
  final double rollDeg;

  /// heading reference가 자북 기준인지. false면 arbitrary corrected fallback이다.
  final bool headingReferenceIsMagneticNorth;

  /// accel peak reject 사유별 카운트.
  final Map<String, int> peakRejectHistogram;

  // ── heading 분해(진단 전용) ──
  //
  // 경로에 실제로 쓰이는 값은 `walkingHeadingDeg = fusedHeadingDeg +
  // walkOffsetDeg` 하나뿐이라, 방향이 틀렸을 때 원인이 자력계인지 우리 보정
  // 단계인지 사후에 구분할 수 없었다. 아래 값들이 그 분해를 남긴다.
  //
  //  - [deviceHeadingDeg]와 [fusedHeadingDeg]가 함께 틀리면 → 자력계.
  //    OS가 직접 계산한 heading과 우리 유도식이 일치한다는 뜻이다.
  //  - [fusedHeadingDeg]는 맞는데 walking heading이 틀리면 → [walkOffsetDeg].
  //  - [deviceHeadingDeg]는 맞는데 [fusedHeadingDeg]가 틀리면 → 네이티브 유도식.
  //  - [gyroHeadingDeg]는 자력계와 독립이라, fused만 흔들리고 gyro는 매끄러우면
  //    자기장 쪽 문제이고, 셋이 같이 움직이면 사용자가 실제로 돈 것이다.

  /// walkOffset 적용 **전** 자북 기준 heading(smoothing 후).
  final double fusedHeadingDeg;

  /// [WalkOffsetEstimator]가 더한 보정량. ±60°로 clamp된다.
  final double walkOffsetDeg;

  /// 이 샘플 시점에 walkOffset이 실제로 갱신 중이었는지.
  final bool walkOffsetActive;

  /// OS가 직접 계산한 heading(iOS `CMDeviceMotion.heading`). 미가용이면 -1.
  final double deviceHeadingDeg;

  /// 자력계와 독립인 자이로 적분 heading. 절대 기준은 없고 상대 변화만 유효하다.
  final double gyroHeadingDeg;

  /// walkOffset이 참조한 가속도 기반 보행축과 그 신뢰도(0~1).
  final double walkDirDeg;
  final double walkDirConfidence;

  /// heading이 자리를 잡았는지([HeadingConvergenceTracker]). native의
  /// [headingStable]은 기기 기울기만 보므로 세션 시작 직후에도 true다.
  final bool headingConverged;

  /// 수렴 판정 창에서의 최대 편차(도). 클수록 방향이 흔들리는 중이다.
  final double headingSpreadDeg;
}

/// 품질 판정 결과.
class PdrQuality {
  const PdrQuality({
    required this.state,
    required this.warnings,
    required this.features,
  });

  final PdrQualityState state;
  final List<String> warnings;
  final PdrQualityFeatures features;
}
