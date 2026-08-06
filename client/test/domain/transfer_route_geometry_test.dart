import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/transfer_route_geometry.dart';
import 'package:navigation_client/models/building_graph.dart';
import 'package:navigation_client/models/floor_graph.dart';
import 'package:navigation_client/models/floor_plan.dart';
import 'package:navigation_client/models/indoor_route.dart';

void main() {
  test('탑승 노드와 가장 가까운 실제 에스컬레이터의 긴 축을 점선 경로로 쓴다', () {
    const routeEnd = LatLng(37.0, 127.00001);
    const segment = IndoorRouteSegment(
      floorId: 'floor-1',
      floorName: '1F',
      route: IndoorRoute(points: [routeEnd], distanceMeters: 0),
      transferModeToNext: 'escalator',
      transferFromNodeId: 'boarding',
      transferToNodeId: 'arrival',
    );
    const graph = FloorGraph(
      nodes: [GraphNode(id: 'boarding', type: 'escalator', xM: 1, yM: 0)],
      edges: [],
    );
    const near = StorePolygon(
      id: 'near',
      name: '에스컬레이터',
      subcategory: '에스컬레이터',
      entranceNodeId: 'unrelated-junction',
      centroid: LatLng(37.00005, 127.00001),
      polygon: [
        LatLng(37.0, 127.0),
        LatLng(37.0, 127.00002),
        LatLng(37.0001, 127.00002),
        LatLng(37.0001, 127.0),
      ],
      polygonLocalM: [
        LocalFloorPoint(0, 0),
        LocalFloorPoint(2, 0),
        LocalFloorPoint(2, 10),
        LocalFloorPoint(0, 10),
      ],
    );
    const far = StorePolygon(
      id: 'far',
      name: '옆 에스컬레이터',
      subcategory: '에스컬레이터',
      centroid: LatLng(37.00005, 127.00101),
      polygon: [
        LatLng(37.0, 127.001),
        LatLng(37.0, 127.00102),
        LatLng(37.0001, 127.00102),
        LatLng(37.0001, 127.001),
      ],
      polygonLocalM: [
        LocalFloorPoint(10, 0),
        LocalFloorPoint(12, 0),
        LocalFloorPoint(12, 10),
        LocalFloorPoint(10, 10),
      ],
    );

    final points = transferRoutePointsOnFloor(
      segment,
      const FloorPlan(stores: [far, near], pois: []),
      graph,
    );

    expect(points.first, routeEnd, reason: '보행 경로 끝과 전환 점선이 끊기면 안 된다');
    expect(points, hasLength(2));
    expect(points[0].longitude, closeTo(127.00001, 0.000001));
    expect(points[1].longitude, closeTo(127.00001, 0.000001));
    expect(points[1].latitude, greaterThan(points[0].latitude));
  });

  test('에스컬레이터가 아니거나 도형 매칭 정보가 없으면 그래프 전이선으로 폴백한다', () {
    const fallback = [LatLng(37, 127), LatLng(37.001, 127.001)];
    const segment = IndoorRouteSegment(
      floorId: 'floor-1',
      floorName: '1F',
      route: IndoorRoute(points: [], distanceMeters: 0),
      transferModeToNext: 'elevator',
      transferFromNodeId: 'boarding',
      transferPointsToNext: fallback,
    );

    expect(
      transferRoutePointsOnFloor(
        segment,
        const FloorPlan(pois: []),
        const FloorGraph(nodes: [], edges: []),
      ),
      fallback,
    );
  });
}
