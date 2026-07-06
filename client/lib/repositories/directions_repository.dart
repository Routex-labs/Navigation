import 'package:latlong2/latlong.dart';

import '../models/directions_route.dart';

abstract class DirectionsRepository {
  /// origin에서 destination까지의 도보 경로를 반환한다. 실패하면 null.
  Future<DirectionsRoute?> getWalkingRoute({
    required LatLng origin,
    required LatLng destination,
  });
}
