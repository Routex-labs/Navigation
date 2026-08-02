import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/map_route_style.dart';

void main() {
  test('축소 zoom에서는 경로 화살표 간격을 더 좁힌다', () {
    expect(kRouteArrowSpacingExpr, const [
      'interpolate',
      ['linear'],
      ['zoom'],
      16,
      40.0,
      18,
      56.0,
      20,
      72.0,
    ]);
    expect(routeArrowProps().symbolSpacing, kRouteArrowSpacingExpr);
  });

  test('화살표는 수평 경로에만 지도 기준으로 배치한다', () {
    final props = routeArrowProps();

    expect(props.symbolPlacement, 'line');
    expect(props.iconRotationAlignment, 'map');
  });
}
