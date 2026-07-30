import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/application/indoor_location_estimate.dart';
import 'package:navigation_client/models/floor_graph.dart';

const _graph = FloorGraph(
  nodes: [
    GraphNode(id: 'a', type: 'corridor', xM: 0, yM: 0, lat: 37.5, lng: 127.0),
    GraphNode(
      id: 'b',
      type: 'corridor',
      xM: 10,
      yM: 0,
      lat: 37.5,
      lng: 127.000113,
    ),
    GraphNode(
      id: 'c',
      type: 'corridor',
      xM: 0,
      yM: 10,
      lat: 37.50009,
      lng: 127.0,
    ),
  ],
  edges: [
    GraphEdge(
      id: 'ab',
      fromNodeId: 'a',
      toNodeId: 'b',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [],
    ),
    GraphEdge(
      id: 'ac',
      fromNodeId: 'a',
      toNodeId: 'c',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [],
    ),
  ],
);

void main() {
  final now = DateTime.utc(2026, 7, 30, 12);

  test('정확하고 최근인 GPS는 가장 가까운 통로에 붙여 추정위치를 만든다', () {
    final estimate = estimateIndoorLocationFromGps(
      buildingId: 'building',
      floorId: '1F',
      graph: _graph,
      latitude: 37.5,
      longitude: 127.0000565,
      accuracyMeters: 5,
      observedAt: now,
      now: now,
    );

    expect(estimate, isNotNull);
    expect(estimate!.source, 'gps');
    expect(estimate.localM.eastM, closeTo(5, 0.2));
    expect(estimate.localM.northM, closeTo(0, 0.2));
  });

  test('정확도가 15m를 넘는 GPS는 자동 위치로 쓰지 않는다', () {
    final estimate = estimateIndoorLocationFromGps(
      buildingId: 'building',
      floorId: '1F',
      graph: _graph,
      latitude: 37.5,
      longitude: 127.0,
      accuracyMeters: 15.1,
      observedAt: now,
      now: now,
    );

    expect(estimate, isNull);
  });

  test('30초보다 오래된 GPS는 자동 위치로 쓰지 않는다', () {
    final estimate = estimateIndoorLocationFromGps(
      buildingId: 'building',
      floorId: '1F',
      graph: _graph,
      latitude: 37.5,
      longitude: 127.0,
      accuracyMeters: 5,
      observedAt: now.subtract(const Duration(seconds: 31)),
      now: now,
    );

    expect(estimate, isNull);
  });

  test('통로에서 12m보다 먼 GPS는 자동 위치로 쓰지 않는다', () {
    final estimate = estimateIndoorLocationFromGps(
      buildingId: 'building',
      floorId: '1F',
      graph: _graph,
      latitude: 37.5003,
      longitude: 127.0003,
      accuracyMeters: 5,
      observedAt: now,
      now: now,
    );

    expect(estimate, isNull);
  });
}
