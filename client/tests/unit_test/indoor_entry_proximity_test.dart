import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/screens/outdoor_map/indoor_entry_proximity.dart';

/// 건물 외곽선 기하 계산 테스트.
///
/// 이 값들이 실내 진입/이탈 판정의 입력이다([indoor_entry_gps.dart]). 특히
/// [metersInsidePolygon]과 [metersToPolygon]이 어긋나면 벽 근처에서 진입과 이탈이
/// 동시에 성립해 화면이 실내와 야외를 오간다. 판정을 지도 컨트롤러에서 떼어낸
/// 순수 함수로 두고 여기서 고정한다.
void main() {
  /// 데모 건물(assets/mock/sample_building.json)의 footprint. 위도 폭
  /// 0.0004도(약 44 m), 경도 폭 0.0006도(이 위도에서 약 53 m)인 사각형이다.
  const footprint = <ll.LatLng>[
    ll.LatLng(37.5663, 126.9777),
    ll.LatLng(37.5667, 126.9777),
    ll.LatLng(37.5667, 126.9783),
    ll.LatLng(37.5663, 126.9783),
  ];

  const center = ll.LatLng(37.5665, 126.9780);

  // 위도 1도 = 111320 m 기준. 경도는 이 위도에서 cos(37.5665) 배(약 88231 m/도).
  const metersPerDegreeLat = 111320.0;
  const metersPerDegreeLng = 88231.0;

  ll.LatLng northOf(double meters) =>
      ll.LatLng(37.5667 + meters / metersPerDegreeLat, 126.9780);
  ll.LatLng eastOf(double meters) =>
      ll.LatLng(37.5665, 126.9783 + meters / metersPerDegreeLng);

  group('폴리곤 폭', () {
    // 실내 진입 임계값을 화면 폭에 맞출 때 "이 건물이 화면에 담기는 zoom"의
    // 입력이다. 여기가 틀리면 좁은 화면의 진입 임계값이 통째로 어긋난다.
    test('경도 폭을 이 위도의 미터로 환산한다', () {
      // 경도 0.0006도 x 88231 m/도 ≈ 53 m.
      expect(polygonWidthMeters(footprint), closeTo(52.9, 0.5));
    });

    test('위도가 높아질수록 같은 경도 폭이 좁아진다', () {
      const north = <ll.LatLng>[
        ll.LatLng(60.0000, 126.9777),
        ll.LatLng(60.0004, 126.9777),
        ll.LatLng(60.0004, 126.9783),
        ll.LatLng(60.0000, 126.9783),
      ];
      expect(
        polygonWidthMeters(north),
        lessThan(polygonWidthMeters(footprint)),
      );
    });

    test('점이 3개 미만이면 0이다', () {
      // 호출부는 0을 "보정 근거 없음"으로 읽고 기본 임계값을 그대로 쓴다.
      expect(polygonWidthMeters(const []), 0);
      expect(
        polygonWidthMeters(const [
          ll.LatLng(37.5663, 126.9777),
          ll.LatLng(37.5667, 126.9783),
        ]),
        0,
      );
    });
  });

  group('폴리곤 내부 판정', () {
    test('건물 중심은 내부다', () {
      expect(isPointInPolygon(center, footprint), isTrue);
    });

    test('건물 밖 좌표는 내부가 아니다', () {
      expect(isPointInPolygon(northOf(30), footprint), isFalse);
      expect(isPointInPolygon(eastOf(30), footprint), isFalse);
    });

    test('점이 3개 미만이면 판정하지 않는다', () {
      expect(isPointInPolygon(center, const []), isFalse);
      expect(
        isPointInPolygon(center, const [
          ll.LatLng(37.5663, 126.9777),
          ll.LatLng(37.5667, 126.9777),
        ]),
        isFalse,
      );
    });
  });

  group('폴리곤까지의 거리', () {
    test('내부면 0이다', () {
      expect(metersToPolygon(center, footprint), 0);
    });

    test('북쪽 50 m는 약 50 m로 나온다', () {
      expect(metersToPolygon(northOf(50), footprint), closeTo(50, 1.0));
    });

    test('경도 방향 거리에 cos(위도)를 반영한다', () {
      // 반영하지 않으면 같은 좌표가 약 88 m로 나와 26% 부풀려진다.
      // 서울 위도에서 동서 거리를 남북과 같은 척도로 재던 실수를 잡는 케이스다.
      expect(metersToPolygon(eastOf(70), footprint), closeTo(70, 1.0));
    });

    test('꼭짓점이 아니라 변까지의 거리를 잰다', () {
      // 위쪽 변(길이 약 53 m) 중점에서 10 m 위. 가장 가까운 꼭짓점까지는 약
      // 28 m지만 변까지는 10 m다. 꼭짓점만 비교하면 벽면 한가운데로 나온
      // 사용자가 "아직 건물에서 멀다"고 잘못 판정된다.
      expect(metersToPolygon(northOf(10), footprint), closeTo(10, 1.0));
    });

    test('점이 3개 미만이면 무한대다', () {
      // 호출부는 이 값을 "판정 근거 없음"으로 읽는다.
      expect(metersToPolygon(center, const []), double.infinity);
    });
  });

  group('폴리곤 안쪽으로 들어온 거리', () {
    test('밖이면 0이다', () {
      expect(metersInsidePolygon(northOf(10), footprint), 0);
    });

    test('안쪽에서는 가장 가까운 변까지의 거리다', () {
      // 중심은 남북 폭 44 m의 한가운데라 가장 가까운 변(위/아래)까지 22 m다.
      expect(metersInsidePolygon(center, footprint), closeTo(22, 1.0));
    });

    test('벽 바로 안쪽은 작은 값이다', () {
      // 진입 판정이 이 값을 임계값과 비교한다. 여기가 부풀면 문 앞에 선 사람이
      // 이미 들어온 것으로 읽힌다.
      final justInside = ll.LatLng(
        37.5667 - 3 / metersPerDegreeLat,
        126.9780,
      );
      expect(metersInsidePolygon(justInside, footprint), closeTo(3, 0.5));
    });

    test('두 거리 중 하나는 항상 0이다', () {
      // 같은 좌표가 "안으로 5 m"이면서 "밖으로 20 m"일 수는 없다. 이 불변이
      // 깨지면 진입과 이탈이 동시에 성립한다.
      for (final point in [center, northOf(10), northOf(100), eastOf(5)]) {
        final inside = metersInsidePolygon(point, footprint);
        final outside = metersToPolygon(point, footprint);
        expect(inside == 0 || outside == 0, isTrue);
      }
    });

    test('점이 3개 미만이면 0이다', () {
      expect(metersInsidePolygon(center, const []), 0);
    });
  });
}
