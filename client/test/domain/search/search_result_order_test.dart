import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/route/dijkstra.dart';
import 'package:navigation_client/domain/search/search_result_order.dart';
import 'package:navigation_client/domain/search/store_suggestions.dart';
import 'package:navigation_client/models/place/poi_search_result.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';

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

/// 후보 정렬용. [nodeId]가 null이면 거리를 알 수 없는 매장이다.
StoreIndexEntry _entry(String name, String floor, String? nodeId) =>
    StoreIndexEntry(
      id: 'PO-$name-$floor',
      name: name,
      floorId: 'FL-$floor',
      floorName: floor,
      entranceNodeId: nodeId,
    );

List<String> _names(List<PoiSearchResult> results) =>
    results.map((r) => r.name).toList();

void main() {
  group('sortedSearchResults', () {
    test('출발 위치가 있으면 보행 거리 오름차순으로 세운다', () {
      // Given: 입력 순서와 거리 순서가 어긋난 결과 3건
      final results = [
        _store('먼 매장', nodeId: 'n-far'),
        _store('가까운 매장', nodeId: 'n-near'),
        _store('중간 매장', nodeId: 'n-mid'),
      ];

      // When
      final sorted = sortedSearchResults(
        results: results,
        reachByNodeId: {
          'n-far': _reach(120),
          'n-near': _reach(8),
          'n-mid': _reach(45),
        },
        fromSemantic: false,
        order: SearchSortOrder.nearest,
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
      sortedSearchResults(
        results: results,
        reachByNodeId: {'n-far': _reach(120), 'n-near': _reach(8)},
        fromSemantic: false,
        order: SearchSortOrder.nearest,
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
          sortedSearchResults(
            results: results,
            reachByNodeId: null,
            fromSemantic: false,
            order: SearchSortOrder.nearest,
          ),
        ),
        ['나중 매장', '먼저 매장'],
      );

      // When / Then: 빈 맵 (reachableFrom을 못 돌린 것과 같은 상태)
      expect(
        _names(
          sortedSearchResults(
            results: results,
            reachByNodeId: const {},
            fromSemantic: false,
            order: SearchSortOrder.nearest,
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
      final sorted = sortedSearchResults(
        results: results,
        reachByNodeId: {'n-far': _reach(120), 'n-near': _reach(8)},
        fromSemantic: false,
        order: SearchSortOrder.nearest,
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
      final sorted = sortedSearchResults(
        results: results,
        reachByNodeId: {'n-far': _reach(120), 'n-near': _reach(8)},
        fromSemantic: false,
        order: SearchSortOrder.nearest,
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
      final sorted = sortedSearchResults(
        results: results,
        reachByNodeId: {'n-far': _reach(120), 'n-near': _reach(8)},
        fromSemantic: true,
        order: SearchSortOrder.nearest,
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
      final first = sortedSearchResults(
        results: results,
        reachByNodeId: reachByNodeId,
        fromSemantic: false,
        order: SearchSortOrder.nearest,
      );
      final second = sortedSearchResults(
        results: results,
        reachByNodeId: reachByNodeId,
        fromSemantic: false,
        order: SearchSortOrder.nearest,
      );

      // Then: 동점 구간이 입력 순서 그대로이고, 두 호출 결과가 같다
      expect(_names(first), expected);
      expect(_names(second), expected);
    });

    test('빈 목록은 빈 목록이다', () {
      expect(
        sortedSearchResults(
          results: const [],
          reachByNodeId: {'n-a': _reach(5)},
          fromSemantic: false,
          order: SearchSortOrder.nearest,
        ),
        isEmpty,
      );
    });

    // P. 사용자가 「이름 맞춤 순」을 고르면 거리를 알아도 세우지 않는다.
    test('bestMatch를 고르면 거리를 알아도 순서를 바꾸지 않는다', () {
      final results = [
        _store('먼 매장', nodeId: 'n-far'),
        _store('가까운 매장', nodeId: 'n-near'),
      ];

      final sorted = sortedSearchResults(
        results: results,
        reachByNodeId: {'n-far': _reach(120), 'n-near': _reach(8)},
        fromSemantic: false,
        order: SearchSortOrder.bestMatch,
      );

      expect(_names(sorted), ['먼 매장', '가까운 매장']);
      // 사본조차 만들지 않는다 — "손대지 않았다"를 가장 분명하게 표현하는 방법.
      expect(identical(sorted, results), isTrue);
    });
  });

  // 설계와 검증 기준은 `docs/client/search-result-list-ux.md` P절이 단일 출처다.
  group('P. 정렬 컨트롤을 띄울지 / 무엇을 기본으로 할지', () {
    test('거리를 아무도 모르면 가까운 순을 고를 수 없다', () {
      expect(canSortByNearest(null), isFalse);
      expect(canSortByNearest(const {}), isFalse);
      expect(canSortByNearest({'n-a': _reach(5)}), isTrue);
    });

    test('결과가 1건 이하면 컨트롤을 띄우지 않는다', () {
      expect(canChooseSortOrder(itemCount: 0, fromSemantic: false), isFalse);
      expect(canChooseSortOrder(itemCount: 1, fromSemantic: false), isFalse);
      expect(canChooseSortOrder(itemCount: 2, fromSemantic: false), isTrue);
    });

    // 유사도순은 사용자가 고를 수 있는 축이 아니다.
    test('의미 검색 결과에는 컨트롤을 띄우지 않는다', () {
      expect(canChooseSortOrder(itemCount: 5, fromSemantic: true), isFalse);
    });

    test('기본은 위치를 알면 가까운 순, 모르면 이름 맞춤 순이다', () {
      expect(defaultSortOrder({'n-a': _reach(5)}), SearchSortOrder.nearest);
      expect(defaultSortOrder(null), SearchSortOrder.bestMatch);
      expect(defaultSortOrder(const {}), SearchSortOrder.bestMatch);
    });
  });

  group('sortedSuggestions', () {
    // 후보 한 줄이 여러 매장(화장실 19곳)일 때, 정렬 기준은 화면에 적히는 값과
    // 같아야 한다 — 대표(최근접)의 거리다. 다른 값으로 세우면 화면의 숫자가
    // 오름차순이 아닌 목록이 나온다.
    test('묶인 후보는 대표(최근접)의 거리로 세운다', () {
      final restrooms = (
        stores: [_entry('화장실', '6F', 'n-6f'), _entry('화장실', 'B2', 'n-b2')],
        kind: SuggestionKind.prefix,
      );
      final cafe = (
        stores: [_entry('카페', '3F', 'n-3f')],
        kind: SuggestionKind.prefix,
      );

      final sorted = sortedSuggestions(
        suggestions: [cafe, restrooms],
        reachByNodeId: {
          'n-6f': _reach(400),
          'n-b2': _reach(20),
          'n-3f': _reach(90),
        },
        order: SearchSortOrder.nearest,
      );

      // 6F(400m)만 봤다면 카페가 1위였을 것이다. 대표는 B2(20m)다.
      expect(sorted.first.stores.first.name, '화장실');
    });

    test('bestMatch면 매칭 품질순 그대로 둔다', () {
      final suggestions = [
        (stores: [_entry('타임', '3F', 'n-far')], kind: SuggestionKind.prefix),
        (stores: [_entry('타임옴므', '3F', 'n-near')], kind: SuggestionKind.prefix),
      ];

      final sorted = sortedSuggestions(
        suggestions: suggestions,
        reachByNodeId: {'n-far': _reach(300), 'n-near': _reach(10)},
        order: SearchSortOrder.bestMatch,
      );

      expect(identical(sorted, suggestions), isTrue);
    });

    test('위치를 모르면 순서를 바꾸지 않는다', () {
      final suggestions = [
        (stores: [_entry('타임', '3F', 'n-a')], kind: SuggestionKind.prefix),
      ];

      expect(
        identical(
          sortedSuggestions(
            suggestions: suggestions,
            reachByNodeId: null,
            order: SearchSortOrder.nearest,
          ),
          suggestions,
        ),
        isTrue,
      );
    });

    // 그룹 전원이 도달 불가인 후보. 거리를 0이나 무한대로 치면 맨 앞이나 맨
    // 뒤로 가는데 둘 다 거짓이다 — 정렬에서 빼고 끝에 붙인다.
    test('거리를 모르는 후보는 목록 끝에 원래 순서로 붙는다', () {
      final unknownA = (
        stores: [_entry('모름A', '1F', null)],
        kind: SuggestionKind.prefix,
      );
      final unknownB = (
        stores: [_entry('모름B', '2F', null)],
        kind: SuggestionKind.prefix,
      );
      final known = (
        stores: [_entry('알수있음', '3F', 'n-k')],
        kind: SuggestionKind.prefix,
      );

      final sorted = sortedSuggestions(
        suggestions: [unknownA, unknownB, known],
        reachByNodeId: {'n-k': _reach(50)},
        order: SearchSortOrder.nearest,
      );

      expect(
        [for (final s in sorted) s.stores.first.name],
        ['알수있음', '모름A', '모름B'],
      );
    });

    test('거리가 같으면 입력 순서를 유지하고 매 호출 같다', () {
      final suggestions = [
        for (var i = 0; i < 40; i++)
          (stores: [_entry('가게$i', '1F', 'n-$i')], kind: SuggestionKind.prefix),
      ];
      final reach = {for (var i = 0; i < 40; i++) 'n-$i': _reach(100)};
      final expected = [for (var i = 0; i < 40; i++) '가게$i'];

      for (var attempt = 0; attempt < 5; attempt++) {
        final sorted = sortedSuggestions(
          suggestions: suggestions,
          reachByNodeId: reach,
          order: SearchSortOrder.nearest,
        );
        expect([for (final s in sorted) s.stores.first.name], expected);
      }
    });
  });
}
