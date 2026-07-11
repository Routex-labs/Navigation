import 'dart:convert';
import 'dart:io';

import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:test/test.dart';

/// 실기기 세션 export에서 재구성한 CMPedometer 입력을 재생해 confirmed(초록)
/// stride/거리 로직을 회귀 검증한다.
///
/// 재구성 충실도는 export가 무엇을 남겼는지에 달려 있다:
///   - `session_1349`: 첫 기록 배치가 cumulativeSteps==deltaSteps라 내부 상태 손실이
///     없다 → stride·delta·거리를 **정확히**(1e-6, 0.1%) 재현할 수 있다.
///   - `session_1355`: 세션이 tracking 시작 전부터 켜져 있어, deltaSteps>0로 기록되기
///     전의 pedometer 이벤트(누적 5걸음 + 그 distance-baseline)가 export에서 빠졌다.
///     첫 배치가 cumulative=7 / delta=2로, 이 손실은 재구성이 불가능하다. 그래서
///     coarse(거리 ±5%) 검증만 한다. 정밀 재현은 향후 full event trace로 확보한다
///     (§ Phase 1 테스트 ③).
void main() {
  Map<String, dynamic> loadFixture(String name) =>
      jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
          as Map<String, dynamic>;

  /// 배치를 tracking ON으로 재생하고 배치별 적용 정보를 batchId로 모은다.
  Map<int, AppliedBatchInfo> replay(Map<String, dynamic> fx) {
    final session = PdrSession(config: PdrSessionConfig(nowMs: () => 0));
    final applied = <int, AppliedBatchInfo>{};
    session.onBatchApplied = (info) => applied[info.batchId] = info;

    session.onHeading(HeadingEvent(
      motionTimestampMs: fx['seedHeadingMs'] as int,
      fusedHeadingDeg: 0,
      headingStable: true,
      headingSource: 'device_motion/xMagneticNorthZVertical',
    ));

    for (final raw in fx['batches'] as List) {
      final b = raw as Map<String, dynamic>;
      session.onPedometerBatch(PedometerBatchEvent(
        steps: b['steps'] as int,
        stepSessionId: b['stepSessionId'] as int?,
        sessionStartMs: b['sessionStartMs'] as int?,
        timestampMs: (b['timestampMs'] as num?)?.toDouble(),
        distanceM: (b['distanceM'] as num?)?.toDouble(),
        distanceAvailable: b['distanceAvailable'] as bool?,
        cadenceHz: (b['cadenceHz'] as num?)?.toDouble(),
        paceSecPerM: (b['paceSecPerM'] as num?)?.toDouble(),
        cadenceAvailable: b['cadenceAvailable'] as bool?,
        paceAvailable: b['paceAvailable'] as bool?,
        stepPeakTimes: (b['stepPeakTimes'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList(),
      ));
    }
    session.dispose();
    return applied;
  }

  /// 엔진이 기록한 appliedSteps로 confirmed 거리·걸음수를 재구성한다.
  ({int steps, double distanceM}) reconstructConfirmed(
    Map<String, dynamic> fx,
    Map<int, AppliedBatchInfo> applied,
  ) {
    var steps = 0;
    var distance = 0.0;
    for (final raw in fx['batches'] as List) {
      final b = raw as Map<String, dynamic>;
      final appliedSteps = b['expectedAppliedSteps'] as int;
      final a = applied[b['expectedBatchId'] as int]!;
      steps += appliedSteps;
      distance += a.stepDistanceMeters * appliedSteps;
    }
    return (steps: steps, distanceM: distance);
  }

  // ── 정확 재현: session_1349 ──
  group('session_1349 (정확 재현)', () {
    final fx = loadFixture('session_1349');
    final batches = (fx['batches'] as List).cast<Map<String, dynamic>>();

    test('배치별 deltaSteps가 엔진과 정확히 일치한다', () {
      final applied = replay(fx);
      for (final b in batches) {
        final a = applied[b['expectedBatchId'] as int];
        expect(a, isNotNull, reason: 'batch ${b['expectedBatchId']} 미적용');
        expect(a!.deltaSteps, b['expectedDeltaSteps'] as int);
      }
    });

    test('배치별 stepDistanceM이 엔진과 1e-6 이내로 일치한다', () {
      final applied = replay(fx);
      for (final b in batches) {
        final expected = (b['expectedStepDistanceM'] as num?)?.toDouble();
        if (expected == null) continue;
        final a = applied[b['expectedBatchId'] as int]!;
        expect(a.stepDistanceMeters, closeTo(expected, 1e-6),
            reason: 'batch ${b['expectedBatchId']}');
      }
    });

    test('confirmed 걸음수·거리가 엔진과 ±0.1% 이내로 일치한다', () {
      final r = reconstructConfirmed(fx, replay(fx));
      expect(r.steps, fx['expectedConfirmedSteps'] as int);
      final expected = (fx['expectedConfirmedDistanceM'] as num).toDouble();
      expect(r.distanceM, closeTo(expected, expected * 0.001),
          reason: '재구성 ${r.distanceM.toStringAsFixed(4)}m vs '
              '엔진 ${expected.toStringAsFixed(4)}m');
    });
  });

  // ── coarse 재현: session_1355 (pre-tracking 이벤트 손실) ──
  group('session_1355 (coarse 재현)', () {
    final fx = loadFixture('session_1355');

    test('confirmed 거리가 엔진과 ±5% 이내로 재구성된다', () {
      final r = reconstructConfirmed(fx, replay(fx));
      final expected = (fx['expectedConfirmedDistanceM'] as num).toDouble();
      expect(r.distanceM, closeTo(expected, expected * 0.05),
          reason: '재구성 ${r.distanceM.toStringAsFixed(4)}m vs '
              '엔진 ${expected.toStringAsFixed(4)}m '
              '(pre-tracking 이벤트 손실로 첫 배치 baseline 재구성 불가)');
    });

    test('appliedSteps 합이 confirmed 걸음수와 일치한다', () {
      // appliedSteps는 export 기록값이라 항상 일치. 재생이 배치를 빠짐없이
      // 처리했는지(모든 batchId 적용)까지 확인한다.
      final applied = replay(fx);
      final batches = (fx['batches'] as List).cast<Map<String, dynamic>>();
      for (final b in batches) {
        expect(applied.containsKey(b['expectedBatchId'] as int), isTrue);
      }
      final r = reconstructConfirmed(fx, applied);
      expect(r.steps, fx['expectedConfirmedSteps'] as int);
    });
  });
}
