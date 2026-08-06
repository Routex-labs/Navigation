import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/multi_floor_router.dart';
import 'package:navigation_client/models/building_graph.dart';
import 'package:navigation_client/models/floor_graph.dart';

GraphNode _node(String id, String floor, double x, double y) =>
    GraphNode(id: id, type: 'junction', xM: x, yM: y, floorId: floor);

// length = 실제 수평 거리, cost = 다익스트라 가중치. 층 내부 간선은 둘이 같고,
// 수직 전이 간선만 갈린다(탑승구~하차구 20m를 걷지만 부담은 탑승 시간 25m 등가).
GraphEdge _edge(
  String id,
  String from,
  String to,
  double length, {
  double? cost,
  String? transferMode,
  bool bidirectional = true,
}) => GraphEdge(
  id: id,
  fromNodeId: from,
  toNodeId: to,
  lengthM: length,
  costM: cost,
  bidirectional: bidirectional,
  geometryLocalM: const [],
  transferMode: transferMode,
);

void main() {
  test('같은 방향 에스컬레이터가 붙어 있으면 현재 위치에서 가까운 전이를 고른다', () {
    final graph = BuildingGraph(
      buildingId: 'building',
      vertical: 'auto',
      floorNamesById: const {'f1': '1F', 'f2': '2F'},
      nodes: [
        _node('start', 'f1', 0, 0),
        _node('near-boarding', 'f1', 2, 0),
        _node('far-boarding', 'f1', 10, 0),
        _node('near-arrival', 'f2', 2, 2),
        _node('far-arrival', 'f2', 10, 2),
        _node('end', 'f2', 6, 6),
      ],
      edges: [
        _edge('walk-near', 'start', 'near-boarding', 2),
        _edge('walk-far', 'start', 'far-boarding', 10),
        _edge(
          'near-up',
          'near-boarding',
          'near-arrival',
          20,
          cost: 25,
          transferMode: 'escalator',
          bidirectional: false,
        ),
        _edge(
          'far-up',
          'far-boarding',
          'far-arrival',
          20,
          cost: 25,
          transferMode: 'escalator',
          bidirectional: false,
        ),
        _edge('near-to-end', 'near-arrival', 'end', 6),
        _edge('far-to-end', 'far-arrival', 'end', 6),
      ],
    );

    final route = computeMultiFloorRoute(graph, 'start', 'end');

    expect(route, isNotNull);
    expect(route!.segments.first.transferEdgeId, 'near-up');
    expect(route.segments.first.transferFromNodeId, 'near-boarding');
    expect(route.segments.first.transferToNodeId, 'near-arrival');
  });

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
          cost: 25,
          transferMode: 'escalator',
        ),
        _edge('walk-2', 'arrival', 'end', 7),
      ],
    );

    final route = computeMultiFloorRoute(graph, 'start', 'end');

    expect(route, isNotNull);
    expect(route!.segments, hasLength(2));
    // 거리는 실거리 합(10+20+7), 비용은 탑승 비용이 들어간 합(10+25+7).
    expect(route.totalDistanceMeters, 37);
    expect(route.totalCostMeters, 42);
    expect(route.segments.first.route.distanceMeters, 10);
    expect(route.segments.first.transferModeToNext, 'escalator');
    expect(route.segments.first.transferDistanceMeters, 20);
    expect(route.segments.first.transferCostMeters, 25);
    expect(route.segments.first.transferEdgeId, 'escalator');
    expect(route.segments.first.transferFromNodeId, 'boarding');
    expect(route.segments.first.transferToNodeId, 'arrival');
    expect(route.segments.first.transferPointsToNext, hasLength(2));
    expect(route.segments.last.route.distanceMeters, 7);
    expect(route.segments.last.route.pointsLocalM.first.x, 2);
    expect(route.segments.last.route.pointsLocalM.first.y, 2);
    expect(route.segments.last.transferPointsToNext, isEmpty);
  });

  // 중간층 보행 가중치: B1→2F에서 실제로 관측된 배치를 그대로 옮긴 케이스.
  //
  // 1F에서 뱅크를 갈아타면 층을 20m 가로질러야 한다. **거리 합만 보면 이게 짧다**
  //   갈아타기: 5 + 20 + 20 + 20 + 5 = 70m
  //   같은 뱅크: 25 + 20 +  2 + 20 + 5 = 72m
  // 중간층 보행에 1.5배를 매기면 갈아타기가 80m가 되어 뒤집힌다. 사용자는 중간층을
  // 헤매는 대신 출발층에서 20m 더 걷는 쪽을 원하므로, +2m를 내고 후자를 고른다.
  BuildingGraph bankChoiceGraph() => BuildingGraph(
    buildingId: 'building',
    vertical: 'auto',
    floorNamesById: const {'b1': 'B1', 'f1': '1F', 'f2': '2F'},
    nodes: [
      _node('start', 'b1', 0, 0),
      _node('es1-board-b1', 'b1', 5, 0), // 가까운 뱅크지만 1F에서 갈아타야 한다
      _node('es2-board-b1', 'b1', 25, 0), // 조금 먼 뱅크, 1F에서 직행
      _node('es1-arrive-f1', 'f1', 5, 0),
      _node('es2-arrive-f1', 'f1', 25, 0),
      _node('es2-board-f1', 'f1', 27, 0), // 같은 뱅크 연결(하차구 바로 옆)
      _node('es2-arrive-f2', 'f2', 27, 0),
      _node('end', 'f2', 27, 5),
    ],
    edges: [
      _edge('b1-walk-es1', 'start', 'es1-board-b1', 5),
      _edge('b1-walk-es2', 'start', 'es2-board-b1', 25),
      _edge(
        'es1-up',
        'es1-board-b1',
        'es1-arrive-f1',
        20,
        transferMode: 'escalator',
      ),
      _edge(
        'es2-up-1',
        'es2-board-b1',
        'es2-arrive-f1',
        20,
        transferMode: 'escalator',
      ),
      // 1F에서 뱅크를 갈아타려면 층을 가로질러야 한다.
      _edge('f1-cross', 'es1-arrive-f1', 'es2-board-f1', 20),
      // 같은 뱅크는 하차구에서 다음 탑승구가 바로 옆이다.
      _edge('f1-same-bank', 'es2-arrive-f1', 'es2-board-f1', 2),
      _edge(
        'es2-up-2',
        'es2-board-f1',
        'es2-arrive-f2',
        20,
        transferMode: 'escalator',
      ),
      _edge('f2-walk', 'es2-arrive-f2', 'end', 5),
    ],
  );

  test('중간층을 가로지르는 대신 출발층에서 더 걸어 같은 에스컬레이터로 직행한다', () {
    final route = computeMultiFloorRoute(bankChoiceGraph(), 'start', 'end');

    expect(route, isNotNull);
    final boarding = route!.segments
        .map((segment) => segment.transferModeToNext)
        .where((mode) => mode != null);
    expect(boarding, hasLength(2), reason: '두 번 탑승해 2F까지 올라간다');
    // 출발층에서 25m 걸어 먼 뱅크를 탄다(가까운 뱅크는 5m).
    expect(route.segments.first.route.distanceMeters, 25);
    // 1F 세그먼트는 같은 뱅크 연결 2m뿐 — 층을 가로지르는 20m가 아니다.
    expect(route.segments[1].route.distanceMeters, 2);
  });

  // 중간층 가중치가 수단 선택을 뒤집지 못하게 하는 가드.
  //
  // 엘리베이터도 샤프트가 전 층을 서비스하지 않으면 중간층에서 갈아타며 걷는다.
  // 그 보행까지 비싸게 매기면 긴 이동이 에스컬레이터 연속 탑승으로 뒤집힌다
  // (실측에서 6F→B4가 엘리베이터 3회 → 에스컬레이터 9회가 됐다). 층수에 따른
  // 수단 선택은 백엔드 비용 상수의 소관이므로 여기서 건드리지 않는다.
  test('엘리베이터가 최단인 경로는 중간층 가중치로 뒤집지 않는다', () {
    final graph = BuildingGraph(
      buildingId: 'building',
      vertical: 'auto',
      floorNamesById: const {'b1': 'B1', 'f1': '1F', 'f2': '2F'},
      nodes: [
        _node('start', 'b1', 0, 0),
        _node('ev-board-b1', 'b1', 5, 0),
        _node('es-board-b1', 'b1', 25, 0),
        _node('ev-arrive-f1', 'f1', 5, 0),
        _node('ev-board-f1', 'f1', 35, 0), // 다른 샤프트 — 1F에서 30m 걸어야 한다
        _node('es-arrive-f1', 'f1', 25, 0),
        _node('es-board-f1', 'f1', 27, 0),
        _node('ev-arrive-f2', 'f2', 35, 0),
        _node('es-arrive-f2', 'f2', 27, 0),
        _node('end', 'f2', 35, 5),
      ],
      edges: [
        _edge('b1-walk-ev', 'start', 'ev-board-b1', 5),
        _edge('b1-walk-es', 'start', 'es-board-b1', 25),
        _edge(
          'ev-1',
          'ev-board-b1',
          'ev-arrive-f1',
          15,
          transferMode: 'elevator',
        ),
        _edge('f1-ev-cross', 'ev-arrive-f1', 'ev-board-f1', 30),
        _edge(
          'ev-2',
          'ev-board-f1',
          'ev-arrive-f2',
          15,
          transferMode: 'elevator',
        ),
        _edge(
          'es-1',
          'es-board-b1',
          'es-arrive-f1',
          20,
          transferMode: 'escalator',
        ),
        _edge('f1-same-bank', 'es-arrive-f1', 'es-board-f1', 2),
        _edge(
          'es-2',
          'es-board-f1',
          'es-arrive-f2',
          20,
          transferMode: 'escalator',
        ),
        _edge('f2-walk-es', 'es-arrive-f2', 'end', 8),
        _edge('f2-walk-ev', 'ev-arrive-f2', 'end', 5),
      ],
    );

    final route = computeMultiFloorRoute(graph, 'start', 'end');

    // 실거리: 엘리베이터 5+15+30+15+5 = 70, 에스컬레이터 25+20+2+20+8 = 75.
    // 가중치를 그대로 적용하면 엘리베이터가 85가 되어 뒤집히지만, 가드가 막는다.
    expect(route!.totalDistanceMeters, 70);
    expect(route.segments.first.transferModeToNext, 'elevator');
  });

  // 이 회귀가 실제 증상이었다: 엘리베이터 탑승 1회가 "남은 거리 65m"로 표시됐다.
  // 실제 수평 이동은 샤프트 오프셋 1m뿐이다.
  test('엘리베이터 대기·탑승 비용이 표시 거리로 새지 않는다', () {
    final graph = BuildingGraph(
      buildingId: 'building',
      vertical: 'auto',
      floorNamesById: const {'b1': 'B1', 'f1': '1F'},
      nodes: [
        _node('start', 'b1', 0, 0),
        _node('ev-b1', 'b1', 10, 0),
        _node('ev-f1', 'f1', 10, 1),
        _node('end', 'f1', 10, 6),
      ],
      edges: [
        _edge('walk-b1', 'start', 'ev-b1', 10),
        // 실데이터와 같은 값: 수평 오프셋 1m, 비용 65m(대기 40초 + 승하차 10초 + 1층).
        _edge('ev', 'ev-b1', 'ev-f1', 1, cost: 65, transferMode: 'elevator'),
        _edge('walk-f1', 'ev-f1', 'end', 5),
      ],
    );

    final route = computeMultiFloorRoute(graph, 'start', 'end');

    // 걸어야 하는 거리는 10 + 1 + 5 = 16m.
    expect(route!.totalDistanceMeters, 16);
    // 소요 시간 추정에는 대기·탑승이 들어간다: 10 + 65 + 5 = 80m 등가.
    expect(route.totalCostMeters, 80);
    expect(route.segments.first.transferDistanceMeters, 1);
    expect(route.segments.first.transferCostMeters, 65);
  });

  test('ETA용 거리는 가중치가 아니라 실거리로 남는다', () {
    final route = computeMultiFloorRoute(bankChoiceGraph(), 'start', 'end');

    // 25(B1) + 20(탑승) + 2(1F) + 20(탑승) + 5(2F) = 72. 중간층 보행 2m에
    // 가중치가 곱해진 값(3m)이 아니다. 거리 합 최소인 70m 경로를 일부러 버린
    // 결과이므로, 이 값이 70이면 가중치가 적용되지 않은 것이다.
    expect(route!.totalDistanceMeters, 72);
  });
}
