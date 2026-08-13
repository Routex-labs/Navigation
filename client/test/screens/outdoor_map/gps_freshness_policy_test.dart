import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/gps_freshness_policy.dart';

void main() {
  final now = DateTime.utc(2026, 8, 13, 13, 41);

  group('shouldRequestFreshFix', () {
    test('아직 한 건도 못 받았으면 즉시 요청한다', () {
      expect(
        shouldRequestFreshFix(
          lastFixReceivedAt: null,
          now: now,
          requestInFlight: false,
        ),
        isTrue,
      );
    });

    test('요청이 떠 있으면 겹쳐 쏘지 않는다', () {
      expect(
        shouldRequestFreshFix(
          lastFixReceivedAt: null,
          now: now,
          requestInFlight: true,
        ),
        isFalse,
      );
    });

    test('스트림이 1초마다 주는 기기에서는 발화하지 않는다', () {
      // 이게 깨지면 정상 기기에서까지 배터리를 태운다.
      expect(
        shouldRequestFreshFix(
          lastFixReceivedAt: now.subtract(const Duration(seconds: 1)),
          now: now,
          requestInFlight: false,
        ),
        isFalse,
      );
    });

    test('실측에서 관측된 15~36초 공백은 반드시 잡는다', () {
      for (final gap in [15.5, 23.3, 36.2, 36.4]) {
        expect(
          shouldRequestFreshFix(
            lastFixReceivedAt: now.subtract(
              Duration(milliseconds: (gap * 1000).round()),
            ),
            now: now,
            requestInFlight: false,
          ),
          isTrue,
          reason: '$gap초 공백이 안 잡혔다',
        );
      }
    });

    test('경계(3초)에서는 요청한다', () {
      expect(
        shouldRequestFreshFix(
          lastFixReceivedAt: now.subtract(gpsFixMaxAge),
          now: now,
          requestInFlight: false,
        ),
        isTrue,
      );
    });
  });
}
