import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';

/// 경로 선 스타일 팩토리 (design.md 공통 컴포넌트: RoutePolyline).
/// 실제 최단 경로 계산(M2-003) 전까지는 현재 위치-목적지 직선을 그린다.
Polyline buildRoutePolyline(List<LatLng> points) {
  return Polyline(points: points, color: AppColors.primary, strokeWidth: 5);
}
