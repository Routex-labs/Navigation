import 'package:latlong2/latlong.dart';

import 'floor_graph.dart';
import 'floor_plan.dart';

/// api/app/schema/route.py의 RouteResponse를 파싱한 결과.
/// 좌표는 FloorPlan과 동일한 규칙(wgs84PointToLatLng)으로 변환되므로
/// 같은 MapLibre 지도 위에 그대로 겹쳐 그릴 수 있다.
class IndoorRoute {
  const IndoorRoute({
    required this.points,
    required this.distanceMeters,
    this.pointsLocalM = const [],
    this.edgeIds = const [],
  });

  final List<LatLng> points;
  final double distanceMeters;

  /// [points]와 같은 폴리라인을 층 로컬 미터 좌표로 담은 값.
  ///
  /// PDR 보정 위치가 층 로컬 좌표라, 경로 진행률을 계산할 때 LatLng으로
  /// 왕복 변환하지 않고 한 좌표계에서 투영하려면 이 값이 필요하다. 서버
  /// 응답만으로 만든 경로(`fromJson`)에는 없으므로 비어 있을 수 있다.
  final List<LocalPoint> pointsLocalM;

  /// 이 경로가 지나는 그래프 간선 id를 진행 순서대로 담은 값.
  ///
  /// 경로 이탈 판정의 근거다. 좌표 거리로 판정하면 경로와 나란한 옆 복도에
  /// 붙었을 때도 "경로 위"로 보이므로, 간선 동일성으로만 판정한다.
  /// `fromJson`으로 만든 경로에는 없으므로 비어 있을 수 있다.
  final List<String> edgeIds;

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
