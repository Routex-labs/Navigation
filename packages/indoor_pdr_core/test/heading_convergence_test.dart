import 'package:indoor_pdr_core/src/application/heading_trackers.dart';
import 'package:test/test.dart';

/// 33Hz DeviceMotion을 흉내내 [durationMs] 동안 heading을 먹인다.
void _feed(
  HeadingConvergenceTracker tracker, {
  required int startMs,
  required int durationMs,
  required double Function(int ms) headingAt,
}) {
  for (var ms = startMs; ms <= startMs + durationMs; ms += 30) {
    tracker.update(ms, headingAt(ms));
  }
}

void main() {
  group('HeadingConvergenceTracker', () {
    test('가만히 있는 heading은 수렴으로 본다', () {
      final tracker = HeadingConvergenceTracker();
      _feed(
        tracker,
        startMs: 0,
        durationMs: 2000,
        headingAt: (ms) => 142.0 + (ms % 3),
      );

      expect(tracker.converged, isTrue);
      expect(tracker.spreadDeg, lessThan(12));
    });

    test('창이 최소 시간만큼 안 찼으면 아직 수렴이 아니다', () {
      final tracker = HeadingConvergenceTracker();
      // minSpanMs(1200) 미만이라 값이 아무리 안정적이어도 판정을 미룬다.
      _feed(tracker, startMs: 0, durationMs: 600, headingAt: (_) => 142.0);

      expect(tracker.converged, isFalse);
    });

    test('흔들리는 동안에는 수렴으로 보지 않는다', () {
      // 세션 시작 직후 실측 패턴: 282° -> 125° 로 크게 튄 뒤 자리를 잡는다.
      final tracker = HeadingConvergenceTracker();
      _feed(
        tracker,
        startMs: 0,
        durationMs: 1600,
        headingAt: (ms) => ms < 800 ? 282.0 : 125.0,
      );

      expect(tracker.converged, isFalse);
      expect(tracker.spreadDeg, greaterThan(12));
    });

    test('흔들린 뒤 자리를 잡으면 수렴으로 바뀐다', () {
      final tracker = HeadingConvergenceTracker();
      _feed(
        tracker,
        startMs: 0,
        durationMs: 1600,
        headingAt: (ms) => ms < 800 ? 282.0 : 125.0,
      );
      expect(tracker.converged, isFalse);

      _feed(tracker, startMs: 1700, durationMs: 2000, headingAt: (_) => 125.0);
      expect(tracker.converged, isTrue);
    });

    test('360/0 경계를 넘나드는 heading도 수렴으로 본다', () {
      // 원형 평균을 쓰지 않으면 358°와 2°의 평균이 180°로 잡혀 오판한다.
      final tracker = HeadingConvergenceTracker();
      _feed(
        tracker,
        startMs: 0,
        durationMs: 2000,
        headingAt: (ms) => (ms ~/ 30).isEven ? 358.0 : 2.0,
      );

      expect(tracker.converged, isTrue);
    });

    test('reset은 수렴 상태를 되돌린다', () {
      final tracker = HeadingConvergenceTracker();
      _feed(tracker, startMs: 0, durationMs: 2000, headingAt: (_) => 142.0);
      expect(tracker.converged, isTrue);

      tracker.reset();
      expect(tracker.converged, isFalse);
      expect(tracker.spreadDeg, 0);
    });
  });
}
