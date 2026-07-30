import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/multi_floor_router.dart';
import 'package:navigation_client/models/building_graph.dart';
import 'package:navigation_client/models/floor_graph.dart';

GraphNode _node(String id, String floor, double x, double y) =>
    GraphNode(id: id, type: 'junction', xM: x, yM: y, floorId: floor);

GraphEdge _edge(
  String id,
  String from,
  String to,
  double length, {
  String? transferMode,
}) => GraphEdge(
  id: id,
  fromNodeId: from,
  toNodeId: to,
  lengthM: length,
  bidirectional: true,
  geometryLocalM: const [],
  transferMode: transferMode,
);

void main() {
  test('에스컬레이터 비용과 두 층 끝점을 별도 전환 구간으로 보존한다', () {
    final graph = BuildingGraph(
      buildingId: 'building',
      vertical: 'auto',
      floorNamesById: const {'f1': '1F', 'f2': '2F'},
      nodes: [
        _node('start', 'f1', 0, 0),
        _node('boarding', 'f1', 10, 0),
        _node('arrival', 'f2', 2, 2),
        _node('end', 'f2', 2, 9),
      ],
      edges: [
        _edge('walk-1', 'start', 'boarding', 10),
        _edge(
          'escalator',
          'boarding',
          'arrival',
          20,
          transferMode: 'escalator',
        ),
        _edge('walk-2', 'arrival', 'end', 7),
      ],
    );

    final route = computeMultiFloorRoute(graph, 'start', 'end');

    expect(route, isNotNull);
    expect(route!.segments, hasLength(2));
    expect(route.totalDistanceMeters, 37);
    expect(route.segments.first.route.distanceMeters, 10);
    expect(route.segments.first.transferModeToNext, 'escalator');
    expect(route.segments.first.transferDistanceMeters, 20);
    expect(route.segments.first.transferPointsToNext, hasLength(2));
    expect(route.segments.last.route.distanceMeters, 7);
    expect(route.segments.last.transferPointsToNext, isEmpty);
  });
}
