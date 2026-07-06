import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/repositories/mock_directions_repository.dart';

void main() {
  test('returns a straight line with distance and duration', () async {
    final repository = MockDirectionsRepository();
    const origin = LatLng(37.5665, 126.9780);
    const destination = LatLng(37.5665, 126.9790);

    final route = await repository.getWalkingRoute(
      origin: origin,
      destination: destination,
    );

    expect(route, isNotNull);
    expect(route!.points, [origin, destination]);
    expect(route.distanceMeters, greaterThan(0));
    expect(route.durationSeconds, greaterThan(0));
  });
}
