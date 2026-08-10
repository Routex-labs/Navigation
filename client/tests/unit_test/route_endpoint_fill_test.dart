import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/route_endpoint_fill.dart';
import 'package:navigation_client/models/directions_route.dart';

/// 여의도 일대. 위도 1도 ≈ 111km라 소수 넷째 자리가 약 11m다.
const _roadEnd = LatLng(37.5259, 126.9290);

DirectionsRoute _route(List<LatLng> points) => DirectionsRoute(
  points: points,
  distanceMeters: 3448,
  durationSeconds: 2880,
);

void main() {
  test('도로에서 끝난 선을 출입구까지 이어 붙인다', () {
    // 도로 끝에서 약 30m 떨어진 출입구.
    const entrance = LatLng(37.52617, 126.9290);
    final filled = extendRouteToDestination(_route(const [
      LatLng(37.5280, 126.9290),
      _roadEnd,
    ]), entrance);

    expect(filled!.points, hasLength(3));
    expect(filled.points.last, entrance);
    // 거리·시간은 건드리지 않는다. 여기서 더하기 시작하면 화면에 적히는 숫자의
    // 출처가 둘로 갈린다.
    expect(filled.distanceMeters, 3448);
    expect(filled.durationSeconds, 2880);
  });

  test('사실상 같은 점이면 붙이지 않는다', () {
    final filled = extendRouteToDestination(
      _route(const [LatLng(37.5280, 126.9290), _roadEnd]),
      const LatLng(37.52590, 126.92901),
    );

    expect(filled!.points, hasLength(2));
  });

  test('너무 멀면 붙이지 않는다 — 직선이 건물·도로를 관통한다', () {
    // 약 1.1km 떨어진 점. 끊긴 선은 "여기부터 알아서"로 읽히지만, 그어진
    // 직선은 길이라고 읽힌다.
    final filled = extendRouteToDestination(
      _route(const [LatLng(37.5280, 126.9290), _roadEnd]),
      const LatLng(37.5359, 126.9290),
    );

    expect(filled!.points, hasLength(2));
  });

  test('경로나 도착점이 없으면 그대로 돌려준다', () {
    expect(extendRouteToDestination(null, _roadEnd), isNull);
    final route = _route(const [LatLng(37.5280, 126.9290), _roadEnd]);
    expect(extendRouteToDestination(route, null), same(route));
    // 좌표가 한 점뿐이면 이을 선 자체가 없다.
    final single = _route(const [_roadEnd]);
    expect(
      extendRouteToDestination(single, const LatLng(37.52617, 126.9290)),
      same(single),
    );
  });
}
