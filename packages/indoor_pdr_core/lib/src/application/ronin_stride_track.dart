import '../domain/events.dart';
import '../domain/heading_sample.dart';
import '../domain/snapshot.dart';
import 'path_accumulator.dart';
import 'pedometer_batch_processor.dart';

/// RoNIN이 제안한 한 걸음 거리를 기존 confirmed step/heading에만 갈아 끼운다.
///
/// 모델이 준비되기 전에는 0.70m로 초록 경로와 같은 출발점을 유지한다. 후보가
/// 들어오면 배치 사이 급변을 20%로 제한한 뒤 EMA로 완화한다. 이 경로의 값은
/// confirmed 거리나 품질 판정에 역으로 섞이지 않는다.
class RoninStrideTrack {
  RoninStrideTrack({required int maxPoints})
    : _paths = PathAccumulator(maxPoints: maxPoints);

  static const double _fallbackStrideM = 0.70;
  static const double _minExperimentalStrideM = 0.20;
  static const double _maxExperimentalStrideM = 1.50;
  static const double _maxChangeFraction = 0.20;
  static const double _alpha = 0.35;

  final PathAccumulator _paths;

  bool supported = false;
  bool modelReady = false;
  int steps = 0;
  double distanceM = 0;
  double effectiveStrideM = _fallbackStrideM;
  double? rawStrideM;
  double? speedMps;
  double? speedStdMps;
  double? cadenceHz;
  String? model;
  String status = 'unsupported';

  bool observe(PedometerBatchEvent event) {
    final before = (
      supported,
      modelReady,
      rawStrideM,
      speedMps,
      speedStdMps,
      cadenceHz,
      model,
      status,
    );
    supported = supported || event.roninSupported;
    modelReady = event.roninReady;
    model = event.roninModel ?? model;
    status = event.roninStatus ?? status;
    speedMps = event.roninSpeedMps ?? speedMps;
    speedStdMps = event.roninSpeedStdMps ?? speedStdMps;
    cadenceHz = event.roninCadenceHz ?? cadenceHz;

    final candidate = event.roninStrideMeters;
    if (candidate != null &&
        candidate.isFinite &&
        candidate >= _minExperimentalStrideM &&
        candidate <= _maxExperimentalStrideM) {
      rawStrideM = candidate;
      final lower = effectiveStrideM * (1 - _maxChangeFraction);
      final upper = effectiveStrideM * (1 + _maxChangeFraction);
      final capped = candidate.clamp(lower, upper).toDouble();
      effectiveStrideM =
          (effectiveStrideM + (capped - effectiveStrideM) * _alpha)
              .clamp(_minExperimentalStrideM, _maxExperimentalStrideM)
              .toDouble();
    }
    final after = (
      supported,
      modelReady,
      rawStrideM,
      speedMps,
      speedStdMps,
      cadenceHz,
      model,
      status,
    );
    return before != after;
  }

  void apply(
    PedometerBatchApplication application, {
    required double currentWalkDeg,
    required double currentFusedDeg,
    required HeadingSample? Function(int ms) headingAt,
  }) {
    if (!supported || application.appliedSteps <= 0) return;
    final applied = _paths.applyPedometerBatch(
      count: application.appliedSteps,
      stepDistanceMeters: effectiveStrideM,
      currentWalkDeg: currentWalkDeg,
      currentFusedDeg: currentFusedDeg,
      headingAt: headingAt,
      spanStartMs: application.spanStartMs,
      spanEndMs: application.spanEndMs,
      peakTimes: application.peakTimes,
    );
    steps += applied;
    distanceM += effectiveStrideM * applied;
  }

  PdrRoninTrack get snapshot => PdrRoninTrack(
    supported: supported,
    modelReady: modelReady,
    position: _paths.correctedPosition,
    path: List.unmodifiable(_paths.corrected),
    steps: steps,
    distanceM: distanceM,
    effectiveStrideM: effectiveStrideM,
    model: model,
    status: status,
    rawStrideM: rawStrideM,
    speedMps: speedMps,
    speedStdMps: speedStdMps,
    cadenceHz: cadenceHz,
  );

  void reset() {
    _paths.reset();
    supported = false;
    modelReady = false;
    steps = 0;
    distanceM = 0;
    effectiveStrideM = _fallbackStrideM;
    rawStrideM = null;
    speedMps = null;
    speedStdMps = null;
    cadenceHz = null;
    model = null;
    status = 'unsupported';
  }
}
