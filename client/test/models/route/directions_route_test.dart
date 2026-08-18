import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/directions_route.dart';

void main() {
  group('classifyTurn', () {
    test('20도 미만이면 직진', () {
      expect(
        classifyTurn(bearingBeforeDeg: 10, bearingAfterDeg: 25),
        DirectionsTurn.straight,
      );
    });

    test('북쪽에서 동쪽으로 90도 틀면 우회전', () {
      expect(
        classifyTurn(bearingBeforeDeg: 0, bearingAfterDeg: 90),
        DirectionsTurn.turnRight,
      );
    });

    test('동쪽에서 북쪽으로 90도 틀면 좌회전', () {
      expect(
        classifyTurn(bearingBeforeDeg: 90, bearingAfterDeg: 0),
        DirectionsTurn.turnLeft,
      );
    });

    test('0/360 경계를 정규화해서 우회전으로 본다', () {
      expect(
        classifyTurn(bearingBeforeDeg: 350, bearingAfterDeg: 10),
        DirectionsTurn.turnRight,
      );
    });
  });

  test('DirectionsRoute.steps 기본값은 빈 리스트다', () {
    const route = DirectionsRoute(
      points: [LatLng(0, 0), LatLng(1, 1)],
      distanceMeters: 100,
      durationSeconds: 60,
    );
    expect(route.steps, isEmpty);
  });

  test('DirectionsRouteStep은 문구·거리·좌표를 그대로 갖는다', () {
    const step = DirectionsRouteStep(
      instruction: '우회전',
      distanceMeters: 200,
      point: LatLng(0.002, 0),
    );
    expect(step.instruction, '우회전');
    expect(step.distanceMeters, 200);
    expect(step.point, const LatLng(0.002, 0));
  });
}
