import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/screens/outdoor_map/route_recompute_policy.dart';

const _origin = LatLng(37.525862, 126.928540);
const _metersPerDegreeLat = 111320.0;

/// [_origin]에서 북쪽으로 [meters] m 떨어진 좌표.
LatLng _north(double meters) =>
    LatLng(_origin.latitude + meters / _metersPerDegreeLat, _origin.longitude);

/// [_origin]에서 동쪽으로 [meters] m 떨어진 좌표.
LatLng _east(double meters) => LatLng(
  _origin.latitude,
  _origin.longitude +
      meters / (_metersPerDegreeLat * math.cos(_origin.latitude * math.pi / 180)),
);

void main() {
  test('아직 한 번도 요청하지 않았으면 계산한다', () {
    expect(
      shouldRecomputeRouteAfterMove(
        origin: _origin,
        lastRequestedOrigin: null,
      ),
      isTrue,
    );
  });

  test('제자리에서 흔들리는 좌표로는 다시 요청하지 않는다', () {
    // 서 있어도 GPS는 몇 m씩 튄다. 이걸 걸러내지 못하면 가만히 있는 사용자
    // 때문에 초당 한 번씩 TMAP 요청이 나간다.
    expect(
      shouldRecomputeRouteAfterMove(
        origin: _north(4),
        lastRequestedOrigin: _origin,
      ),
      isFalse,
    );
  });

  test('문턱만큼 움직이면 다시 요청한다', () {
    expect(
      shouldRecomputeRouteAfterMove(
        origin: _north(routeRecomputeMinMoveMeters),
        lastRequestedOrigin: _origin,
      ),
      isTrue,
    );
  });

  test('방향과 무관하게 거리로만 판단한다', () {
    expect(
      shouldRecomputeRouteAfterMove(
        origin: _east(12),
        lastRequestedOrigin: _origin,
      ),
      isTrue,
    );
  });

  test('문턱은 호출부가 좁힐 수 있다', () {
    expect(
      shouldRecomputeRouteAfterMove(
        origin: _north(4),
        lastRequestedOrigin: _origin,
        minMoveMeters: 3,
      ),
      isTrue,
    );
  });
}
