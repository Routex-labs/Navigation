import 'package:latlong2/latlong.dart';

import 'floor_plan.dart';

/// api/app/schema/route.py의 RouteResponse를 파싱한 결과.
/// 좌표는 FloorPlan과 동일한 규칙(wgs84PointToLatLng)으로 변환되므로
/// 같은 MapLibre 지도 위에 그대로 겹쳐 그릴 수 있다.
class IndoorRoute {
  const IndoorRoute({required this.points, required this.distanceMeters});

  final List<LatLng> points;
  final double distanceMeters;

  factory IndoorRoute.fromJson(Map<String, dynamic> json) {
    final points = ((json['path_points_wgs84'] as List<dynamic>?) ?? const [])
        .map((point) => wgs84PointToLatLng(point as Map<String, dynamic>))
        .whereType<LatLng>()
        .toList();

    return IndoorRoute(
      points: points,
      distanceMeters: (json['total_distance_m'] as num).toDouble(),
    );
  }
}
