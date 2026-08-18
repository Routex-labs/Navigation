/// 자동차 경로 후보(kind, DirectionsRoute) 묶음을 화면에 보일 목록으로
/// 합친다.
///
/// 좌표열이 같은 후보는 한 줄로 합치고, 순서는 추천 > 최단거리 > 대안이다.
/// `feature-car-route-alternatives` 브랜치의 `_geometryKey()`를 그대로
/// 가져왔다 — 총거리·시간이 아니라 좌표열로 비교하는 이유는
/// `docs/client/car-route-alternatives.md`에 있다.
library;

import '../../models/route/directions_route.dart';

const _kindPriority = [
  DirectionsRouteOptionKind.recommended,
  DirectionsRouteOptionKind.shortestDistance,
  DirectionsRouteOptionKind.alternative,
];

/// [candidates]를 kind 우선순위로 정렬하고 좌표열이 같은 것을 합친다.
List<DirectionsRouteOption> mergeDirectionsRouteOptions(
  List<(DirectionsRouteOptionKind, DirectionsRoute)> candidates,
) {
  final sorted = [...candidates]..sort(
    (a, b) =>
        _kindPriority.indexOf(a.$1).compareTo(_kindPriority.indexOf(b.$1)),
  );
  final order = <String>[];
  final byKey = <String, DirectionsRouteOption>{};
  for (final (kind, route) in sorted) {
    final key = _geometryKey(route);
    final existing = byKey[key];
    if (existing == null) {
      order.add(key);
      byKey[key] = DirectionsRouteOption(kinds: [kind], route: route);
    } else {
      byKey[key] = DirectionsRouteOption(
        kinds: [...existing.kinds, kind],
        route: existing.route,
      );
    }
  }
  return [for (final key in order) byKey[key]!];
}

String _geometryKey(DirectionsRoute route) =>
    route.points.map((p) => '${p.latitude},${p.longitude}').join(';');
