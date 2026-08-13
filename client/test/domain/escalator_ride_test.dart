import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/escalator_ride.dart';

/// 위도 37.5 기준 약 10m 동쪽. 경도 1도 ≈ 88.4km.
const _tenMetersEastLng = 127.0 + 10 / 88400.0;

void main() {
  group('탑승 활강', () {
    const from = LatLng(37.5, 127.0);
    const to = LatLng(37.5, _tenMetersEastLng);
    const glide = EscalatorGlide(from: from, to: to);

    test('진행률 0이면 탑승 노드에 있다', () {
      expect(glide.pointAtProgress(0).longitude, from.longitude);
    });

    test('진행률이 오르면 도착 노드 쪽으로 흐른다', () {
      final mid = glide.pointAtProgress(0.5);
      expect(mid.longitude, greaterThan(from.longitude));
      expect(mid.longitude, lessThan(to.longitude));
    });

    test('진행률이 범위를 벗어나도 양 끝을 지킨다', () {
      // 하차 확정 뒤 마커가 도착 노드를 지나쳐 매장 안으로 들어가면 안 된다.
      expect(glide.pointAtProgress(1.4).longitude, closeTo(to.longitude, 1e-12));
      expect(glide.pointAtProgress(-0.2).longitude, from.longitude);
    });
  });

  group('기압 진행률', () {
    test('도면 교체 시점이 0, 예상 층고가 1이다', () {
      // 실측 리듬: 층고 5.9m, 교체 순간 Δ 2.6m.
      expect(
        escalatorRideProgressTarget(
          deltaTowardsM: 2.6,
          swapDeltaM: 2.6,
          expectedTotalM: 5.9,
        ),
        0,
      );
      expect(
        escalatorRideProgressTarget(
          deltaTowardsM: 4.25,
          swapDeltaM: 2.6,
          expectedTotalM: 5.9,
        ),
        closeTo(0.5, 0.01),
      );
    });

    test('추정으로는 1에 닿지 않는다', () {
      // 층고 추정이 실제보다 작아도 1은 하차 확정만이 채운다. 추정이 1을
      // 채우면 아직 타는 중인데 마커가 도착해 있는다.
      expect(
        escalatorRideProgressTarget(
          deltaTowardsM: 9.0,
          swapDeltaM: 2.6,
          expectedTotalM: 5.9,
        ),
        escalatorRideProgressCap,
      );
    });

    test('남은 높이 추정이 0에 가까워도 즉시 상한에 붙지 않는다', () {
      expect(
        escalatorRideProgressTarget(
          deltaTowardsM: 2.7,
          swapDeltaM: 2.6,
          expectedTotalM: 2.5,
        ),
        closeTo(0.1, 0.01),
      );
    });

    test('노이즈로 음수가 되면 0으로 잡는다', () {
      expect(
        escalatorRideProgressTarget(
          deltaTowardsM: 2.3,
          swapDeltaM: 2.6,
          expectedTotalM: 5.9,
        ),
        0,
      );
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
