import 'dart:async';

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../contract/indoor_navigation_contract.dart';
import '../platform/native_pdr_event.dart';
import '../platform/pdr_motion_source.dart';

/// 앱 범위 실내 내비게이션 세션을 소유하는 headless 컨트롤러.
///
/// 계약([IndoorNavigationController])을 구현한다. 위젯을 만들지 않고, PdrSession(코어)과
/// [PdrMotionSource]를 소유하며 native 이벤트를 코어로 흘린다. UI는 스트림을 관찰만 한다.
///
/// lifecycle 원칙(설계 v4 Phase 2):
///   - anchor 확정 + startGuidance에서 세션 ON
///   - 화면 전환(IndoorMap↔RouteGuide↔calibration)에는 세션 유지
///   - 안내 종료·층 변경·명시 reset·background에서만 stop/pause
class IndoorNavigationDriver implements IndoorNavigationController {
  IndoorNavigationDriver({
    required PdrMotionSource source,
    PdrSessionConfig? config,
    int Function()? nowMs,
  }) : _source = source, // ignore: prefer_initializing_formals
       _nowMs = nowMs ?? _defaultNowMs {
    _session = PdrSession(config: config);
    _sessionSub = _session.snapshots.listen(_onSnapshot);
  }

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  final PdrMotionSource _source;
  final int Function() _nowMs;

  late final PdrSession _session;
  late final StreamSubscription<PdrSnapshot> _sessionSub;
  StreamSubscription<NativePdrEvent>? _eventSub;

  final _snapshots = StreamController<PdrSnapshot>.broadcast();
  final _headingObservations =
      StreamController<PdrHeadingObservation>.broadcast();
  final _calibration = StreamController<CalibrationStatus>.broadcast();
  final _runtimeStatuses = StreamController<PdrRuntimeStatus>.broadcast();

  PdrSnapshot? _current;
  PdrHeadingObservation? _currentHeadingObservation;
  int? _lastHeadingPublishTimestampMs;
  CalibrationStatus _calib = const CalibrationStatus.uncalibrated();
  PdrRuntimeStatus _runtimeStatus = const PdrRuntimeStatus.idle();
  bool _guiding = false;
  bool _backgrounded = false;
  String? _floorId;

  // 캘리브레이션 진행 중 임시 상태.
  PdrLocalPoint? _pendingPinFloorM;
  PdrLocalPoint? _pendingPinPdrM;
  PdrToFloorAxes _pendingAxes = const PdrToFloorAxes.identity();

  // ── IndoorNavigationView ──

  @override
  Stream<PdrSnapshot> get snapshots => _snapshots.stream;

  @override
  PdrSnapshot? get currentSnapshot => _current;

  @override
  Stream<PdrHeadingObservation> get headingObservations =>
      _headingObservations.stream;

  @override
  PdrHeadingObservation? get currentHeadingObservation =>
      _currentHeadingObservation;

  @override
  Stream<CalibrationStatus> get calibration => _calibration.stream;

  @override
  CalibrationStatus get currentCalibration => _calib;

  @override
  Stream<PdrRuntimeStatus> get runtimeStatuses => _runtimeStatuses.stream;

  @override
  PdrRuntimeStatus get currentRuntimeStatus => _runtimeStatus;

  // ── IndoorNavigationIntents ──

  @override
  Future<void> startGuidance({required String floorId}) async {
    if (_guiding && _floorId == floorId) {
      return;
    }
    _floorId = floorId;
    _guiding = true;
    _backgrounded = false;
    _currentHeadingObservation = null;
    _lastHeadingPublishTimestampMs = null;
    _session.reset();
    _updateRuntime(PdrRuntimeState.starting);
    _eventSub ??= _source.events.listen(
      _onNativeEvent,
      onError: _onSourceError,
    );
    try {
      await _source.start();
      // 새 guidance는 native step-session도 반드시 새로 연다. 그렇지 않으면
      // 직전 stop에서 동결한 Android counter가 재시작 뒤에도 finalized 상태로
      // 남아 이후 걸음을 모두 무시한다.
      final newSessionId = await _source.resetPedometer();
      _session.reset(newStepSessionId: newSessionId);
    } on Object {
      _updateRuntime(
        PdrRuntimeState.degraded,
        warnings: const ['sensorStartFailed'],
      );
    }
    _updateCalibration(CalibrationPhase.awaitingPin);
  }

  @override
  Future<void> stopGuidance() async {
    if (!_guiding) {
      return;
    }
    _guiding = false;
    _backgrounded = false;
    _updateRuntime(PdrRuntimeState.stopping);
    try {
      // stop 전에 native가 보유한 마지막 STEP_COUNTER/CMPedometer 상태를
      // 한 번만 flush한다. finalize 뒤 native는 추가 pedometer callback을
      // 경로로 보내지 않으므로 종료 지점이 흔들리지 않는다.
      await _source.finalizePedometer();
      await Future<void>.delayed(Duration.zero);
    } on Object {
      _updateRuntime(
        PdrRuntimeState.degraded,
        warnings: const ['pedometerFinalizeFailed'],
      );
    }
    await _source.stop();
    _pendingPinFloorM = null;
    _pendingPinPdrM = null;
    _pendingAxes = const PdrToFloorAxes.identity();
    _currentHeadingObservation = null;
    _lastHeadingPublishTimestampMs = null;
    _updateCalibration(CalibrationPhase.uncalibrated);
    _updateRuntime(PdrRuntimeState.idle);
  }

  @override
  Future<void> confirmAnchorByPin({
    required PdrLocalPoint floorPointM,
    PdrToFloorAxes axes = const PdrToFloorAxes.identity(),
  }) async {
    if (!_guiding) {
      return;
    }
    _pendingPinFloorM = floorPointM;
    _pendingPinPdrM = _session.position;
    _pendingAxes = axes;
    if (_session.headingReference == HeadingReference.magneticNorth) {
      // 자북 기준: 서버 north_alignment 오프셋을 Phase 3에서 주입한다. 지금은 0.
      _finalizeAnchor(rotationDeg: 0, source: AnchorSource.userPin);
    } else {
      // arbitrary corrected: 진행 방향 보정이 필수(§4).
      _updateCalibration(CalibrationPhase.awaitingHeading);
    }
  }

  @override
  Future<void> confirmAnchorByFloorDirection({
    required PdrLocalPoint floorDirection,
  }) async {
    if (!_guiding || _pendingPinFloorM == null) {
      return;
    }
    // 화면/floor 좌표의 방향을 자북 기준 PDR 동·북 frame으로 되돌린 뒤 비교한다.
    // axes가 반전되거나 회전된 층에서 floor 각도를 바로 빼면 90°/180° 오차가 난다.
    final pdrDirection = _pendingAxes.inverseApply(floorDirection);
    if (pdrDirection == null || pdrDirection.distance < 1e-12) return;
    final targetPdrHeadingDeg = pdrBearingForDirection(pdrDirection);
    final rotationDeg = normalizePdrRotation(
      targetPdrHeadingDeg - _session.walkingHeadingDeg,
    );
    _finalizeAnchor(
      rotationDeg: rotationDeg,
      source: AnchorSource.manualHeadingCal,
    );
  }

  @override
  Future<void> changeFloor({required String floorId}) async {
    _floorId = floorId;
    _pendingPinFloorM = null;
    _pendingPinPdrM = null;
    _pendingAxes = const PdrToFloorAxes.identity();
    try {
      await _resetSessionForNewFloor();
    } on Object {
      _session.reset();
      _updateRuntime(
        PdrRuntimeState.degraded,
        warnings: const ['pedometerResetFailed'],
      );
    }
    _updateCalibration(CalibrationPhase.awaitingPin);
  }

  // ── 앱 lifecycle (앱 셸이 호출) ──

  /// 앱이 background로 가면 tracking pause.
  Future<void> onAppBackgrounded() async {
    if (!_guiding || _backgrounded) {
      return;
    }
    _backgrounded = true;
    _session.pause(atMs: _session.lastMotionAtMs ?? _nowMs());
    try {
      await _source.stop();
      _updateRuntime(PdrRuntimeState.paused);
    } on Object {
      _updateRuntime(
        PdrRuntimeState.degraded,
        warnings: const ['sensorStopFailed'],
      );
    }
  }

  /// 앱이 foreground로 돌아오면 tracking resume.
  Future<void> onAppForegrounded() async {
    if (!_guiding || !_backgrounded) {
      return;
    }
    try {
      await _source.start();
      _session.resume(atMs: _session.lastMotionAtMs ?? _nowMs());
      _backgrounded = false;
      _updateRuntime(PdrRuntimeState.starting);
    } on Object {
      _updateRuntime(
        PdrRuntimeState.degraded,
        warnings: const ['sensorResumeFailed'],
      );
    }
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _sessionSub.cancel();
    _session.dispose();
    await _source.dispose();
    await _snapshots.close();
    await _headingObservations.close();
    await _calibration.close();
    await _runtimeStatuses.close();
  }

  // ── 내부 ──

  void _onNativeEvent(NativePdrEvent e) {
    if (_runtimeStatus.state == PdrRuntimeState.starting) {
      _updateRuntime(PdrRuntimeState.running);
    }
    // 순서 유지: heading → accel peak → pedometer (연구 엔진과 동일).
    final heading = e.heading;
    if (heading != null) {
      _session.onHeading(heading);
      _publishHeadingObservation(heading.motionTimestampMs);
    }
    final accelPeak = e.accelPeak;
    if (accelPeak != null) {
      _session.onAccelPeak(accelPeak);
    }
    final pedometer = e.pedometer;
    if (pedometer != null) {
      _session.onPedometerBatch(pedometer);
    }
  }

  void _publishHeadingObservation(int motionTimestampMs) {
    final measured = _session.deviceHeadingDeg >= 0
        ? _session.deviceHeadingDeg
        : _session.fusedHeadingDeg;
    final observation = PdrHeadingObservation(
      measuredBearingDeg: normalizePdrBearing(measured),
      walkingBearingDeg: normalizePdrBearing(_session.walkingHeadingDeg),
      stable: _session.headingStable,
      source: _session.headingSource,
      magneticAccuracy: _session.magneticAccuracy,
      motionTimestampMs: motionTimestampMs,
    );
    _currentHeadingObservation = observation;

    final last = _lastHeadingPublishTimestampMs;
    if (last != null &&
        motionTimestampMs >= last &&
        motionTimestampMs - last < 50) {
      return;
    }
    _lastHeadingPublishTimestampMs = motionTimestampMs;
    if (!_headingObservations.isClosed) {
      _headingObservations.add(observation);
    }
  }

  void _onSourceError(Object error, [StackTrace? stackTrace]) {
    _updateRuntime(
      PdrRuntimeState.degraded,
      warnings: const ['sensorStreamError'],
    );
  }

  void _onSnapshot(PdrSnapshot snapshot) {
    final output = _withRuntimeQuality(snapshot);
    _current = output;
    if (!_snapshots.isClosed) {
      _snapshots.add(output);
    }
  }

  PdrSnapshot _withRuntimeQuality(PdrSnapshot snapshot) {
    if (_runtimeStatus.state != PdrRuntimeState.degraded) {
      return snapshot;
    }
    final warnings = <String>{
      ...snapshot.quality.warnings,
      ..._runtimeStatus.warnings,
    }.toList(growable: false);
    return PdrSnapshot(
      position: snapshot.position,
      path: snapshot.path,
      steps: snapshot.steps,
      distanceM: snapshot.distanceM,
      walkingHeadingDeg: snapshot.walkingHeadingDeg,
      hasHeading: snapshot.hasHeading,
      preview: snapshot.preview,
      quality: PdrQuality(
        state: PdrQualityState.degraded,
        warnings: warnings,
        features: snapshot.quality.features,
      ),
    );
  }

  Future<void> _resetSessionForNewFloor() async {
    final newSessionId = await _source.resetPedometer();
    _session.reset(newStepSessionId: newSessionId);
  }

  void _finalizeAnchor({
    required double rotationDeg,
    required AnchorSource source,
  }) {
    final pinFloor = _pendingPinFloorM;
    final pinPdr = _pendingPinPdrM;
    if (pinFloor == null || pinPdr == null) {
      return;
    }
    // anchorLocalM = pinFloor - axes·R(rotationDeg)·pinPdr.
    // PDR는 +east/+north지만 floor local_m은 +y가 남쪽일 수 있으므로, anchor
    // 확정에도 렌더링과 같은 축 변환을 적용해야 한다.
    final mappedPinPdr = _pendingAxes.apply(
      rotatePdrBearing(pinPdr, rotationDeg),
    );
    final anchorLocalM = PdrLocalPoint(
      pinFloor.eastM - mappedPinPdr.eastM,
      pinFloor.northM - mappedPinPdr.northM,
    );

    final reference = _session.headingReference;
    final anchor = PdrAnchor(
      floorId: _floorId ?? '',
      anchorLocalM: anchorLocalM,
      rotationDeg: rotationDeg,
      headingReference: reference,
      requiresManualRotationCalibration:
          reference != HeadingReference.magneticNorth,
      source: source,
      confidence: 1,
      axes: _pendingAxes,
    );
    _pendingPinFloorM = null;
    _pendingPinPdrM = null;
    _pendingAxes = const PdrToFloorAxes.identity();
    _updateCalibration(CalibrationPhase.calibrated, anchor: anchor);
  }

  void _updateCalibration(CalibrationPhase phase, {PdrAnchor? anchor}) {
    final reference = _session.headingReference;
    _calib = CalibrationStatus(
      phase: phase,
      headingReference: reference,
      requiresManualRotationCalibration:
          reference != HeadingReference.magneticNorth,
      anchor: anchor,
    );
    if (!_calibration.isClosed) {
      _calibration.add(_calib);
    }
  }

  void _updateRuntime(
    PdrRuntimeState state, {
    List<String> warnings = const [],
  }) {
    _runtimeStatus = PdrRuntimeStatus(
      state: state,
      warnings: List.unmodifiable(warnings),
    );
    if (!_runtimeStatuses.isClosed) {
      _runtimeStatuses.add(_runtimeStatus);
    }
  }
}
