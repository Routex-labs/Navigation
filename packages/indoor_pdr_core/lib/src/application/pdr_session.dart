import 'dart:async';
import 'dart:math' as math;

import '../domain/angle_utils.dart';
import '../domain/events.dart';
import '../domain/heading_reference.dart';
import '../domain/heading_sample.dart';
import '../domain/pdr_local_point.dart';
import '../domain/quality.dart';
import '../domain/snapshot.dart';
import 'accel_preview_track.dart';
import 'heading_trackers.dart';
import 'path_accumulator.dart';
import 'pedometer_batch_processor.dart';
import 'pdr_session_config.dart';
import 'quality_metrics.dart';
import 'stride_estimator.dart';

/// 적용된 confirmed 배치의 진단 정보. [PdrSession.onBatchApplied]로 전달된다.
class AppliedBatchInfo {
  const AppliedBatchInfo({
    required this.batchId,
    required this.deltaSteps,
    required this.appliedSteps,
    required this.stepDistanceMeters,
    required this.strideSource,
  });

  final int batchId;
  final int deltaSteps;
  final int appliedSteps;
  final double stepDistanceMeters;
  final String strideSource;
}

/// 위젯·플랫폼·지도·GPS·ML·export에 의존하지 않는 PDR 코어.
///
/// typed 센서 이벤트를 받아 confirmed(초록) 경로/거리와 preview(주황) 경로, 품질
/// 신호를 유지한다. 연구 앱 `PdrEngine`의 오케스트레이션을 재작성했다:
///   - `Offset`→`PdrLocalPoint`, `ValueNotifier`→`Stream<PdrSnapshot>`
///   - GPS reference / IMU v3 / ML preview / JSON export / relative-display baseline 제외
///
/// 위치 계산:
///   거리 = CMPedometer step delta × 추정 보폭
///   방향 = fused heading smoothing + walkOffset 보정
class PdrSession {
  PdrSession({PdrSessionConfig? config})
      : config = config ?? const PdrSessionConfig() {
    _paths = PathAccumulator(maxPoints: this.config.maxPathPoints);
    _accelPreview = AccelPreviewTrack(maxPoints: this.config.maxPathPoints);
    _stride.fallbackMeters = this.config.fallbackStrideMeters;
    _stride.effectiveMeters = this.config.fallbackStrideMeters;
    _stride.lastBatchMeters = this.config.fallbackStrideMeters;
  }

  final PdrSessionConfig config;

  late final PathAccumulator _paths;
  late final AccelPreviewTrack _accelPreview;
  final StrideEstimator _stride = StrideEstimator();
  final PedometerBatchProcessor _pedometer = PedometerBatchProcessor();
  final SwingDetector _swing = SwingDetector();
  final WalkOffsetEstimator _walkOffset = WalkOffsetEstimator();
  final HeadingHistory _headingHistory = HeadingHistory();

  final StreamController<PdrSnapshot> _snapshots =
      StreamController<PdrSnapshot>.broadcast();

  bool _tracking = true;

  // fused heading 상태.
  bool hasFusedHeading = false;
  double fusedHeadingDeg = 0;
  bool headingStable = false;
  String headingSource = 'waiting';
  double deviceHeadingDeg = -1;
  double yawDeg = 0;
  double gyroHeadingDeg = 0;
  double pitchDeg = 0;
  double rollDeg = 0;
  String magneticAccuracy = 'unknown';
  double walkDirDeg = 0;
  double walkDirConfidence = 0;
  int? lastMotionAtMs;

  int iosTrackedSteps = 0;

  /// 적용된 confirmed 배치 진단 훅(telemetry/테스트용). appliedSteps>0일 때만 호출.
  void Function(AppliedBatchInfo info)? onBatchApplied;

  // ── 파생 상태 ──

  bool get tracking => _tracking;

  /// fused heading + walkOffset. confirmed path 방향의 기준.
  double get walkingHeadingDeg =>
      normalizeDegrees(fusedHeadingDeg + _walkOffset.offsetDeg);

  HeadingReference get headingReference =>
      headingReferenceFromSource(headingSource);

  PdrLocalPoint get position => _paths.correctedPosition;
  List<PdrLocalPoint> get path => List.unmodifiable(_paths.corrected);
  int get steps => iosTrackedSteps;

  /// confirmed 이동 거리(m). tracking 중 반영한 step distance 합.
  double get distanceM => _stride.trackedDistanceM;

  Stream<PdrSnapshot> get snapshots => _snapshots.stream;

  // ── 이벤트 입력 ──

  /// CoreMotion DeviceMotion 이벤트. heading smoothing/swing/walkOffset/history 갱신.
  void onHeading(HeadingEvent e) {
    headingSource = e.headingSource ?? headingSource;
    deviceHeadingDeg = e.deviceHeadingDeg ?? deviceHeadingDeg;
    magneticAccuracy = e.magneticAccuracy ?? magneticAccuracy;
    headingStable = e.headingStable ?? headingStable;
    yawDeg = e.yawDeg ?? yawDeg;
    gyroHeadingDeg = e.gyroHeadingDeg ?? gyroHeadingDeg;
    pitchDeg = e.pitchDeg ?? pitchDeg;
    rollDeg = e.rollDeg ?? rollDeg;
    walkDirDeg = e.walkDirDeg ?? walkDirDeg;
    walkDirConfidence = e.walkDirConfidence ?? walkDirConfidence;

    // motionTimestamp는 native step peak timestamp와 같은 시간축이다.
    final motionMs = e.motionTimestampMs;
    final dtSeconds =
        ((motionMs - (lastMotionAtMs ?? motionMs)) / 1000.0).clamp(0.0, 0.5);
    lastMotionAtMs = motionMs;

    // 팔 흔들림은 smoothing 전 raw heading으로 판단한다.
    _swing.update(motionMs, e.fusedHeadingDeg);
    _updateFusedHeading(e.fusedHeadingDeg, dtSeconds);
    _walkOffset.update(
      nowMs: motionMs,
      dtSeconds: dtSeconds,
      swinging: _swing.swinging,
      swingNetDeg: _swing.netDeg,
      walkDirDeg: walkDirDeg,
      walkDirConfidence: walkDirConfidence,
      fusedHeadingDeg: fusedHeadingDeg,
    );
    _headingHistory.add(
      HeadingSample(
        ms: motionMs,
        walkDeg: walkingHeadingDeg,
        fusedDeg: fusedHeadingDeg,
        yawDeg: yawDeg,
        deviceHeadingDeg: deviceHeadingDeg,
      ),
    );
  }

  /// native accel step-peak 신호. 주황 preview 경로에만 반영.
  void onAccelPeak(AccelPeakEvent e) {
    final changed = _accelPreview.applyRealtimePeaks(
      e,
      tracking: _tracking,
      hasHeading: hasFusedHeading,
      effectiveStrideMeters: _stride.effectiveMeters,
      fallbackStrideMeters: _stride.fallbackMeters,
      confirmedSteps: iosTrackedSteps,
      confirmedDistanceM: _stride.trackedDistanceM,
      pedometerCadenceHz:
          _stride.cadenceAvailable ? _stride.cadenceHz : null,
      headingAt: _headingHistory.at,
      fallbackHeadingDeg: walkingHeadingDeg,
    );
    if (changed) {
      _emit();
    }
  }

  /// CMPedometer 배치. confirmed(초록) 경로/거리에 반영.
  void onPedometerBatch(PedometerBatchEvent e) {
    final application = _pedometer.process(
      e,
      receivedAtMs: config.nowMs(),
      tracking: _tracking,
      hasHeading: hasFusedHeading,
      trackedSteps: iosTrackedSteps,
      stride: _stride,
    );
    if (application == null) {
      return;
    }
    final applied = _paths.applyPedometerBatch(
      count: application.appliedSteps,
      stepDistanceMeters: application.stepDistanceMeters,
      currentWalkDeg: walkingHeadingDeg,
      currentFusedDeg: fusedHeadingDeg,
      headingAt: _headingHistory.at,
      spanStartMs: application.spanStartMs,
      spanEndMs: application.spanEndMs,
      peakTimes: application.peakTimes,
    );
    iosTrackedSteps += applied;
    _stride.addTrackedDistance(application.stepDistanceMeters * applied);
    onBatchApplied?.call(
      AppliedBatchInfo(
        batchId: application.batchId,
        deltaSteps: application.deltaSteps,
        appliedSteps: applied,
        stepDistanceMeters: application.stepDistanceMeters,
        strideSource: application.strideSource,
      ),
    );
    _emit();
  }

  // ── 외부 command ──

  /// pause. 전이 시각을 motion 시간축으로 기록해 늦은 batch를 시간축으로 분할한다.
  void pause({required int atMs}) => _setTracking(false, atMs);

  void resume({required int atMs}) => _setTracking(true, atMs);

  /// 경로·추정 상태 초기화. [newStepSessionId] 이후 pedometer event만 받는다.
  void reset({int? newStepSessionId}) {
    _paths.reset();
    _accelPreview.reset();
    iosTrackedSteps = 0;
    _pedometer.reset(
      initialTrackingOn: _tracking,
      newSessionId: newStepSessionId,
    );
    _headingHistory.clear();
    _stride.reset();
    _swing.reset();
    walkDirConfidence = 0;
    _walkOffset.reset();
    _emit();
  }

  /// 현재 스냅샷을 즉시 만든다.
  PdrSnapshot get snapshot => _buildSnapshot();

  void dispose() {
    _snapshots.close();
  }

  // ── 내부 ──

  void _setTracking(bool value, int atMs) {
    if (value == _tracking) {
      return;
    }
    _tracking = value;
    _pedometer.addTrackingTransition(atMs: atMs, on: value);
  }

  /// heading smoothing 시간상수. 안정적이면 빠르게, 팔 흔들림 중이면 느리게.
  double get _headingTauSeconds {
    if (!headingStable) {
      return 0.60;
    }
    if (_swing.swinging) {
      return 1.00;
    }
    return 0.10;
  }

  /// fused heading을 최단각 exponential filter로 smoothing한다.
  void _updateFusedHeading(double targetDeg, double dtSeconds) {
    if (!hasFusedHeading) {
      hasFusedHeading = true;
      fusedHeadingDeg = normalizeDegrees(targetDeg);
      return;
    }
    final alpha = 1 - math.exp(-dtSeconds / _headingTauSeconds);
    final delta = shortestDeltaDegrees(targetDeg - fusedHeadingDeg);
    fusedHeadingDeg = normalizeDegrees(fusedHeadingDeg + delta * alpha);
  }

  void _emit() {
    if (!_snapshots.isClosed) {
      _snapshots.add(_buildSnapshot());
    }
  }

  PdrSnapshot _buildSnapshot() {
    final quality = _buildQuality();
    return PdrSnapshot(
      position: _paths.correctedPosition,
      path: List.unmodifiable(_paths.corrected),
      steps: iosTrackedSteps,
      distanceM: _stride.trackedDistanceM,
      walkingHeadingDeg: walkingHeadingDeg,
      hasHeading: hasFusedHeading,
      preview: PdrPreview(
        position: _accelPreview.position,
        path: List.unmodifiable(_accelPreview.path),
        steps: _accelPreview.steps,
        distanceM: _accelPreview.distanceM,
      ),
      quality: quality,
    );
  }

  PdrQuality _buildQuality() {
    final undercount = QualityMetrics.undercountScan(_pedometer.batches);
    final undercountSuspected =
        QualityMetrics.pedometerUndercountSuspected(_pedometer.batches);
    final overcountLikely = QualityMetrics.accelOvercountLikely(
      nativeSessionSteps: _pedometer.nativeSessionSteps,
      accelPreviewSteps: _accelPreview.steps,
      pedometerUndercountSuspected: undercountSuspected,
    );
    final green = _stride.trackedDistanceM;
    final orange = _accelPreview.distanceM;
    final divergencePct =
        green > 0 ? (orange - green).abs() / green * 100.0 : 0.0;
    final ratio = _pedometer.nativeSessionSteps > 0
        ? _accelPreview.steps / _pedometer.nativeSessionSteps
        : 0.0;

    // 판정(잠정, §5): undercount는 진단 전용이라 자동 전환에 쓰지 않지만 degraded
    // 신호로는 쓴다. divergence 단독으로 degraded를 만들지 않는다(주황 과검출일 수 있음).
    final PdrQualityState state;
    if (undercountSuspected) {
      state = PdrQualityState.degraded;
    } else if (divergencePct > config.cautionDivergencePct || overcountLikely) {
      state = PdrQualityState.caution;
    } else {
      state = PdrQualityState.healthy;
    }

    final warnings = QualityMetrics.warnings(
      nativeSessionSteps: _pedometer.nativeSessionSteps,
      accelPreviewSteps: _accelPreview.steps,
      accelPreviewRejectReasons: _accelPreview.rejectReasons,
      pedometerUndercountSuspected: undercountSuspected,
    );

    return PdrQuality(
      state: state,
      warnings: warnings,
      features: PdrQualityFeatures(
        greenOrangeDistanceDivergencePct: divergencePct,
        orangeStepRatio: ratio,
        orangeOvercountLikely: overcountLikely,
        pedometerUndercountSuspected: undercountSuspected,
        pedometerFlaggedSpanS: undercount.flaggedSpanMs / 1000.0,
        headingStable: headingStable,
        cadenceHz: _stride.cadenceHz,
        pitchDeg: pitchDeg,
        rollDeg: rollDeg,
        headingReferenceIsMagneticNorth:
            headingReference == HeadingReference.magneticNorth,
        peakRejectHistogram: Map.unmodifiable(_accelPreview.rejectReasons),
      ),
    );
  }
}
