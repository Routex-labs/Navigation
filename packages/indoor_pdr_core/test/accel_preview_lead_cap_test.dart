import 'package:indoor_pdr_core/indoor_pdr_core.dart';
// AccelPreviewTrack은 공개 API가 아니라 src에서 직접 가져온다.
import 'package:indoor_pdr_core/src/application/accel_preview_track.dart';
import 'package:test/test.dart';

/// preview가 confirmed보다 얼마나 앞서 있든 peak를 계속 먹이고, 몇 걸음에서
/// 멈추는지 본다. [confirmedSteps]를 고정해 lead cap만 검사한다.
({int steps, double distanceM, int leadRejects}) _feedPeaks({
  required int peakCount,
  required int confirmedSteps,
  required double confirmedDistanceM,
}) {
  final track = AccelPreviewTrack();
  var peakMs = 1000;
  for (var i = 1; i <= peakCount; i += 1) {
    // 실제 보행 케이던스(약 1.9Hz)와 같은 간격이라 interval gate에 걸리지 않는다.
    peakMs += 530;
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
  return (
    steps: track.steps,
    distanceM: track.distanceM,
    leadRejects: track.rejectReasons[AccelPreviewTrack.stepLeadCap] ?? 0,
  );
}

void main() {
  group('AccelPreviewTrack lead cap', () {
    test('confirmed가 들어온 뒤에는 confirmed + maxStepLead에서 멈춘다', () {
      // 회귀 케이스: 예전에는 cap이 reject를 기록만 하고 걸음을 그대로
      // 반영해서, preview가 confirmed를 무한히 앞질렀다. 실측 세션에서
      // stepLeadCap 133건이 찍혔는데도 preview는 confirmed(112)+12=124를 넘어
      // 163걸음까지 갔다.
      final result = _feedPeaks(
        peakCount: 200,
        confirmedSteps: 20,
        confirmedDistanceM: 1000,
      );

      expect(result.steps, 20 + AccelPreviewTrack.maxStepLead);
      expect(result.leadRejects, greaterThan(0));
    });

    test('confirmed가 아직 0이면 초기 허용치까지 앞서갈 수 있다', () {
      // 첫 CMPedometer batch가 늦게 오는 동안 preview가 12걸음에서 얼어붙지
      // 않도록 하는 기존 완화는 유지돼야 한다.
      final result = _feedPeaks(
        peakCount: 200,
        confirmedSteps: 0,
        confirmedDistanceM: 0,
      );

      expect(result.steps, AccelPreviewTrack.maxInitialStepLead);
    });

    test('거리 cap도 실제로 걸음을 막는다', () {
      // step 여유(500+12)는 넉넉하지만 거리 여유가 먼저 소진되는 구성.
      // confirmedDistanceM > 0이라 완화된 초기 허용치가 아닌 평시 cap이 걸린다.
      const confirmedDistanceM = 5.0;
      final result = _feedPeaks(
        peakCount: 200,
        confirmedSteps: 500,
        confirmedDistanceM: confirmedDistanceM,
      );

      expect(
        result.distanceM,
        lessThanOrEqualTo(
          confirmedDistanceM + AccelPreviewTrack.maxDistanceLeadMeters,
        ),
      );
      expect(result.steps, lessThan(200));
    });
  });
}
