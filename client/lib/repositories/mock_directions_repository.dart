import 'package:latlong2/latlong.dart';

import '../models/directions_route.dart';
import 'directions_repository.dart';

const _walkingSpeedMetersPerSecond = 1.2;

/// 실제 도보 경로 API(TMAP 등) 없이 출발지-목적지 직선을 도보 경로로 취급한다.
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
}
