import 'package:latlong2/latlong.dart';

import '../../models/route/directions_route.dart';
import 'directions_repository.dart';

const _walkingSpeedMetersPerSecond = 1.2;

/// 도심 자동차 평균 속도(m/s). 시속 22 km쯤으로, 신호·정체를 포함한 값이다.
/// 직선 거리에 곱하는 값이라 정확도를 논할 수준은 아니고, "도보보다 몇 배
/// 빠르다"는 감만 맞추면 된다.
const _drivingSpeedMetersPerSecond = 6.0;

/// 실제 경로 API(TMAP 등) 없이 출발지-목적지 직선을 경로로 취급한다.
/// 실제 라우팅이 준비되면 [TmapDirectionsRepository]로 교체한다.
class MockDirectionsRepository implements DirectionsRepository {
  @override
  Future<DirectionsRoute?> getWalkingRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final distance = const Distance().as(LengthUnit.Meter, origin, destination);
    return DirectionsRoute(
      points: [origin, destination],
      distanceMeters: distance,
      durationSeconds: (distance / _walkingSpeedMetersPerSecond).round(),
    );
  }

  @override
  Future<DirectionsRoute?> getDrivingRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final distance = const Distance().as(LengthUnit.Meter, origin, destination);
    return DirectionsRoute(
      points: [origin, destination],
      distanceMeters: distance,
      durationSeconds: (distance / _drivingSpeedMetersPerSecond).round(),
      // 요금은 **지어내지 않는다.** 거리로 곱해 만든 숫자를 "통행료 3,200원"
      // 처럼 적으면 사용자는 그것을 조회된 값으로 읽는다. 없으면 카드가 그
      // 줄을 아예 안 그린다.
    );
  }
}
