import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:test/test.dart';

/// synthetic typed event로 PdrSession의 핵심 계약을 검증한다.
void main() {
  PdrSession newSession() =>
      PdrSession(config: PdrSessionConfig(nowMs: () => 0));

  group('confirmed(초록) 경로', () {
    test('heading 이후 첫 배치는 apple distance로 보폭을 잡고 누적한다', () {
      final s = newSession();
      // 정북(0도)을 바라보는 heading seed.
      s.onHeading(const HeadingEvent(
        motionTimestampMs: 1000,
        fusedHeadingDeg: 0,
        headingStable: true,
        headingSource: 'device_motion/xMagneticNorthZVertical',
      ));
      expect(s.hasFusedHeading, isTrue);

      // 10걸음 / 7.0m → 보폭 0.70m. 첫 배치는 cumulative==delta.
      s.onPedometerBatch(const PedometerBatchEvent(
        steps: 10,
        stepSessionId: 1,
        sessionStartMs: 900,
        timestampMs: 2000,
        distanceM: 7.0,
        distanceAvailable: true,
        stepPeakTimes: [1100, 1300, 1500, 1700, 1900],
      ));

      expect(s.steps, 10);
      expect(s.distanceM, closeTo(7.0, 1e-9));
      // walkingHeading 0도 → 전부 +north.
      expect(s.position.northM, closeTo(7.0, 1e-9));
      expect(s.position.eastM, closeTo(0.0, 1e-9));
    });

    test('heading이 없으면 배치를 경로에 반영하지 않는다', () {
      final s = newSession();
      s.onPedometerBatch(const PedometerBatchEvent(
        steps: 10,
        stepSessionId: 1,
        sessionStartMs: 900,
        timestampMs: 2000,
        distanceM: 7.0,
        distanceAvailable: true,
        stepPeakTimes: [1100, 1500, 1900],
      ));
      expect(s.steps, 0);
      expect(s.distanceM, 0);
    });
  });

  group('preview(주황) 경로', () {
    test('accel peak는 preview에만 반영되고 confirmed에는 영향이 없다', () {
      final s = newSession();
      s.onHeading(const HeadingEvent(
        motionTimestampMs: 1000,
        fusedHeadingDeg: 0,
        headingStable: true,
        headingSource: 'device_motion/xMagneticNorthZVertical',
      ));
      // baseline peak(첫 신호) → 미반영, 이후 delta만 반영.
      s.onAccelPeak(const AccelPeakEvent(count: 0, latestPeakMs: 1000));
      s.onAccelPeak(const AccelPeakEvent(count: 1, latestPeakMs: 1500));
      s.onAccelPeak(const AccelPeakEvent(count: 2, latestPeakMs: 2000));

      expect(s.snapshot.preview.steps, greaterThan(0));
      expect(s.steps, 0, reason: 'confirmed는 pedometer로만 늘어난다');
    });
  });

  test('snapshots 스트림은 배치 반영 시 이벤트를 낸다', () async {
    final s = newSession();
    final future = s.snapshots.first;
    s.onHeading(const HeadingEvent(
      motionTimestampMs: 1000,
      fusedHeadingDeg: 0,
      headingStable: true,
      headingSource: 'device_motion/xMagneticNorthZVertical',
    ));
    s.onPedometerBatch(const PedometerBatchEvent(
      steps: 4,
      stepSessionId: 1,
      sessionStartMs: 900,
      timestampMs: 2000,
      distanceM: 2.8,
      distanceAvailable: true,
      stepPeakTimes: [1200, 1600],
    ));
    final snap = await future;
    expect(snap.steps, 4);
    s.dispose();
  });
}
