import 'package:latlong2/latlong.dart';

/// 출발지에서 목적지까지의 도보 경로.
class DirectionsRoute {
  const DirectionsRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final int durationSeconds;
}
