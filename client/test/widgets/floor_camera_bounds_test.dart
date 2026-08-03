import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/widgets/floor_camera_bounds.dart';

/// 더현대 서울 1F를 흉내낸 사각 도면.
const _footprint = [
  ll.LatLng(37.0, 127.0),
  ll.LatLng(37.2, 127.0),
  ll.LatLng(37.2, 127.4),
  ll.LatLng(37.0, 127.4),
];

void main() {
  group('clampToFootprint', () {
    // 가만히 둔 지도가 매 idle마다 animateCamera로 미세하게 떨리면 안 된다.
    test('이미 도면 안이면 아무것도 하지 않는다', () {
      expect(clampToFootprint(const ll.LatLng(37.1, 127.2), _footprint), isNull);
    });

    test('경계 위도 정확히 위에 있으면 그대로 둔다', () {
      expect(clampToFootprint(const ll.LatLng(37.0, 127.0), _footprint), isNull);
      expect(clampToFootprint(const ll.LatLng(37.2, 127.4), _footprint), isNull);
    });

    test('밖으로 나간 축만 가장자리로 당긴다', () {
      final clamped = clampToFootprint(
        const ll.LatLng(37.9, 127.2),
        _footprint,
      )!;

      expect(clamped.latitude, closeTo(37.2, 1e-9));
      // 안에 있던 경도는 건드리지 않는다.
      expect(clamped.longitude, closeTo(127.2, 1e-9));
    });

    test('두 축 모두 나가면 모서리로 당긴다', () {
      final clamped = clampToFootprint(
        const ll.LatLng(36.0, 128.5),
        _footprint,
      )!;

      expect(clamped.latitude, closeTo(37.0, 1e-9));
      expect(clamped.longitude, closeTo(127.4, 1e-9));
    });

    // 기준이 없는데 되돌리면 엉뚱한 데로 끌고 간다. 무한히 밀리는 것보다 나쁘다.
    test('wgs84 footprint가 없으면 되돌리지 않는다', () {
      expect(clampToFootprint(const ll.LatLng(0, 0), const []), isNull);
      expect(
        clampToFootprint(const ll.LatLng(0, 0), const [ll.LatLng(37.0, 127.0)]),
        isNull,
      );
    });

    test('한 축이 퇴화한 도면도 되돌리지 않는다', () {
      expect(
        clampToFootprint(const ll.LatLng(38.0, 127.0), const [
          ll.LatLng(37.0, 127.0),
          ll.LatLng(37.2, 127.0),
        ]),
        isNull,
      );
    });
  });
}
