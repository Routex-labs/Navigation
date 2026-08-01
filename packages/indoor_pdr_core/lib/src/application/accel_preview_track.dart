import 'dart:math' as math;

import '../domain/events.dart';
import '../domain/heading_sample.dart';
import '../domain/pdr_local_point.dart';
import 'stride_estimator.dart';

/// accel peak만으로 누적하는 raw-ish preview path(주황).
///
/// confirmed path/distance/count에는 영향을 주지 않는 비교용 경로다.
///
/// 연구 앱 `accel_preview_track.dart`에서 옮겼다. `Offset`→`PdrLocalPoint`로 바꾸고
/// export 전용 stepEvents/peakEvents/recentRejects/pathPoints는 제거했다.
/// quality가 읽는 [rejectReasons] 히스토그램은 보존한다.
class AccelPreviewTrack {
  AccelPreviewTrack({this.maxPoints = 800});

  static const int maxStepLead = 12;
  static const double maxDistanceLeadMeters = 10.0;
  static const int maxInitialStepLead = 30;
  static const double maxInitialDistanceLeadMeters = 24.0;
  static const int minPeakIntervalMs = 300;
  static const int maxPeakIntervalMs = 1100;

  static const String baseline = 'baseline';
  static const String tooDense = 'tooDense';
  static const String tooSparse = 'tooSparse';
  static const String cadenceMismatch = 'cadenceMismatch';
  static const String stepLeadCap = 'stepLeadCap';
  static const String distanceLeadCap = 'distanceLeadCap';
  static const String notTracking = 'notTracking';
  static const String noHeading = 'noHeading';
  static const String missingTimestamp = 'missingTimestamp';
  static const String batchedPeaksCapped = 'batchedPeaksCapped';

  final int maxPoints;
  final List<PdrLocalPoint> path = [PdrLocalPoint.zero];

  /// [path]와 같은 길이·같은 인덱스로 유지되는, 실제 반영된 peak 시각.
  ///
  /// 거부된 peak는 path에 점을 만들지 않으므로 여기에도 남지 않는다. 원점은
  /// 대응 peak가 없어 null이다. 배치 peak(`delta > 1`)는 알고 있는 시각이
  /// `latestPeakMs` 하나뿐이라 같은 값을 delta번 넣어 인덱스를 맞춘다.
  final List<int?> acceptedPeakTimesMs = [null];

  PdrLocalPoint position = PdrLocalPoint.zero;
  int steps = 0;
  int acceptedPeaks = 0;
  int rejectedPeaks = 0;
  int? lastStepAtMs;
  String lastRejectReason = 'none';
  double distanceM = 0;
  final Map<String, int> rejectReasons = {
    baseline: 0,
    tooDense: 0,
    tooSparse: 0,
    cadenceMismatch: 0,
    stepLeadCap: 0,
    distanceLeadCap: 0,
    notTracking: 0,
    noHeading: 0,
    missingTimestamp: 0,
    batchedPeaksCapped: 0,
  };

  int? _lastPeakCount;
  int? _lastAcceptedPeakMs;
  int? _lastGatePeakMs;

  bool applyRealtimePeaks(
    AccelPeakEvent? signal, {
    required bool tracking,
    required bool hasHeading,
    required double effectiveStrideMeters,
    required double fallbackStrideMeters,
    required int confirmedSteps,
    required double confirmedDistanceM,
    int? confirmedThroughMs,
    required double? pedometerCadenceHz,
    required HeadingSample? Function(int ms) headingAt,
    required double fallbackHeadingDeg,
  }) {
    if (signal == null) {
      return false;
    }
    final count = signal.count;
    final peakMs = signal.latestPeakMs;

    final previousCount = _lastPeakCount;
    if (previousCount == null || count < previousCount) {
      _lastPeakCount = count;
      _resyncGate(peakMs);
      _recordReject(reason: baseline, deltaPeaks: 0, counted: false);
      return false;
    }

    final delta = count - previousCount;
    _lastPeakCount = count;
    if (delta <= 0) {
      return false;
    }

    if (peakMs == null) {
      _recordReject(reason: missingTimestamp, deltaPeaks: delta);
      return false;
    }
    if (!tracking || !hasHeading) {
      final reason = tracking ? noHeading : notTracking;
      _resyncGate(peakMs);
      _recordReject(reason: reason, deltaPeaks: delta);
      return false;
    }

    if (delta > 1) {
      _recordReject(
        reason: batchedPeaksCapped,
        deltaPeaks: delta - 1,
        counted: false,
      );
    }
    final intervalCheck = _checkInterval(peakMs, pedometerCadenceHz);
    if (intervalCheck.reason != null) {
      _recordReject(
        reason: intervalCheck.reason!,
        deltaPeaks: 1,
        counted: false,
      );
      if (intervalCheck.resync) {
        _resyncGate(peakMs);
      }
    }

    final sample = headingAt(peakMs);
    final headingDeg = sample?.walkDeg ?? fallbackHeadingDeg;
    final stride = _resolveStepDistance(
      effectiveStrideMeters: effectiveStrideMeters,
      fallbackStrideMeters: fallbackStrideMeters,
    );
    final leadReason = _leadCapReason(
      stride.meters,
      confirmedSteps: confirmedSteps,
      confirmedDistanceM: confirmedDistanceM,
      confirmedThroughMs: confirmedThroughMs,
    );
    if (leadReason != null) {
      // 실제로 걸음을 버려야 lead cap이 의미가 있다. 예전에는 여기서 reject만
      // 기록하고 아래로 그대로 흘러가, position·path·steps·distanceM에 전부
      // 반영된 뒤 lastRejectReason까지 'none'으로 덮였다. 그래서 캡이 사실상
      // no-op이었고 preview가 confirmed보다 무한히 앞서 나갔다(실측 세션에서
      // stepLeadCap 133건이 기록됐는데도 preview가 confirmed+12를 훌쩍 넘긴
      // 163걸음까지 갔다). 위쪽 다른 reject 경로들과 동일하게 여기서 끊는다.
      _resyncGate(peakMs);
      _recordReject(reason: leadReason, deltaPeaks: delta);
      return false;
    }

    final headingRad = headingDeg * math.pi / 180;
    final stepOffset = PdrLocalPoint(
      math.sin(headingRad) * stride.meters,
      math.cos(headingRad) * stride.meters,
    );

    for (var i = 0; i < delta; i += 1) {
      position += stepOffset;
      path.add(position);
      acceptedPeakTimesMs.add(peakMs);
    }
    steps += delta;
    acceptedPeaks += delta;
    distanceM += stride.meters * delta;
    _trim();
    lastStepAtMs = peakMs;
    _lastAcceptedPeakMs = peakMs;
    _resyncGate(peakMs);
    lastRejectReason = 'none';
    return true;
  }

  void reset({bool preserveNativePeakBaseline = false}) {
    final nativePeakBaseline = _lastPeakCount;
    path
      ..clear()
      ..add(PdrLocalPoint.zero);
    acceptedPeakTimesMs
      ..clear()
      ..add(null);
    position = PdrLocalPoint.zero;
    steps = 0;
    acceptedPeaks = 0;
    rejectedPeaks = 0;
    lastStepAtMs = null;
    lastRejectReason = 'none';
    distanceM = 0;
    for (final key in rejectReasons.keys.toList()) {
      rejectReasons[key] = 0;
    }
    // 위치 재지정은 센서를 재시작하는 동작이 아니다. 네이티브 누적 peak count를
    // 기억해야 다음 count가 이전 전체 누적이 아니라 정확히 한 걸음 delta가 된다.
    _lastPeakCount = preserveNativePeakBaseline ? nativePeakBaseline : null;
    _lastAcceptedPeakMs = null;
    _lastGatePeakMs = null;
  }

  void _trim() {
    if (path.length > maxPoints) {
      final drop = path.length - maxPoints;
      path.removeRange(0, drop);
      // 인덱스 정렬이 깨지면 확정 소비가 엉뚱한 걸음을 지우므로 반드시 함께 자른다.
      acceptedPeakTimesMs.removeRange(0, drop);
    }
  }

  ({String? reason, bool resync, int? intervalMs, double? expectedIntervalMs})
  _checkInterval(int peakMs, double? pedometerCadenceHz) {
    final previous = _lastGatePeakMs ?? _lastAcceptedPeakMs;
    if (previous == null) {
      return (
        reason: null,
        resync: false,
        intervalMs: null,
        expectedIntervalMs: null,
      );
    }
    final intervalMs = peakMs - previous;
    if (intervalMs < minPeakIntervalMs) {
      return (
        reason: tooDense,
        resync: false,
        intervalMs: intervalMs,
        expectedIntervalMs: null,
      );
    }
    if (intervalMs > maxPeakIntervalMs) {
      return (
        reason: tooSparse,
        resync: true,
        intervalMs: intervalMs,
        expectedIntervalMs: null,
      );
    }

    if (pedometerCadenceHz != null && pedometerCadenceHz > 0.2) {
      final expectedMs = 1000.0 / pedometerCadenceHz;
      // CMPedometer cadence는 배치/평균값이라 realtime accel peak와 정확히 같은
      // cadence를 보장하지 않는다. 특히 peak detector가 한쪽 발/강한 peak만 잡으면
      // 실제 interval이 Apple cadence의 2배 근처로 보일 수 있다.
      if (intervalMs < expectedMs * 0.45 || intervalMs > expectedMs * 2.60) {
        return (
          reason: cadenceMismatch,
          resync: true,
          intervalMs: intervalMs,
          expectedIntervalMs: expectedMs,
        );
      }
    }
    return (
      reason: null,
      resync: false,
      intervalMs: intervalMs,
      expectedIntervalMs: pedometerCadenceHz != null && pedometerCadenceHz > 0.2
          ? 1000.0 / pedometerCadenceHz
          : null,
    );
  }

  String? _leadCapReason(
    double stepDistance, {
    required int confirmedSteps,
    required double confirmedDistanceM,
    int? confirmedThroughMs,
  }) {
    if (confirmedThroughMs != null) {
      var pendingSteps = 0;
      var pendingDistanceM = 0.0;
      for (var index = 1; index < acceptedPeakTimesMs.length; index++) {
        final peakMs = acceptedPeakTimesMs[index];
        if (peakMs == null || peakMs <= confirmedThroughMs) continue;
        pendingSteps++;
        if (index < path.length) {
          pendingDistanceM += (path[index] - path[index - 1]).distance;
        }
      }
      if (pendingSteps + 1 > maxStepLead) return stepLeadCap;
      if (pendingDistanceM + stepDistance > maxDistanceLeadMeters) {
        return distanceLeadCap;
      }
      return null;
    }
    // 첫 CMPedometer batch는 실제 기기에서 7~10초 늦게 올 수 있다.
    // confirmed가 아직 0이면 일반 lead cap보다 넓게 허용해서 preview가 초반에
    // 12 step에서 멈추지 않게 한다. confirmed가 한 번이라도 들어오면 기존 cap으로
    // 돌아가서 raw-ish 경로가 무한히 앞서가는 것을 막는다.
    final stepLead = confirmedSteps == 0 ? maxInitialStepLead : maxStepLead;
    final distanceLead = confirmedDistanceM <= 0
        ? maxInitialDistanceLeadMeters
        : maxDistanceLeadMeters;
    if (steps + 1 > confirmedSteps + stepLead) {
      return stepLeadCap;
    }
    if (distanceM + stepDistance > confirmedDistanceM + distanceLead) {
      return distanceLeadCap;
    }
    return null;
  }

  ({double meters, String source}) _resolveStepDistance({
    required double effectiveStrideMeters,
    required double fallbackStrideMeters,
  }) {
    if (StrideEstimator.valid(effectiveStrideMeters)) {
      return (meters: effectiveStrideMeters, source: 'effective');
    }
    if (StrideEstimator.valid(fallbackStrideMeters)) {
      return (meters: fallbackStrideMeters, source: 'fallback');
    }
    return (meters: 0.70, source: 'default');
  }

  void _resyncGate(int? peakMs) {
    if (peakMs != null) {
      _lastGatePeakMs = peakMs;
    }
  }

  void _recordReject({
    required String reason,
    required int deltaPeaks,
    bool counted = true,
  }) {
    final count = math.max(0, deltaPeaks);
    if (counted) {
      rejectedPeaks += count;
    }
    rejectReasons[reason] = (rejectReasons[reason] ?? 0) + count;
    lastRejectReason = _label(reason);
  }

  String _label(String reason) {
    switch (reason) {
      case tooDense:
        return 'too dense';
      case tooSparse:
        return 'too sparse';
      case cadenceMismatch:
        return 'cadence mismatch';
      case stepLeadCap:
        return 'step lead cap';
      case distanceLeadCap:
        return 'distance lead cap';
      case notTracking:
        return 'not tracking';
      case noHeading:
        return 'no heading';
      case missingTimestamp:
        return 'missing timestamp';
      case batchedPeaksCapped:
        return 'batched peaks capped';
      case baseline:
        return 'baseline';
      default:
        return reason;
    }
  }
}
