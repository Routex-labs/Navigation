import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/escalator_ride.dart';

/// 위도 37.5 기준 약 10m 동쪽. 경도 1도 ≈ 88.4km.
const _tenMetersEastLng = 127.0 + 10 / 88400.0;

void main() {
  group('탑승 활강', () {
    const from = LatLng(37.5, 127.0);
    const to = LatLng(37.5, _tenMetersEastLng);
    const glide = EscalatorGlide(from: from, to: to, startedAtMs: 1000);

    test('시작 시각에는 탑승 노드에 있다', () {
      expect(glide.pointAt(1000).longitude, from.longitude);
      expect(glide.progressAt(1000), 0);
    });

    test('시간이 지나면 도착 노드 쪽으로 흐른다', () {
      final mid = glide.pointAt(
        1000 + escalatorGlideDuration.inMilliseconds ~/ 2,
      );
      expect(mid.longitude, greaterThan(from.longitude));
      expect(mid.longitude, lessThan(to.longitude));
    });

    test('끝난 뒤에는 도착 노드에 머문다', () {
      // 하차 확정은 활강보다 늦게 온다. 그 사이 마커가 계속 흘러가면 도착
      // 노드를 지나쳐 매장 안으로 들어간다.
      final after = glide.pointAt(1000 + 60000);
      expect(after.longitude, closeTo(to.longitude, 1e-12));
      expect(glide.isDoneAt(1000 + 60000), isTrue);
    });

    test('시작 전 시각도 탑승 노드로 잡는다', () {
      expect(glide.progressAt(0), 0);
    });
  });

  group('하차 방향', () {
    test('탑승 → 도착 방위각을 낸다', () {
      final bearing = escalatorExitBearingDeg(
        boarding: const LatLng(37.5, 127.0),
        arrival: const LatLng(37.5, _tenMetersEastLng),
      );

      expect(bearing, closeTo(90, 1));
    });

    test('북쪽으로 내리면 0도다', () {
      final bearing = escalatorExitBearingDeg(
        boarding: const LatLng(37.5, 127.0),
        arrival: const LatLng(37.5 + 10 / 111320.0, 127.0),
      );

      expect(bearing, closeTo(0, 1));
    });

    test('두 노드가 겹쳐 있으면 방향을 단정하지 않는다', () {
      // 수직으로만 그려 둔 도면. 좌표 오차가 만드는 아무 방향으로 지도를
      // 돌리느니 그대로 두는 편이 낫다.
      final bearing = escalatorExitBearingDeg(
        boarding: const LatLng(37.5, 127.0),
        arrival: const LatLng(37.5, 127.0 + 1 / 88400.0),
      );

      expect(bearing, isNull);
    });
  });
}
