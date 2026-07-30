import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/route_guidance.dart';
import 'package:navigation_client/domain/route_progress.dart';
import 'package:navigation_client/models/floor_graph.dart';

void main() {
  const points = [LocalPoint(0, 0), LocalPoint(0, 10), LocalPoint(10, 10)];
  const wgs84 = [
    LatLng(37, 127),
    LatLng(37.00009, 127),
    LatLng(37.00009, 127.000113),
  ];

  test('현재 위치에서 첫 의미 있는 회전 거리와 방향을 안내한다', () {
    const progress = RouteProgress(
      traveledM: 4,
      remainingM: 16,
      offsetM: 0,
      onRouteEdge: true,
      reacquired: false,
      segmentIndex: 0,
      projectedPoint: LocalPoint(0, 4),
    );

    final instruction = buildRouteGuidance(
      localPoints: points,
      wgs84Points: wgs84,
      progress: progress,
    );

    expect(instruction.action, RouteGuidanceAction.turnRight);
    expect(instruction.primaryText, '잠시 후 우회전');
  });

  test('회전이 없고 다음 층 이동이 있으면 에스컬레이터를 우선 안내한다', () {
    const progress = RouteProgress(
      traveledM: 0,
      remainingM: 10,
      offsetM: 0,
      onRouteEdge: true,
      reacquired: false,
      segmentIndex: 0,
      projectedPoint: LocalPoint(0, 0),
    );

    final instruction = buildRouteGuidance(
      localPoints: const [LocalPoint(0, 0), LocalPoint(0, 10)],
      wgs84Points: const [LatLng(37, 127), LatLng(37.00009, 127)],
      progress: progress,
      transferMode: 'escalator',
    );

    expect(instruction.action, RouteGuidanceAction.escalator);
    expect(instruction.primaryText, '10미터 후 에스컬레이터 탑승');
  });

  test('행동 거리는 실제 신뢰도에 맞게 5m 단위로 반올림한다', () {
    const progress = RouteProgress(
      traveledM: 0,
      remainingM: 18,
      offsetM: 0,
      onRouteEdge: true,
      reacquired: false,
      segmentIndex: 0,
      projectedPoint: LocalPoint(0, 0),
    );

    final instruction = buildRouteGuidance(
      localPoints: const [LocalPoint(0, 0), LocalPoint(0, 18)],
      wgs84Points: const [LatLng(37, 127), LatLng(37.00016, 127)],
      progress: progress,
      transferMode: 'escalator',
    );

    expect(instruction.primaryText, '20미터 후 에스컬레이터 탑승');
  });

  test('현재 간선 확정이 흔들려도 진행점을 기준으로 회색·파란선을 나눈다', () {
    const progress = RouteProgress(
      traveledM: 4,
      remainingM: 16,
      offsetM: 0,
      onRouteEdge: false,
      reacquired: false,
      segmentIndex: 0,
      projectedPoint: LocalPoint(0, 4),
    );

    final split = splitRouteAtProgress(points, progress)!;

    expect(split.completed, const [LocalPoint(0, 0), LocalPoint(0, 4)]);
    expect(split.remaining, const [
      LocalPoint(0, 4),
      LocalPoint(0, 10),
      LocalPoint(10, 10),
    ]);
  });

  test('다층 중간 세그먼트 끝은 목적지 도착으로 안내하지 않는다', () {
    const progress = RouteProgress(
      traveledM: 10,
      remainingM: 0,
      offsetM: 0,
      onRouteEdge: true,
      reacquired: false,
      segmentIndex: 0,
      projectedPoint: LocalPoint(0, 10),
    );

    final instruction = buildRouteGuidance(
      localPoints: const [LocalPoint(0, 0), LocalPoint(0, 10)],
      wgs84Points: const [LatLng(37, 127), LatLng(37.00009, 127)],
      progress: progress,
      allowArrival: false,
    );

    expect(instruction.action, isNot(RouteGuidanceAction.arrived));
    expect(instruction.primaryText, '다음 층 이동 지점입니다');
  });
}
