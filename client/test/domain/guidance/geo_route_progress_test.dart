import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/guidance/geo_route_progress.dart';

void main() {
  const route = [LatLng(37.0, 127.0), LatLng(37.0, 127.001)];

  test('위경도 경로를 미터 기준으로 투영해 완료/잔여 거리를 만든다', () {
    final progress = computeGeoRouteProgress(
      routePoints: route,
      position: const LatLng(37.000005, 127.0005),
    );

    expect(progress, isNotNull);
    expect(progress!.traveledM, closeTo(44.5, 1.0));
    expect(progress.remainingM, closeTo(44.5, 1.0));
    expect(progress.offsetM, closeTo(0.55, 0.2));
    expect(progress.segmentIndex, 0);
    expect(progress.reacquired, isFalse);
  });

  test('이전 진행점에서 멀리 튄 GPS는 재획득으로 표시한다', () {
    final progress = computeGeoRouteProgress(
      routePoints: route,
      position: const LatLng(37.0, 127.0009),
      previousTraveledM: 5,
      searchWindowM: 10,
    );

    expect(progress, isNotNull);
    expect(progress!.reacquired, isTrue);
  });

  test('경로에서 벗어난 좌표도 투영 거리를 미터로 계산한다', () {
    final progress = computeGeoRouteProgress(
      routePoints: route,
      position: const LatLng(37.0003, 127.0005),
    );

    expect(progress, isNotNull);
    expect(progress!.offsetM, closeTo(33.4, 1.0));
  });
}
