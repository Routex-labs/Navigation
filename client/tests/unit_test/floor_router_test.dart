import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/floor_router.dart';
import 'package:navigation_client/models/floor_graph.dart';

/// api/app/services/navigation_service.py::NavigationService.get_shortest_path의
/// 포팅(다익스트라 + 경로 stitching + wgs84 변환 전체 파이프라인)을 검증한다.
void main() {
  test('경로가 있으면 노드 lat/lng을 정확히 지나는 폴리라인을 만든다', () {
    final graph = FloorGraph(
      nodes: [
        GraphNode(id: 'A', type: 'corridor', xM: 0, yM: 0, lat: 37.500, lng: 127.000),
        GraphNode(id: 'B', type: 'corridor', xM: 10, yM: 0, lat: 37.5001, lng: 127.0012),
        GraphNode(id: 'C', type: 'corridor', xM: 0, yM: 10, lat: 37.5011, lng: 127.0002),
      ],
      edges: [
        GraphEdge(
          id: 'AB',
          fromNodeId: 'A',
          toNodeId: 'B',
          lengthM: 5.0,
          bidirectional: true,
          geometryLocalM: const [],
        ),
      ],
    );

    final route = computeShortestRoute(graph, 'A', 'B');

    expect(route, isNotNull);
    expect(route!.distanceMeters, 5.0);
    expect(route.points.length, 2);
    expect(route.points.first.latitude, closeTo(37.500, 1e-9));
    expect(route.points.first.longitude, closeTo(127.000, 1e-9));
    expect(route.points.last.latitude, closeTo(37.5001, 1e-9));
    expect(route.points.last.longitude, closeTo(127.0012, 1e-9));
  });

  test('연결되지 않은 노드는 null을 반환한다', () {
    final graph = FloorGraph(
      nodes: [
        GraphNode(id: 'A', type: 'corridor', xM: 0, yM: 0),
        GraphNode(id: 'B', type: 'corridor', xM: 10, yM: 0),
      ],
      edges: const [],
    );

    expect(computeShortestRoute(graph, 'A', 'B'), isNull);
  });

  test('그래프에 없는 노드 ID는 ArgumentError다', () {
    final graph = FloorGraph(
      nodes: [GraphNode(id: 'A', type: 'corridor', xM: 0, yM: 0)],
      edges: const [],
    );

    expect(
      () => computeShortestRoute(graph, 'A', 'missing'),
      throwsArgumentError,
    );
  });
}
