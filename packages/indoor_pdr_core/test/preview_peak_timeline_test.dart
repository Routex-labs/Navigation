import 'package:indoor_pdr_core/indoor_pdr_core.dart';
// AccelPreviewTrack은 공개 API가 아니라 src에서 직접 가져온다.
import 'package:indoor_pdr_core/src/application/accel_preview_track.dart';
import 'package:test/test.dart';

/// 상태형 preview(4번 작업)가 "확정 배치 시간창까지의 주황 걸음"만 소비하려면,
/// 코어가 (a) 실제 반영된 peak의 시각을 path와 정렬해 주고 (b) 확정 배치를
/// 식별 가능하게 내보내야 한다. 이 파일은 그 계약을 고정한다.
///
/// 네이티브 `stepPeakTimes` 원본을 그대로 쓰면 안 된다는 점이 핵심이다.
/// AccelPreviewTrack이 간격·cadence·lead cap으로 버린 peak는 주황 경로에
/// 점을 만들지 않으므로, 그 원본으로 소비 위치를 계산하면 어긋난다.
void main() {
  group('AccelPreviewTrack.acceptedPeakTimesMs', () {
    ({AccelPreviewTrack track, int lastPeakMs}) feed({
      required int peakCount,
      required int confirmedSteps,
      required double confirmedDistanceM,
      int maxPoints = 800,
      int stepMs = 530,
    }) {
      final track = AccelPreviewTrack(maxPoints: maxPoints);
      var peakMs = 1000;
      for (var i = 1; i <= peakCount; i += 1) {
        peakMs += stepMs;
        track.applyRealtimePeaks(
          AccelPeakEvent(count: i, latestPeakMs: peakMs),
          tracking: true,
          hasHeading: true,
          effectiveStrideMeters: 0.75,
          fallbackStrideMeters: 0.75,
          confirmedSteps: confirmedSteps,
          confirmedDistanceM: confirmedDistanceM,
          pedometerCadenceHz: 1.9,
          headingAt: (_) => null,
          fallbackHeadingDeg: 0,
        );
      }
      return (track: track, lastPeakMs: peakMs);
    }

    test('path와 길이가 같고 원점만 null이다', () {
      final track = feed(
        peakCount: 8,
        confirmedSteps: 100,
        confirmedDistanceM: 100,
      ).track;

      // 첫 peak는 카운터 baseline이라 걸음이 되지 않는다(peakCount - 1).
      expect(track.steps, 7);
      expect(track.acceptedPeakTimesMs.length, track.path.length);
      expect(track.acceptedPeakTimesMs.first, isNull);
      expect(track.acceptedPeakTimesMs.skip(1), everyElement(isNotNull));
      // 시각은 단조 증가해야 한다. 뒤집히면 확정 소비가 엉뚱한 지점을 자른다.
      final times = track.acceptedPeakTimesMs.skip(1).cast<int>().toList();
      for (var i = 1; i < times.length; i += 1) {
        expect(times[i], greaterThan(times[i - 1]));
      }
    });

    test('거부된 peak는 경로에도 시각 배열에도 남지 않는다', () {
      // confirmed 0 → maxInitialStepLead(30)에서 멈춘다. 40개를 먹여도 30걸음.
      final track = feed(
        peakCount: 40,
        confirmedSteps: 0,
        confirmedDistanceM: 0,
      ).track;

      expect(track.rejectReasons[AccelPreviewTrack.stepLeadCap], greaterThan(0));
      expect(track.steps, AccelPreviewTrack.maxInitialStepLead);
      // 핵심: 거부분이 시각 배열에 새지 않는다.
      expect(track.acceptedPeakTimesMs.length, track.path.length);
      expect(track.acceptedPeakTimesMs.length, track.steps + 1);
    });

    test('delta > 1이면 같은 시각을 반복 저장해 인덱스 정렬을 지킨다', () {
      final track = AccelPreviewTrack();
      void peak(int count, int peakMs) => track.applyRealtimePeaks(
        AccelPeakEvent(count: count, latestPeakMs: peakMs),
        tracking: true,
        hasHeading: true,
        effectiveStrideMeters: 0.75,
        fallbackStrideMeters: 0.75,
        confirmedSteps: 100,
        confirmedDistanceM: 100,
        pedometerCadenceHz: 1.9,
        headingAt: (_) => null,
        fallbackHeadingDeg: 0,
      );

      peak(1, 1000); // baseline
      peak(2, 1530); // delta 1
      peak(5, 3120); // delta 3 — 한 이벤트가 peak 3개를 싣고 왔다

      expect(track.steps, 4);
      expect(track.acceptedPeakTimesMs.length, track.path.length);
      // 코어가 아는 시각은 latestPeakMs 하나뿐이라 3개가 같은 값을 갖는다.
      expect(track.acceptedPeakTimesMs, [null, 1530, 3120, 3120, 3120]);
    });

    test('path가 trim되면 시각 배열도 같은 만큼 잘린다', () {
      final result = feed(
        peakCount: 20,
        confirmedSteps: 100,
        confirmedDistanceM: 100,
        maxPoints: 6,
      );
      final track = result.track;

      expect(track.path.length, 6);
      expect(track.acceptedPeakTimesMs.length, 6);
      // 앞이 잘렸으므로 원점 null은 사라지고 마지막은 최신 peak 시각이다.
      expect(track.acceptedPeakTimesMs.last, result.lastPeakMs);
      expect(track.acceptedPeakTimesMs, everyElement(isNotNull));
    });

    test('reset은 원점 상태로 되돌린다', () {
      final track = feed(
        peakCount: 5,
        confirmedSteps: 100,
        confirmedDistanceM: 100,
      ).track;
      track.reset();

      expect(track.acceptedPeakTimesMs, [null]);
      expect(track.acceptedPeakTimesMs.length, track.path.length);
    });
  });

  group('PdrSnapshot.lastAppliedBatch', () {
    PdrSession seededSession() {
      final s = PdrSession(config: PdrSessionConfig(nowMs: () => 0));
      s.onHeading(
        const HeadingEvent(
          motionTimestampMs: 1000,
          fusedHeadingDeg: 0,
          headingStable: true,
          headingSource: 'device_motion/xMagneticNorthZVertical',
        ),
      );
      return s;
    }

    test('배치를 반영하기 전에는 null이다', () {
      expect(seededSession().snapshot.lastAppliedBatch, isNull);
    });

    test('반영된 배치의 시간창·걸음·거리를 그대로 싣는다', () {
      final s = seededSession();
      s.onPedometerBatch(
        const PedometerBatchEvent(
          steps: 10,
          stepSessionId: 1,
          sessionStartMs: 900,
          timestampMs: 2000,
          distanceM: 7.0,
          distanceAvailable: true,
          stepPeakTimes: [1100, 1300, 1500, 1700, 1900],
        ),
      );

      final batch = s.snapshot.lastAppliedBatch;
      expect(batch, isNotNull);
      expect(batch!.appliedSteps, 10);
      expect(batch.appliedDistanceM, closeTo(7.0, 1e-9));
      expect(batch.spanStartMs, 900);
      expect(batch.spanEndMs, 2000);
    });

    test('batchId가 배치마다 증가해 중복 소비를 막을 수 있다', () {
      final s = seededSession();
      s.onPedometerBatch(
        const PedometerBatchEvent(
          steps: 10,
          stepSessionId: 1,
          sessionStartMs: 900,
          timestampMs: 2000,
          distanceM: 7.0,
          distanceAvailable: true,
          stepPeakTimes: [1100, 1500, 1900],
        ),
      );
      final first = s.snapshot.lastAppliedBatch!.batchId;

      // snapshot은 motion 이벤트마다 다시 방출된다. 같은 배치를 두 번 소비하면
      // 안 되므로 batchId가 그대로여야 한다.
      s.onHeading(
        const HeadingEvent(
          motionTimestampMs: 2200,
          fusedHeadingDeg: 5,
          headingStable: true,
          headingSource: 'device_motion/xMagneticNorthZVertical',
        ),
      );
      expect(s.snapshot.lastAppliedBatch!.batchId, first);

      s.onPedometerBatch(
        const PedometerBatchEvent(
          steps: 18,
          stepSessionId: 1,
          sessionStartMs: 900,
          timestampMs: 4000,
          distanceM: 12.6,
          distanceAvailable: true,
          stepPeakTimes: [2300, 2900, 3500],
        ),
      );
      final second = s.snapshot.lastAppliedBatch!;
      expect(second.batchId, greaterThan(first));
      expect(second.appliedSteps, 8);
    });

    test('reset하면 batchId가 1로 되돌아가므로 lastAppliedBatch도 비운다', () {
      final s = seededSession();
      s.onPedometerBatch(
        const PedometerBatchEvent(
          steps: 10,
          stepSessionId: 1,
          sessionStartMs: 900,
          timestampMs: 2000,
          distanceM: 7.0,
          distanceAvailable: true,
          stepPeakTimes: [1100, 1500, 1900],
        ),
      );
      expect(s.snapshot.lastAppliedBatch, isNotNull);

      s.reset(newStepSessionId: 2);
      // 남겨두면 새 세션의 batchId=1을 "이미 소비함"으로 오판한다.
      expect(s.snapshot.lastAppliedBatch, isNull);
    });
  });

  group('확정 시간창 기준 preview 소비', () {
    test('spanEndMs 이하 peak만 소비하고 미래 peak는 남는다', () {
      final s = PdrSession(config: PdrSessionConfig(nowMs: () => 0));
      s.onHeading(
        const HeadingEvent(
          motionTimestampMs: 1000,
          fusedHeadingDeg: 0,
          headingStable: true,
          headingSource: 'device_motion/xMagneticNorthZVertical',
        ),
      );
      // 첫 peak(1000)는 baseline이라 걸음이 되지 않는다. 이후 6개가 주황 걸음.
      var count = 0;
      for (final peakMs in [1000, 1500, 2000, 2500, 3000, 3500, 4000]) {
        count += 1;
        s.onAccelPeak(AccelPeakEvent(count: count, latestPeakMs: peakMs));
      }
      // 초록 배치는 2600까지만 덮는다.
      s.onPedometerBatch(
        const PedometerBatchEvent(
          steps: 3,
          stepSessionId: 1,
          sessionStartMs: 900,
          timestampMs: 2600,
          distanceM: 2.1,
          distanceAvailable: true,
          stepPeakTimes: [1500, 2000, 2500],
        ),
      );

      final snapshot = s.snapshot;
      final spanEndMs = snapshot.lastAppliedBatch!.spanEndMs!;
      final times = snapshot.preview.acceptedPeakTimesMs;
      expect(times.length, snapshot.preview.path.length);

      final consumed = times
          .where((t) => t != null && t <= spanEndMs)
          .length;
      final pending = times
          .where((t) => t != null && t > spanEndMs)
          .length;
      // 확정 시간창 안의 주황 걸음 3개만 소비되고, 이후 3개는 선행분으로 남는다.
      expect(consumed, 3);
      expect(pending, 3);
      // 초록 걸음 수(3)가 아니라 시간창이 기준이라는 점을 함께 고정한다.
      expect(snapshot.preview.steps, 6);
      expect(snapshot.steps, 3);
    });
  });
}
