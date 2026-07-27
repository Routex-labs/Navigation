import 'package:indoor_pdr_core/indoor_pdr_core.dart';

/// native EventChannel의 raw `Map`을 코어의 typed 이벤트로 변환하는 경계.
///
/// 연구 앱 `native_motion_event.dart`의 파싱 계층을 옮겨, raw `Map<dynamic,dynamic>`이
/// 코어까지 흘러들지 않게 한다(설계 제약 3). native "motion" 이벤트는 heading과 accel
/// peak를 함께 싣고, "pedometer" 이벤트는 CMPedometer 필드를, "snapshot"은 둘 다 싣는다.
class NativePdrEvent {
  const NativePdrEvent({
    required this.source,
    required this.kind,
    required this.stepSessionId,
    required this.heading,
    required this.accelPeak,
    required this.pedometer,
  });

  final String? source;
  final String? kind;
  final int? stepSessionId;
  final HeadingEvent? heading;
  final AccelPeakEvent? accelPeak;
  final PedometerBatchEvent? pedometer;

  /// raw native 이벤트를 파싱한다. 형식이 아니거나 필드가 없으면 null.
  static NativePdrEvent? tryParse(Object? value) {
    if (value is! Map) {
      return null;
    }
    return NativePdrEvent(
      source: value['source']?.toString(),
      kind: value['kind']?.toString(),
      stepSessionId: (value['stepSessionId'] as num?)?.toInt(),
      heading: _parseHeading(value),
      accelPeak: _parseAccelPeak(value),
      pedometer: _parsePedometer(value),
    );
  }

  static HeadingEvent? _parseHeading(Map raw) {
    final fused = _double(raw, 'fusedHeadingDeg');
    final motionMs = (raw['motionTimestamp'] as num?)?.round();
    if (fused == null || motionMs == null) {
      return null;
    }
    return HeadingEvent(
      motionTimestampMs: motionMs,
      fusedHeadingDeg: fused,
      headingStable: raw['headingStable'] as bool?,
      deviceHeadingDeg: _double(raw, 'deviceHeadingDeg'),
      yawDeg: _double(raw, 'yawDeg'),
      gyroHeadingDeg: _double(raw, 'gyroHeadingDeg'),
      pitchDeg: _double(raw, 'pitchDeg'),
      rollDeg: _double(raw, 'rollDeg'),
      walkDirDeg: _double(raw, 'walkDirDeg'),
      walkDirConfidence: _double(raw, 'walkDirConfidence'),
      magneticAccuracy: raw['magneticAccuracy']?.toString(),
      magneticField: _double(raw, 'magneticField'),
      rotationHeadingAccuracyDeg: _double(raw, 'rotationHeadingAccuracyDeg'),
      headingSource: raw['headingSource']?.toString(),
    );
  }

  static AccelPeakEvent? _parseAccelPeak(Map raw) {
    final count = (raw['stepPeakCount'] as num?)?.toInt();
    if (count == null) {
      return null;
    }
    return AccelPeakEvent(
      count: count,
      latestPeakMs: (raw['latestStepPeakMs'] as num?)?.round(),
      motionTimestampMs: raw['motionTimestamp'] as num?,
    );
  }

  static PedometerBatchEvent? _parsePedometer(Map raw) {
    final steps = (raw['steps'] as num?)?.toInt();
    if (steps == null) {
      return null;
    }
    return PedometerBatchEvent(
      steps: steps,
      stepSessionId: (raw['stepSessionId'] as num?)?.toInt(),
      sessionStartMs: (raw['pedometerSessionStartMs'] as num?)?.round(),
      timestampMs: _double(raw, 'pedometerTimestamp'),
      deltaMs: _double(raw, 'pedometerDeltaMs'),
      distanceM: _double(raw, 'pedometerDistance'),
      distanceAvailable: raw['pedometerDistanceAvailable'] as bool?,
      cadenceHz: _double(raw, 'pedometerCadence'),
      paceSecPerM: _double(raw, 'pedometerPace'),
      cadenceAvailable: raw['pedometerCadenceAvailable'] as bool?,
      paceAvailable: raw['pedometerPaceAvailable'] as bool?,
      stepPeakTimes: (raw['stepPeakTimes'] as List?)
          ?.map((value) => (value as num).toDouble())
          .toList(),
      isAndroid: raw['source']?.toString() == 'android_sensor_manager',
      stepCountSource: raw['stepCountSource']?.toString(),
      authoritativeSteps: (raw['authoritativeSteps'] as num?)?.toInt(),
      stepCounterSteps: (raw['stepCounterSteps'] as num?)?.toInt(),
      stepCounterDelta: (raw['stepCounterDelta'] as num?)?.toInt(),
      counterLastEventAtMs: _double(raw, 'counterLastEventAtMs'),
      stepAccelAmplitudeMps2: _double(raw, 'stepAccelAmplitudeMps2'),
      roninSupported: raw['roninSupported'] as bool? ?? false,
      roninReady: raw['roninReady'] as bool? ?? false,
      roninModel: raw['roninModel']?.toString(),
      roninStatus: raw['roninStatus']?.toString(),
      roninSpeedMps: _double(raw, 'roninSpeedMps'),
      roninSpeedStdMps: _double(raw, 'roninSpeedStdMps'),
      roninCadenceHz: _double(raw, 'roninCadenceHz'),
      roninStrideMeters: _double(raw, 'roninStrideMeters'),
    );
  }

  static double? _double(Map raw, String key) => (raw[key] as num?)?.toDouble();
}
