import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/application/floor_map_matcher.dart';
import 'package:navigation_client/models/floor_graph.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';

FloorGraph _testGraph() => FloorGraph(
  nodes: const [
    GraphNode(id: 'a', type: 'path', xM: 0, yM: 0),
    GraphNode(id: 'b', type: 'path', xM: 10, yM: 0),
    GraphNode(id: 'c', type: 'path', xM: 10, yM: 10),
    GraphNode(id: 'd', type: 'path', xM: 0, yM: 3),
    GraphNode(id: 'e', type: 'path', xM: 10, yM: 3),
  ],
  edges: const [
    GraphEdge(
      id: 'ab',
      fromNodeId: 'a',
      toNodeId: 'b',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(10, 0)],
    ),
    GraphEdge(
      id: 'bc',
      fromNodeId: 'b',
      toNodeId: 'c',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(10, 0), LocalPoint(10, 10)],
    ),
    GraphEdge(
      id: 'de',
      fromNodeId: 'd',
      toNodeId: 'e',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 3), LocalPoint(10, 3)],
    ),
  ],
);

FloorGraph _recoveryGraph() => FloorGraph(
  nodes: const [
    GraphNode(id: 'a', type: 'path', xM: 0, yM: 0),
    GraphNode(id: 'b', type: 'path', xM: 10, yM: 0),
    GraphNode(id: 'c', type: 'junction', xM: 0, yM: 3),
    GraphNode(id: 'd', type: 'corridor', xM: 10, yM: 3),
  ],
  edges: const [
    GraphEdge(
      id: 'ab',
      fromNodeId: 'a',
      toNodeId: 'b',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(10, 0)],
    ),
    GraphEdge(
      id: 'ac',
      fromNodeId: 'a',
      toNodeId: 'c',
      lengthM: 3,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(0, 3)],
    ),
    GraphEdge(
      id: 'cd',
      fromNodeId: 'c',
      toNodeId: 'd',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 3), LocalPoint(10, 3)],
    ),
  ],
);

FloorGraph _accessEdgeGraph() => FloorGraph(
  nodes: const [
    GraphNode(id: 'a', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'j', type: 'junction', xM: 5, yM: 0),
    GraphNode(id: 'b', type: 'corridor', xM: 10, yM: 0),
    GraphNode(id: 'store', type: 'store_entrance', xM: 5, yM: 2),
  ],
  edges: const [
    GraphEdge(
      id: 'aj',
      fromNodeId: 'a',
      toNodeId: 'j',
      lengthM: 5,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(5, 0)],
    ),
    GraphEdge(
      id: 'jb',
      fromNodeId: 'j',
      toNodeId: 'b',
      lengthM: 5,
      bidirectional: true,
      geometryLocalM: [LocalPoint(5, 0), LocalPoint(10, 0)],
    ),
    GraphEdge(
      id: 'store_edge_000',
      fromNodeId: 'store',
      toNodeId: 'j',
      lengthM: 2,
      bidirectional: true,
      geometryLocalM: [LocalPoint(5, 2), LocalPoint(5, 0)],
    ),
  ],
);

void main() {
  group('FloorMapMatcher', () {
    test('PDR 좌표를 가장 가까운 복도 선분으로 투영한다', () {
      final matched = FloorMapMatcher(
        _testGraph(),
      ).match(const PdrLocalPoint(4, 1.2));

      expect(matched, isNotNull);
      expect(matched!.edgeId, 'ab');
      expect(matched.point.eastM, closeTo(4, 1e-9));
      expect(matched.point.northM, closeTo(0, 1e-9));
      expect(matched.distanceToGraphM, closeTo(1.2, 1e-9));
    });

    test('시작점 스냅은 matcher 상태를 만들지 않고 가장 가까운 통로를 고른다', () {
      final matcher = FloorMapMatcher(_testGraph());

      final snapped = matcher.snapToWalkableNetwork(
        const PdrLocalPoint(4, 1.2),
      );

      expect(snapped, isNotNull);
      expect(snapped!.edgeId, 'ab');
      expect(snapped.point, const PdrLocalPoint(4, 0));
      // snap 뒤 첫 PDR 점은 이전 위치 제약 없이 다시 매칭돼야 한다.
      expect(matcher.match(const PdrLocalPoint(10, 4))!.edgeId, 'bc');
    });

    test('분기 뒤에는 다음 graph 간선 위로 자연스럽게 전환한다', () {
      final matcher = FloorMapMatcher(_testGraph());
      final path = matcher.matchPath(const [
        PdrLocalPoint(8, 0.3),
        PdrLocalPoint(10.2, 4),
      ]);

      expect(path.map((point) => point.edgeId), ['ab', 'bc']);
      expect(path.last.point.eastM, closeTo(10, 1e-9));
      expect(path.last.point.northM, closeTo(4, 1e-9));
    });

    test('평행 복도 사이의 작은 센서 흔들림은 직전 간선을 유지한다', () {
      final matcher = FloorMapMatcher(_testGraph());
      final path = matcher.matchPath(const [
        PdrLocalPoint(2, 0.2),
        PdrLocalPoint(4, 1.6),
      ]);

      expect(path.map((point) => point.edgeId), ['ab', 'ab']);
      expect(path.last.point.northM, closeTo(0, 1e-9));
    });

    test('간선 전환은 교차 노드를 경유해 렌더한다', () {
      final matcher = FloorMapMatcher(_testGraph());
      final path = matcher.matchRoutedPath(const [
        PdrLocalPoint(8, 0.3),
        PdrLocalPoint(10.2, 4),
      ]);

      // ab와 bc의 스냅 점만 직선으로 이으면 (8,0)→(10,4)가 되어 복도를
      // 대각선으로 뚫는다. graph junction b=(10,0)를 반드시 포함해야 한다.
      expect(path, contains(const PdrLocalPoint(10, 0)));
      expect(path.last, const PdrLocalPoint(10, 4));
    });

    test('연결되지 않은 가까운 복도로는 순간이동하지 않는다', () {
      final matcher = FloorMapMatcher(_testGraph());
      final path = matcher.matchPath(const [
        PdrLocalPoint(4, 0.1),
        // de가 훨씬 가깝지만 ab와 graph 연결이 없다.
        PdrLocalPoint(4, 3),
      ]);

      expect(path.map((point) => point.edgeId), ['ab', 'ab']);
      expect(path.last.point, const PdrLocalPoint(4, 0));
    });

    test('매장 입구 가지보다 가까운 주 복도에 anchor를 우선 부착한다', () {
      final matched = FloorMapMatcher(
        _accessEdgeGraph(),
      ).snapToWalkableNetwork(const PdrLocalPoint(5, 1.5));

      expect(matched, isNotNull);
      expect(matched!.edgeId, isNot('store_edge_000'));
      expect(matched.point.northM, closeTo(0, 1e-9));
    });

    test('같은 대체 복도 증거가 누적되면 확장된 거리로 재획득한다', () {
      final matcher = FloorMapMatcher(_recoveryGraph());
      final path = matcher.matchPath(const [
        PdrLocalPoint(1, 0.1),
        PdrLocalPoint(2, 1.6),
        PdrLocalPoint(3, 2.2),
        PdrLocalPoint(4, 2.8),
        PdrLocalPoint(5, 3),
      ]);

      expect(path.map((point) => point.state), [
        MapMatchState.tracking,
        MapMatchState.tracking,
        MapMatchState.suspect,
        MapMatchState.suspect,
        MapMatchState.recovered,
      ]);
      expect(path.last.edgeId, 'cd');
      expect(path.last.point, const PdrLocalPoint(5, 3));
    });

    test('복구 전환도 연결 교차점을 경유해 렌더한다', () {
      final path = FloorMapMatcher(_recoveryGraph()).matchRoutedPath(const [
        PdrLocalPoint(1, 0.1),
        PdrLocalPoint(2, 1.6),
        PdrLocalPoint(3, 2.2),
        PdrLocalPoint(4, 2.8),
        PdrLocalPoint(5, 3),
      ]);

      expect(path, contains(const PdrLocalPoint(0, 0)));
      expect(path, contains(const PdrLocalPoint(0, 3)));
      expect(path.last, const PdrLocalPoint(5, 3));
    });

    test('한 번의 이탈 의심 뒤 원래 복도로 돌아오면 복구 증거를 지운다', () {
      final matcher = FloorMapMatcher(_recoveryGraph());
      final path = matcher.matchPath(const [
        PdrLocalPoint(1, 0.1),
        PdrLocalPoint(2, 1.6),
        PdrLocalPoint(3, 2.2),
        PdrLocalPoint(4, 0.2),
        PdrLocalPoint(5, 2.2),
      ]);

      expect(path[2].state, MapMatchState.suspect);
      expect(path[3].state, MapMatchState.tracking);
      expect(path[4].state, MapMatchState.suspect);
      expect(path.last.edgeId, 'ab');
    });

    test('연결되지 않은 복도는 반복해서 가까워도 복구하지 않는다', () {
      final matcher = FloorMapMatcher(_testGraph());
      final path = matcher.matchPath(const [
        PdrLocalPoint(1, 0.1),
        PdrLocalPoint(2, 3),
        PdrLocalPoint(3, 3),
        PdrLocalPoint(4, 3),
        PdrLocalPoint(5, 3),
      ]);

      expect(path.map((point) => point.edgeId).toSet(), {'ab'});
      expect(path.map((point) => point.state).toSet(), {
        MapMatchState.tracking,
      });
    });
  });
}
