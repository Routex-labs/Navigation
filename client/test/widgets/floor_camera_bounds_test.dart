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

  group('clampToFootprint — 화면 크기만큼 깎기', () {
    // 중심만 bbox 안에 가두면 중심이 모서리에 있는 상태가 합법이라, 그 순간
    // 화면의 절반 이상이 건물 밖 빈 공간이 된다.
    test('모서리는 화면 절반만큼 안쪽으로 밀린다', () {
      final clamped = clampToFootprint(
        const ll.LatLng(37.2, 127.4),
        _footprint,
        halfSpanLat: 0.05,
        halfSpanLng: 0.1,
      )!;

      expect(clamped.latitude, closeTo(37.15, 1e-9));
      expect(clamped.longitude, closeTo(127.3, 1e-9));
    });

    test('깎고 남은 영역 안이면 그대로 둔다', () {
      expect(
        clampToFootprint(
          const ll.LatLng(37.1, 127.2),
          _footprint,
          halfSpanLat: 0.05,
          halfSpanLng: 0.1,
        ),
        isNull,
      );
    });

    // 뒤집힌 범위를 그대로 clamp에 넘기면 ArgumentError가 난다.
    test('화면이 건물보다 크면 그 축은 중점으로 붕괴한다', () {
      final clamped = clampToFootprint(
        const ll.LatLng(37.0, 127.0),
        _footprint,
        halfSpanLat: 5,
        halfSpanLng: 5,
      )!;

      expect(clamped.latitude, closeTo(37.1, 1e-9));
      expect(clamped.longitude, closeTo(127.2, 1e-9));
    });

    test('한 축만 화면이 더 크면 그 축만 붕괴한다', () {
      final clamped = clampToFootprint(
        const ll.LatLng(37.0, 127.35),
        _footprint,
        halfSpanLat: 5,
        halfSpanLng: 0.05,
      )!;

      expect(clamped.latitude, closeTo(37.1, 1e-9));
      // 경도는 아직 깎을 여유가 있어 가장자리로만 당긴다.
      expect(clamped.longitude, closeTo(127.35, 1e-9));
    });

    // 되돌림은 animateCamera이고 그게 다시 onCameraIdle을 부른다.
    test('붕괴한 중점에 이미 서 있으면 되돌리지 않는다', () {
      expect(
        clampToFootprint(
          const ll.LatLng(37.1, 127.2),
          _footprint,
          halfSpanLat: 5,
          halfSpanLng: 5,
        ),
        isNull,
      );
    });

    test('화면 크기를 못 구해 0이 들어오면 예전대로 bbox만 본다', () {
      expect(
        clampToFootprint(
          const ll.LatLng(37.2, 127.4),
          _footprint,
          halfSpanLat: 0,
          halfSpanLng: 0,
        ),
        isNull,
      );
    });
  });
}
