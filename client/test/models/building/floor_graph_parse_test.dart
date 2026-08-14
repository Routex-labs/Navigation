import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/models/building/floor_graph.dart';

/// 층 그래프 파싱의 계약 검증.
///
/// **왜 이 파일이 따로 있나.** 간선의 양 끝 노드 키 하나가 어긋나면 여기서
/// 타입 예외가 나고, 호출부(`outdoor_map_screen._fetchFloorGraph`)가 그것을
/// 삼키면 층 도면과 그래프가 **통째로 null**이 된다. 그러면 층 외곽선·카메라
/// fit·매장 탭·검색 포커스가 한꺼번에 죽는데, 화면에는 "지하층이 잘려 보이고
/// 매장을 눌러도 뒤 건물만 반응한다"로만 드러나 원인을 짚을 단서가 없다.
///
/// 실제로 그 일이 있었다 — 백엔드가 ETag를 뽑으려고 `model_dump_json()`을 직접
/// 부르면서 by_alias를 빠뜨려, `/floors/{floor}` 응답만 `from`/`to` 대신 필드명
/// `from_node_id`/`to_node_id`로 나갔다(같은 DTO를 쓰는 `/graph`는 정상이었다).
void main() {
  Map<String, dynamic> edge(Map<String, dynamic> ends) => {
    'id': 'E1',
    ...ends,
    'length_m': 12.5,
    'cost_m': 12.5,
    'bidirectional': true,
    'geometry_local_m': [
      {'x': 0.0, 'y': 0.0},
      {'x': 3.0, 'y': 4.0},
    ],
  };

  group('간선 양 끝 노드 키', () {
    test('계약대로인 from/to를 읽는다', () {
      final parsed = GraphEdge.fromJson(edge({'from': 'A', 'to': 'B'}));
      expect(parsed.fromNodeId, 'A');
      expect(parsed.toNodeId, 'B');
    });

    test('alias가 안 붙은 from_node_id/to_node_id도 읽는다', () {
      // 서버를 고치더라도, 아직 배포되지 않은 구 버전에 붙은 앱이 이것 하나로
      // 통째로 죽으면 안 된다.
      final parsed = GraphEdge.fromJson(
        edge({'from_node_id': 'A', 'to_node_id': 'B'}),
      );
      expect(parsed.fromNodeId, 'A');
      expect(parsed.toNodeId, 'B');
    });

    test('둘 다 없으면 무엇이 없는지 말하는 예외를 낸다', () {
      // 조용한 null 캐스팅 예외("null is not a String")로 끝나면 안 된다 —
      // 이 계약이 또 어긋났을 때 로그만 보고 알 수 있어야 한다.
      expect(
        () => GraphEdge.fromJson(edge({})),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('from'), contains('from_node_id')),
          ),
        ),
      );
    });

    test('나머지 필드는 그대로 실려 온다', () {
      final parsed = GraphEdge.fromJson(
        edge({'from_node_id': 'A', 'to_node_id': 'B'}),
      );
      expect(parsed.lengthM, 12.5);
      expect(parsed.routingCostM, 12.5);
      expect(parsed.bidirectional, isTrue);
      expect(parsed.geometryLocalM, hasLength(2));
    });
  });

  test('그래프 전체가 두 철자 중 무엇으로 와도 간선을 다 싣는다', () {
    for (final ends in [
      {'from': 'A', 'to': 'B'},
      {'from_node_id': 'A', 'to_node_id': 'B'},
    ]) {
      final graph = FloorGraph.fromJson({
        'nodes': [
          {'id': 'A', 'type': 'corridor', 'name': null, 'x_m': 0.0, 'y_m': 0.0},
          {'id': 'B', 'type': 'corridor', 'name': null, 'x_m': 3.0, 'y_m': 4.0},
        ],
        'edges': [edge(ends)],
      });
      expect(graph.nodes, hasLength(2));
      expect(graph.edges, hasLength(1));
      expect(graph.edges.single.fromNodeId, 'A');
    }
  });
}
