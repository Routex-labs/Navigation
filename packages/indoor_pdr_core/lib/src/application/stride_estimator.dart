import 'dart:math' as math;

/// confirmed path에 쓸 step distance를 고른다.
///
/// 우선순위는 Apple distance delta, Apple cadence/pace, fallback stride 순서다.
///
/// 연구 앱 `lib/src/pdr/stride_estimator.dart`에서 그대로 옮겼다(Flutter 비의존).
class StrideEstimator {
  static const double minMeters = 0.35;
  static const double maxMeters = 1.20;
  static const double _maxChangeFraction = 0.20;

  double fallbackMeters = 0.70;
  double iosDistanceM = 0;
  bool distanceAvailable = false;
  double cadenceHz = 0;
  double paceSecPerM = 0;
  bool cadenceAvailable = false;
  bool paceAvailable = false;
  double trackedDistanceM = 0;
  double effectiveMeters = 0.70;
  double lastBatchMeters = 0.70;
  String source = 'fixed';
  String rejectReason = 'none';

  /// Android의 cadence/가속도 후보는 거리 스케일에 자동 적용하지 않는다. 기종·폰
  /// 위치 차이를 라벨 없이 일반화할 수 없기 때문이다. 대신 이후 실측 검증용으로
  /// conservative candidate만 유지한다.
  double cadenceCandidateMeters = 0.70;
  double weinbergCandidateMeters = 0.70;
  double shadowCandidateMeters = 0.70;
  double androidCandidateConfidence = 0;

  double? _lastNativeDistanceM;
  int? _lastDistanceSteps;

  double autoMeters(int nativeSessionSteps) =>
      nativeSessionSteps > 0 ? iosDistanceM / nativeSessionSteps : 0;

  double get cadenceMeters =>
      paceSecPerM > 0 && cadenceHz > 0 ? 1.0 / (paceSecPerM * cadenceHz) : 0;

  double resolve({
    required int deltaSteps,
    required int cumulativeSteps,
    required int trackedSteps,
    required double? nativeDistanceM,
    required bool nativeDistanceAvailable,
    bool isAndroid = false,
    double? stepAccelAmplitudeMps2,
  }) {
    _updateAndroidCandidates(
      isAndroid: isAndroid,
      cadence: cadenceHz,
      amplitudeMps2: stepAccelAmplitudeMps2,
    );
    final apple = _appleDistanceStride(
      deltaSteps: deltaSteps,
      cumulativeSteps: cumulativeSteps,
      nativeDistanceM: nativeDistanceM,
      nativeDistanceAvailable: nativeDistanceAvailable,
    );
    final cadence = apple == null ? _cadencePaceStride() : null;
    final measured = apple ?? cadence ?? fallbackMeters;

    lastBatchMeters = measured;
    source = apple != null
        ? 'apple-distance'
        : cadence != null
        ? 'cadence-pace'
        : 'fixed';
    if (apple != null) {
      rejectReason = 'none';
    } else if (cadence != null) {
      rejectReason = 'apple: $rejectReason';
    } else if (rejectReason == 'none') {
      rejectReason = isAndroid
          ? 'android shadow candidates; fixed fallback'
          : 'fixed fallback';
    }

    effectiveMeters = _smooth(measured, trackedSteps);
    adoptDistanceBaseline(
      cumulativeSteps: cumulativeSteps,
      nativeDistanceM: nativeDistanceM,
      nativeDistanceAvailable: nativeDistanceAvailable,
    );
    return effectiveMeters;
  }

  void adoptDistanceBaseline({
    required int cumulativeSteps,
    required double? nativeDistanceM,
    required bool nativeDistanceAvailable,
  }) {
    if (!nativeDistanceAvailable || nativeDistanceM == null) {
      return;
    }
    _lastNativeDistanceM = nativeDistanceM;
    _lastDistanceSteps = cumulativeSteps;
  }

  void addTrackedDistance(double meters) {
    trackedDistanceM += meters;
  }

  /// 네이티브 거리 baseline과 학습된 보폭은 유지하고 표시 경로 거리만 0으로
  /// 되돌린다. baseline을 버리면 다음 누적 distance가 이전 구간까지 포함한 값으로
  /// 들어와 첫 배치 보폭을 왜곡한다.
  void rebaseTrackedDistance() {
    trackedDistanceM = 0;
  }

  void reset() {
    iosDistanceM = 0;
    distanceAvailable = false;
    cadenceHz = 0;
    paceSecPerM = 0;
    cadenceAvailable = false;
    paceAvailable = false;
    trackedDistanceM = 0;
    effectiveMeters = fallbackMeters;
    lastBatchMeters = fallbackMeters;
    source = 'fixed';
    rejectReason = 'none';
    cadenceCandidateMeters = fallbackMeters;
    weinbergCandidateMeters = fallbackMeters;
    shadowCandidateMeters = fallbackMeters;
    androidCandidateConfidence = 0;
    _lastNativeDistanceM = null;
    _lastDistanceSteps = null;
  }

  static bool valid(double meters) =>
      meters >= minMeters && meters <= maxMeters;

  double? _appleDistanceStride({
    required int deltaSteps,
    required int cumulativeSteps,
    required double? nativeDistanceM,
    required bool nativeDistanceAvailable,
  }) {
    if (!nativeDistanceAvailable || nativeDistanceM == null) {
      rejectReason = 'nil distance';
      return null;
    }
    if (_lastNativeDistanceM == null || _lastDistanceSteps == null) {
      if (cumulativeSteps == deltaSteps && nativeDistanceM > 0) {
        final measured = nativeDistanceM / deltaSteps;
        if (valid(measured)) {
          return measured;
        }
        rejectReason = 'distance out of range';
        return null;
      }
      rejectReason = 'distance baseline';
      return null;
    }
    final distanceStepDelta = cumulativeSteps - _lastDistanceSteps!;
    if (distanceStepDelta != deltaSteps) {
      rejectReason = 'distance span mismatch';
      return null;
    }
    final distanceDelta = nativeDistanceM - _lastNativeDistanceM!;
    if (distanceDelta <= 0) {
      rejectReason = 'zero distance delta';
      return null;
    }
    final measured = distanceDelta / deltaSteps;
    if (!valid(measured)) {
      rejectReason = 'distance out of range';
      return null;
    }
    return measured;
  }

  double? _cadencePaceStride() {
    if (!cadenceAvailable ||
        !paceAvailable ||
        cadenceHz <= 0 ||
        paceSecPerM <= 0) {
      return null;
    }
    final measured = 1.0 / (paceSecPerM * cadenceHz);
    return valid(measured) ? measured : null;
  }

  double _smooth(double measured, int trackedSteps) {
    final previous = effectiveMeters > 0 ? effectiveMeters : measured;
    final lower = previous * (1 - _maxChangeFraction);
    final upper = previous * (1 + _maxChangeFraction);
    final capped = measured.clamp(lower, upper).toDouble();
    final alpha = trackedSteps < 10 ? 0.45 : 0.20;
    return (previous + (capped - previous) * alpha)
        .clamp(minMeters, maxMeters)
        .toDouble();
  }

  void _updateAndroidCandidates({
    required bool isAndroid,
    required double cadence,
    required double? amplitudeMps2,
  }) {
    if (!isAndroid) return;
    final base = fallbackMeters;
    final hasCadence = cadence.isFinite && cadence >= 0.5 && cadence <= 3.5;
    final hasAmplitude =
        amplitudeMps2 != null &&
        amplitudeMps2.isFinite &&
        amplitudeMps2 >= 0.2 &&
        amplitudeMps2 <= 12;
    cadenceCandidateMeters = hasCadence
        ? (base * math.pow(cadence / 1.75, 0.18))
              .clamp(minMeters, maxMeters)
              .toDouble()
        : base;
    weinbergCandidateMeters = hasAmplitude
        ? (base * math.pow((amplitudeMps2 / 2).clamp(0.25, 4), 0.25))
              .clamp(minMeters, maxMeters)
              .toDouble()
        : base;
    shadowCandidateMeters = switch ((hasCadence, hasAmplitude)) {
      (true, true) => (cadenceCandidateMeters + weinbergCandidateMeters) / 2,
      (true, false) => cadenceCandidateMeters,
      (false, true) => weinbergCandidateMeters,
      (false, false) => base,
    };
    androidCandidateConfidence = switch ((hasCadence, hasAmplitude)) {
      (true, true) => 0.65,
      (true, false) || (false, true) => 0.40,
      (false, false) => 0.0,
    };
  }
}
