import 'dart:math' as math;

import '../domain/events.dart';
import 'stride_estimator.dart';
import 'tracking_timeline.dart';

/// 처리된 CMPedometer 배치의 진단 레코드.
///
/// 연구 앱은 이 정보를 `Map<String,Object?>`로 쌓아 export/quality가 함께 읽었다.
/// 코어는 JSON export를 하지 않으므로, quality(undercount 스캔)가 읽는 필드만 담은
/// 타입 레코드로 대체한다.
class PedometerBatchRecord {
  const PedometerBatchRecord({
    required this.batchId,
    required this.spanStartMs,
    required this.spanEndMs,
    required this.cumulativeSteps,
    required this.deltaSteps,
    required this.stepPeakTimes,
    required this.appliedSteps,
  });

  final int batchId;
  final int? spanStartMs;
  final int? spanEndMs;
  final int cumulativeSteps;
  final int deltaSteps;
  final List<double>? stepPeakTimes;
  final int appliedSteps;
}

/// path에 반영할 confirmed step 묶음(초록 경로 입력).
class PedometerBatchApplication {
  const PedometerBatchApplication({
    required this.appliedSteps,
    required this.deltaSteps,
    required this.batchId,
    required this.createdAtMs,
    required this.strideSource,
    required this.stepDistanceMeters,
    required this.spanStartMs,
    required this.spanEndMs,
    required this.peakTimes,
  });

  final int appliedSteps;

  /// 이 배치의 총 step 증가분(tracking split 적용 전).
  final int deltaSteps;
  final int batchId;
  final int? createdAtMs;
  final String strideSource;
  final double stepDistanceMeters;
  final int? spanStartMs;
  final int? spanEndMs;
  final List<double>? peakTimes;
}

/// 연구 앱 `pedometer_batch_processor.dart`를 옮겼다. `_batches`만 타입 레코드로 대체.
class PedometerBatchProcessor {
  final TrackingTimeline _trackingTimeline = TrackingTimeline();
  final List<PedometerBatchRecord> _batches = [];

  int _nextBatchId = 1;
  int? _lastNativeSteps;
  int _stepSessionId = -1;
  int? _lastPedometerEndMs;

  int nativeSessionSteps = 0;
  int lastStepDelta = 0;
  int? lastStepAtMs;
  double gapMs = 0;

  List<PedometerBatchRecord> get batches => _batches;

  void addTrackingTransition({required int atMs, required bool on}) {
    _trackingTimeline.addTransition(atMs: atMs, on: on);
  }

  void reset({required bool initialTrackingOn, int? newSessionId}) {
    nativeSessionSteps = 0;
    _lastNativeSteps = null;
    lastStepDelta = 0;
    lastStepAtMs = null;
    _lastPedometerEndMs = null;
    _batches.clear();
    _nextBatchId = 1;
    _trackingTimeline.reset(initialOn: initialTrackingOn);
    if (newSessionId != null) {
      _stepSessionId = newSessionId;
    }
  }

  PedometerBatchApplication? process(
    PedometerBatchEvent event, {
    required int receivedAtMs,
    required bool tracking,
    required bool hasHeading,
    required int trackedSteps,
    required StrideEstimator stride,
  }) {
    final steps = event.steps;
    final sessionId = event.stepSessionId ?? _stepSessionId;
    if (sessionId < _stepSessionId) {
      return null;
    }

    final sessionStartMs = event.sessionStartMs;
    final spanStartMs = _lastPedometerEndMs ?? sessionStartMs;
    final endMs = event.timestampMs;
    final hasBatchWindow =
        sessionStartMs != null && endMs != null && endMs > sessionStartMs;

    final deltaSteps = _resolveDeltaSteps(
      sessionId: sessionId,
      steps: steps,
      hasBatchWindow: hasBatchWindow,
    );
    _lastNativeSteps = steps;
    nativeSessionSteps = steps;

    if (endMs != null && endMs > 0) {
      _lastPedometerEndMs = endMs.round();
    }
    gapMs = event.deltaMs ?? gapMs;

    final nativeDistanceM = event.distanceM;
    stride.distanceAvailable =
        event.distanceAvailable ?? nativeDistanceM != null;
    if (stride.distanceAvailable && nativeDistanceM != null) {
      stride.iosDistanceM = nativeDistanceM;
    }
    stride.cadenceHz = event.cadenceHz ?? stride.cadenceHz;
    stride.paceSecPerM = event.paceSecPerM ?? stride.paceSecPerM;
    stride.cadenceAvailable = event.cadenceAvailable ?? stride.cadenceHz > 0;
    stride.paceAvailable = event.paceAvailable ?? stride.paceSecPerM > 0;

    if (deltaSteps <= 0) {
      stride.adoptDistanceBaseline(
        cumulativeSteps: steps,
        nativeDistanceM: nativeDistanceM,
        nativeDistanceAvailable: stride.distanceAvailable,
      );
      return null;
    }

    lastStepDelta = deltaSteps;
    lastStepAtMs = receivedAtMs;
    final stepDistance = stride.resolve(
      deltaSteps: deltaSteps,
      cumulativeSteps: steps,
      trackedSteps: trackedSteps,
      nativeDistanceM: nativeDistanceM,
      nativeDistanceAvailable: stride.distanceAvailable,
    );
    final peakTimes = event.stepPeakTimes;
    final batchId = _nextBatchId++;
    final split = _trackingTimeline.resolveBatch(
      deltaSteps: deltaSteps,
      spanStartMs: spanStartMs,
      spanEndMs: _lastPedometerEndMs,
      peakTimes: peakTimes,
      currentlyTracking: tracking,
    );
    final appliedSteps = hasHeading ? split.count : 0;
    _batches.add(
      PedometerBatchRecord(
        batchId: batchId,
        spanStartMs: spanStartMs,
        spanEndMs: _lastPedometerEndMs,
        cumulativeSteps: steps,
        deltaSteps: deltaSteps,
        stepPeakTimes: peakTimes,
        appliedSteps: appliedSteps,
      ),
    );
    if (appliedSteps <= 0) {
      return null;
    }
    return PedometerBatchApplication(
      appliedSteps: appliedSteps,
      deltaSteps: deltaSteps,
      batchId: batchId,
      createdAtMs: receivedAtMs,
      strideSource: stride.source,
      stepDistanceMeters: stepDistance,
      spanStartMs: split.spanStartMs,
      spanEndMs: split.spanEndMs,
      peakTimes: split.peakTimes,
    );
  }

  int _resolveDeltaSteps({
    required int sessionId,
    required int steps,
    required bool hasBatchWindow,
  }) {
    if (sessionId > _stepSessionId) {
      _stepSessionId = sessionId;
      return hasBatchWindow ? math.max(0, steps) : 0;
    }
    if (_lastNativeSteps == null) {
      return hasBatchWindow ? math.max(0, steps) : 0;
    }
    return math.max(0, steps - _lastNativeSteps!);
  }
}
