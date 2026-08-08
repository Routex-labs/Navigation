import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/dijkstra.dart';
import 'package:navigation_client/domain/search_result_order.dart';
import 'package:navigation_client/models/poi_search_result.dart';

/// 정렬은 이름·좌표를 보지 않으므로 검증에 필요한 `name`·`nodeId`만 다르게 준다.
PoiSearchResult _store(String name, {String? nodeId}) => PoiSearchResult(
  name: name,
  floor: 'B2',
  point: const LatLng(37.5, 127.0),
  nodeId: nodeId,
);

/// `reachableFrom`이 돌려주는 형태. 거리와 비용을 일부러 다르게 둬서, 정렬이
/// 표시값인 `distanceM`을 쓰는지 튜닝값인 `costM`을 쓰는지 구분되게 한다.
NodeReach _reach(double distanceM) =>
    NodeReach(distanceM: distanceM, costM: distanceM * 3);

List<String> _names(List<PoiSearchResult> results) =>
    results.map((r) => r.name).toList();

void main() {
  group('sortedByWalkingDistance', () {
    test('출발 위치가 있으면 보행 거리 오름차순으로 세운다', () {
      // Given: 입력 순서와 거리 순서가 어긋난 결과 3건
      final results = [
        _store('먼 매장', nodeId: 'n-far'),
        _store('가까운 매장', nodeId: 'n-near'),
        _store('중간 매장', nodeId: 'n-mid'),
      ];

      // When
      final sorted = sortedByWalkingDistance(
        results: results,
        reachByNodeId: {
          'n-far': _reach(120),
          'n-near': _reach(8),
          'n-mid': _reach(45),
        },
        fromSemantic: false,
      );

      // Then
      expect(_names(sorted), ['가까운 매장', '중간 매장', '먼 매장']);
    });

    test('입력 목록을 바꾸지 않는다', () {
      // Given
      final results = [
        _store('먼 매장', nodeId: 'n-far'),
        _store('가까운 매장', nodeId: 'n-near'),
      ];

      // When
      sortedByWalkingDistance(
        results: results,
        reachByNodeId: {'n-far': _reach(120), 'n-near': _reach(8)},
        fromSemantic: false,
      );

      // Then: 원본은 그대로여야 호출부가 다른 화면과 목록을 공유해도 안전하다
      expect(_names(results), ['먼 매장', '가까운 매장']);
    });

    // PDR 미시작·측위 실패. 절반만 정렬된 목록이 가장 나쁘다 —
    // 사용자는 위쪽이 가깝다고 읽는데 사실이 아니게 된다.
    test('출발 위치가 없으면 순서를 그대로 둔다', () {
      // Given: 거리를 아는 매장이 하나도 없거나, 맵 자체가 없는 두 경우
      final results = [
        _store('나중 매장', nodeId: 'n-b'),
        _store('먼저 매장', nodeId: 'n-a'),
      ];

      // When / Then: null
      expect(
        _names(
          sortedByWalkingDistance(
            results: results,
            reachByNodeId: null,
            fromSemantic: false,
          ),
        ),
        ['나중 매장', '먼저 매장'],
      );

      // When / Then: 빈 맵 (reachableFrom을 못 돌린 것과 같은 상태)
      expect(
        _names(
          sortedByWalkingDistance(
            results: results,
            reachByNodeId: const {},
            fromSemantic: false,
          ),
        ),
        ['나중 매장', '먼저 매장'],
      );
    });

    // A-2가 이 매장들에 `경로 안내 불가`를 표시한다. 거리를 0으로 치면 맨 앞,
    // 무한대로 치면 "가장 먼 매장"이 되는데 둘 다 거짓이다.
    test('nodeId가 없는 매장은 원래 상대 순서를 유지한 채 끝으로 간다', () {
      // Given: 노드 없는 매장 2건이 목록 앞뒤에 섞여 있다
      final results = [
        _store('노드없음 A'),
        _store('먼 매장', nodeId: 'n-far'),
        _store('노드없음 B'),
        _store('가까운 매장', nodeId: 'n-near'),
      ];

      // When
      final sorted = sortedByWalkingDistance(
        results: results,
        reachByNodeId: {'n-far': _reach(120), 'n-near': _reach(8)},
        fromSemantic: false,
      );

      // Then: 거리 아는 것 먼저, 모르는 것은 뒤에 A→B 순서 그대로
      expect(_names(sorted), ['가까운 매장', '먼 매장', '노드없음 A', '노드없음 B']);
    });

    // 그래프가 끊겨 reachableFrom이 키를 남기지 않은 경우. nodeId가 null인
    // 경우와 같은 취급이어야 한다 — 둘 다 "거리를 모른다"는 같은 사실이다.
    test('도달 불가 매장도 같은 규칙으로 끝으로 간다', () {
      // Given
      final results = [
        _store('끊긴 매장', nodeId: 'n-island'),
        _store('먼 매장', nodeId: 'n-far'),
        _store('노드없음', nodeId: null),
        _store('가까운 매장', nodeId: 'n-near'),
      ];

      // When: reachByNodeId에 n-island 키가 없다
      final sorted = sortedByWalkingDistance(
        results: results,
        reachByNodeId: {'n-far': _reach(120), 'n-near': _reach(8)},
        fromSemantic: false,
      );

      // Then
      expect(_names(sorted), ['가까운 매장', '먼 매장', '끊긴 매장', '노드없음']);
    });

    // /query/ai가 유사도순으로 준 결과다. 거리로 다시 세우면 "뜻이 가장 잘
    // 맞는 매장"이 아래로 내려간다.
    test('의미 검색 결과는 거리를 알아도 순서를 바꾸지 않는다', () {
      // Given: 유사도 1위가 가장 먼 매장인 상황
      final results = [
        _store('유사도 1위 · 먼 매장', nodeId: 'n-far'),
        _store('유사도 2위 · 가까운 매장', nodeId: 'n-near'),
      ];

      // When
      final sorted = sortedByWalkingDistance(
        results: results,
        reachByNodeId: {'n-far': _reach(120), 'n-near': _reach(8)},
        fromSemantic: true,
      );

      // Then
      expect(_names(sorted), ['유사도 1위 · 먼 매장', '유사도 2위 · 가까운 매장']);
    });

    // 같은 노드를 공유하는 인접 매장(푸드코트 한 줄)은 거리가 정확히 같다.
    // Dart의 List.sort는 안정 정렬이 아니라, 인덱스 tie-breaker가 없으면
    // 호출할 때마다 순서가 뒤집힐 수 있다.
    test('거리가 같으면 입력 순서를 유지하고, 매 호출 같은 결과를 준다', () {
      // Given: 같은 노드를 쓰는 동점 매장을 정렬이 흔들릴 만큼 충분히 준다
      // (요소가 적으면 삽입 정렬로 떨어져 불안정성이 드러나지 않는다).
      final results = [
        for (var i = 0; i < 40; i++) _store('동점 $i', nodeId: 'n-shared'),
        _store('가까운 매장', nodeId: 'n-near'),
      ];
      final reachByNodeId = {'n-shared': _reach(60), 'n-near': _reach(8)};
      final expected = ['가까운 매장', for (var i = 0; i < 40; i++) '동점 $i'];

      // When
      final first = sortedByWalkingDistance(
        results: results,
        reachByNodeId: reachByNodeId,
        fromSemantic: false,
      );
      final second = sortedByWalkingDistance(
        results: results,
        reachByNodeId: reachByNodeId,
        fromSemantic: false,
      );

      // Then: 동점 구간이 입력 순서 그대로이고, 두 호출 결과가 같다
      expect(_names(first), expected);
      expect(_names(second), expected);
    });

    test('빈 목록은 빈 목록이다', () {
      expect(
        sortedByWalkingDistance(
          results: const [],
          reachByNodeId: {'n-a': _reach(5)},
          fromSemantic: false,
        ),
        isEmpty,
      );
    });
  });
}
