import 'dart:math' as math;

import '../domain/angle_utils.dart';
import '../domain/heading_sample.dart';

/// step batch가 늦게 도착했을 때 해당 시점의 heading을 되찾기 위한 history.
///
/// 연구 앱 `heading_tracker.dart`에서 옮겼다. export 전용 메서드는 제거했다.
class HeadingHistory {
  HeadingHistory({this.maxAgeMs = 20000});

  final int maxAgeMs;
  final List<HeadingSample> _samples = [];

  void add(HeadingSample sample) {
    _samples.add(sample);
    prune(sample.ms);
  }

  HeadingSample? at(int ms) {
    for (var i = _samples.length - 1; i >= 0; i -= 1) {
      if (_samples[i].ms <= ms) {
        return _samples[i];
      }
    }
    return _samples.isEmpty ? null : _samples.first;
  }

  void prune(int nowMs) {
    var drop = 0;
    while (drop < _samples.length && _samples[drop].ms < nowMs - maxAgeMs) {
      drop += 1;
    }
    if (drop > 0) {
      _samples.removeRange(0, drop);
    }
  }

  void clear() => _samples.clear();
}

/// raw heading window로 팔 흔들림인지 실제 회전인지 구분한다.
class SwingDetector {
  final List<({int ms, double deg})> _window = [];

  bool swinging = false;
  double oscillationDeg = 0;

  double get netDeg {
    if (_window.length < 2) {
      return 0;
    }
    return shortestDeltaDegrees(_window.last.deg - _window.first.deg).abs();
  }

  void update(int nowMs, double rawDeg) {
    _window.add((ms: nowMs, deg: rawDeg));
    var drop = 0;
    while (drop < _window.length && _window[drop].ms < nowMs - 1500) {
      drop += 1;
    }
    if (drop > 0) {
      _window.removeRange(0, drop);
    }
    if (_window.length < 6) {
      swinging = false;
      oscillationDeg = 0;
      return;
    }

    var sumSin = 0.0;
    var sumCos = 0.0;
    for (final sample in _window) {
      final r = sample.deg * math.pi / 180;
      sumSin += math.sin(r);
      sumCos += math.cos(r);
    }
    final meanDeg = math.atan2(sumSin, sumCos) * 180 / math.pi;
    var minD = 0.0;
    var maxD = 0.0;
    for (final sample in _window) {
      final d = shortestDeltaDegrees(sample.deg - meanDeg);
      minD = math.min(minD, d);
      maxD = math.max(maxD, d);
    }
    final peakToPeak = maxD - minD;
    oscillationDeg = math.max(0, peakToPeak - netDeg);
    swinging = swinging ? oscillationDeg > 18 : oscillationDeg > 30;
  }

  void reset() {
    _window.clear();
    swinging = false;
    oscillationDeg = 0;
  }
}

/// 자북 기준 heading이 "자리를 잡았는지"를 판정한다.
///
/// native가 주는 `headingStable`은 기기 기울기(top축의 수평 성분)만 본다. 즉
/// 폰을 똑바로 들고만 있으면 세션 시작 직후에도 true다. 그래서 CoreMotion의
/// 자북 reference가 아직 수렴하지 않았거나 사용자가 몸을 돌리는 중이어도
/// "안정"으로 보고돼, 그 사이에 놓인 첫 걸음들이 틀어진 방향으로 눕는다
/// (실측: 첫 4걸음이 복도 방향 대비 17.6° 어긋남).
///
/// 여기서는 값이 실제로 **가만히 있는지**를 본다. 최근 [windowMs] 동안의
/// heading이 원형 평균에서 [maxDeviationDeg] 안에 머물고, 그 창이 최소
/// [minSpanMs]만큼 채워졌을 때 수렴으로 본다. 원인이 센서 수렴이든 사용자
/// 회전이든 "지금 방향을 믿어도 되는가"라는 같은 질문에 답한다.
class HeadingConvergenceTracker {
  HeadingConvergenceTracker({
    this.windowMs = 2000,
    this.minSpanMs = 1200,
    this.maxDeviationDeg = 12.0,
    this.minSamples = 8,
  });

  final int windowMs;
  final int minSpanMs;
  final double maxDeviationDeg;
  final int minSamples;

  final List<({int ms, double deg})> _window = [];

  bool converged = false;

  /// 수렴 판정에 쓴 최근 창의 최대 편차(도). 진단용.
  double spreadDeg = 0;

  void update(int nowMs, double rawDeg) {
    _window.add((ms: nowMs, deg: rawDeg));
    var drop = 0;
    while (drop < _window.length && _window[drop].ms < nowMs - windowMs) {
      drop += 1;
    }
    if (drop > 0) _window.removeRange(0, drop);

    if (_window.length < minSamples ||
        _window.last.ms - _window.first.ms < minSpanMs) {
      // 아직 판단할 만큼 안 모였다. 한 번 수렴했다면 그 상태를 유지한다 —
      // 샘플이 잠깐 끊겼다고 다시 "수렴 안 됨"으로 돌리면 게이트가 깜빡인다.
      return;
    }

    var sumSin = 0.0;
    var sumCos = 0.0;
    for (final sample in _window) {
      final r = sample.deg * math.pi / 180;
      sumSin += math.sin(r);
      sumCos += math.cos(r);
    }
    final meanDeg = math.atan2(sumSin, sumCos) * 180 / math.pi;

    var maxDeviation = 0.0;
    for (final sample in _window) {
      final d = shortestDeltaDegrees(sample.deg - meanDeg).abs();
      if (d > maxDeviation) maxDeviation = d;
    }
    spreadDeg = maxDeviation;
    if (maxDeviation <= maxDeviationDeg) {
      converged = true;
    }
  }

  void reset() {
    _window.clear();
    converged = false;
    spreadDeg = 0;
  }
}

/// 팔 흔들림에서 추정한 보행축을 fused heading에 천천히 반영한다.
class WalkOffsetEstimator {
  static const double confidenceThreshold = 0.35;
  static const double _tauSeconds = 2.5;
  static const double _decayTauSeconds = 12.0;
  static const double _maxDeg = 60.0;
  static const double turnGateNetDeg = 20.0;

  double offsetDeg = 0;
  bool active = false;
  int turnHoldUntilMs = 0;

  void update({
    required int nowMs,
    required double dtSeconds,
    required bool swinging,
    required double swingNetDeg,
    required double walkDirDeg,
    required double walkDirConfidence,
    required double fusedHeadingDeg,
  }) {
    if (swingNetDeg > turnGateNetDeg) {
      turnHoldUntilMs = nowMs + 1500;
    }

    if (!swinging) {
      offsetDeg *= math.exp(-dtSeconds / _decayTauSeconds);
      active = false;
      return;
    }
    if (nowMs < turnHoldUntilMs || walkDirConfidence < confidenceThreshold) {
      active = false;
      return;
    }

    final current = normalizeDegrees(fusedHeadingDeg + offsetDeg);
    final branchA = walkDirDeg;
    final branchB = normalizeDegrees(walkDirDeg + 180);
    final target =
        shortestDeltaDegrees(branchA - current).abs() <=
            shortestDeltaDegrees(branchB - current).abs()
        ? branchA
        : branchB;
    final desiredOffset = shortestDeltaDegrees(target - fusedHeadingDeg);
    final alpha = 1 - math.exp(-dtSeconds / _tauSeconds);
    final updated = shortestDeltaDegrees(
      offsetDeg + shortestDeltaDegrees(desiredOffset - offsetDeg) * alpha,
    );
    offsetDeg = updated.clamp(-_maxDeg, _maxDeg);
    active = true;
  }

  void reset() {
    offsetDeg = 0;
    active = false;
    turnHoldUntilMs = 0;
  }
}
