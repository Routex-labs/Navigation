import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/domain/dijkstra.dart';
import 'package:navigation_client/models/building.dart';
import 'package:navigation_client/models/discovery_result.dart';
import 'package:navigation_client/models/poi_search_result.dart';
import 'package:navigation_client/repositories/building_repository.dart';
import 'package:navigation_client/repositories/destination_repository.dart';
import 'package:navigation_client/state/recent_searches_controller.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/reach_label.dart';
import 'package:navigation_client/widgets/search_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('highlightedNameSpans', () {
    test('검색어와 일치하는 구간만 강조하고 나머지는 원문 그대로 둔다', () {
      final spans = highlightedNameSpans('죠죠 더현대서울점', '더현대서울');

      expect(spans.map((span) => span.text).toList(), ['죠죠 ', '더현대서울', '점']);
      expect(spans[0].style?.color, isNull);
      expect(spans[1].style?.color, AppColors.primary);
      expect(spans[2].style?.color, isNull);
    });

    test('대소문자는 무시하되 원문의 표기는 보존한다', () {
      final spans = highlightedNameSpans('EQL 더현대서울점', 'eql');

      expect(spans.first.text, 'EQL');
      expect(spans.first.style?.color, AppColors.primary);
    });

    test('여러 번 나오면 모두 강조한다', () {
      final spans = highlightedNameSpans('나이키 나이키키즈', '나이키');

      final highlighted = spans
          .where((span) => span.style?.color == AppColors.primary)
          .map((span) => span.text)
          .toList();
      expect(highlighted, ['나이키', '나이키']);
    });

    // 의미 검색("밥 먹을 곳" → "정돈프리미엄")은 이름에 검색어가 없는 결과를
    // 돌려주는 것이 목적이다. 강조가 하나도 안 걸리는 것이 정상 상태이므로
    // 원문 한 덩어리를 그대로 돌려줘야 한다.
    test('일치하는 구간이 없으면 강조 없이 원문 한 덩어리를 돌려준다', () {
      final spans = highlightedNameSpans('정돈프리미엄', '밥 먹을 곳');

      expect(spans.length, 1);
      expect(spans.single.text, '정돈프리미엄');
      expect(spans.single.style, isNull);
    });

    test('검색어가 비어 있으면 원문 한 덩어리를 돌려준다', () {
      final spans = highlightedNameSpans('나이키', '   ');

      expect(spans.length, 1);
      expect(spans.single.text, '나이키');
    });
  });

  group('검색 결과 한 줄', () {
    late DestinationRepository originalDestination;
    late BuildingRepository originalBuilding;

    setUp(() {
      originalDestination = destinationRepository;
      originalBuilding = buildingRepository;
      buildingRepository = _FakeBuildingRepository();
    });

    tearDown(() {
      destinationRepository = originalDestination;
      buildingRepository = originalBuilding;
    });

    Widget buildSubject({Map<String, NodeReach>? reachByNodeId}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: SearchPanel(
            buildingId: 'building-1',
            query: '나이키',
            submitTick: 0,
            onStorePicked: (_) {},
            onBuildingPicked: (_) {},
            onQueryPicked: (_) {},
            reachByNodeId: reachByNodeId,
          ),
        ),
      ),
    );

    /// 디바운스(300ms)가 끝나고 가짜 응답이 프레임에 반영될 때까지 흘려보낸다.
    Future<void> settleSearch(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
    }

    testWidgets('소분류가 있으면 이름 오른쪽에 업종으로 보여준다', (tester) async {
      destinationRepository = _FakeDestinationRepository([
        _result(subcategory: '여성패션', category: '패션'),
      ]);

      await tester.pumpWidget(buildSubject());
      await settleSearch(tester);

      expect(find.text('여성패션'), findsOneWidget);
      expect(find.text('3F'), findsOneWidget);
    });

    testWidgets('소분류가 없으면 업종이 사라지지 않고 대분류로 떨어진다', (tester) async {
      destinationRepository = _FakeDestinationRepository([
        _result(subcategory: null, category: '패션'),
      ]);

      await tester.pumpWidget(buildSubject());
      await settleSearch(tester);

      expect(find.text('패션'), findsOneWidget);
    });

    testWidgets('대분류도 없으면 업종 자리를 비운다', (tester) async {
      destinationRepository = _FakeDestinationRepository([
        _result(subcategory: null, category: null),
      ]);

      await tester.pumpWidget(buildSubject());
      await settleSearch(tester);

      // 이름과 층은 그대로 나오고, 업종만 없다.
      expect(find.text('3F'), findsOneWidget);
      expect(find.text('패션'), findsNothing);
    });

    // 영어 열거값(restroom 등)은 화면에 그대로 나가면 안 된다. 상세 시트가 쓰는
    // 것과 같은 변환 규칙을 목록도 따라야 한다.
    testWidgets('영어 소분류는 한글 라벨로 바꿔 보여준다', (tester) async {
      destinationRepository = _FakeDestinationRepository([
        _result(subcategory: 'restroom', category: '편의시설'),
      ]);

      await tester.pumpWidget(buildSubject());
      await settleSearch(tester);

      expect(find.text('화장실'), findsOneWidget);
      expect(find.text('restroom'), findsNothing);
    });

    testWidgets('위치를 잡았으면 거리와 도보 시간을 함께 보여준다', (tester) async {
      destinationRepository = _FakeDestinationRepository([
        _result(subcategory: '여성패션', category: '패션'),
      ]);

      await tester.pumpWidget(
        buildSubject(
          reachByNodeId: const {
            'node-1': NodeReach(distanceM: 124.4, costM: 124.4),
          },
        ),
      );
      await settleSearch(tester);

      // 124.4m / 1.2m·s⁻¹ ≈ 104초 → 올림해서 2분.
      expect(find.text('124m · 도보 2분'), findsOneWidget);
    });

    // 위치를 아직 안 잡은 상태가 정상 경로다. 줄마다 "거리 알 수 없음"을
    // 반복하면 목록이 읽히지 않는다.
    testWidgets('위치가 없으면 거리 줄을 아예 그리지 않는다', (tester) async {
      destinationRepository = _FakeDestinationRepository([
        _result(subcategory: '여성패션', category: '패션'),
      ]);

      await tester.pumpWidget(buildSubject());
      await settleSearch(tester);

      expect(find.textContaining('도보'), findsNothing);
      expect(find.text('3F'), findsOneWidget);
    });

    // 그래프가 끊겨 있으면 그 노드는 맵에 키가 없다(reachableFrom 계약).
    testWidgets('도달할 수 없는 매장은 거리 줄이 없다', (tester) async {
      destinationRepository = _FakeDestinationRepository([
        _result(subcategory: '여성패션', category: '패션'),
      ]);

      await tester.pumpWidget(
        buildSubject(
          reachByNodeId: const {'다른-노드': NodeReach(distanceM: 10, costM: 10)},
        ),
      );
      await settleSearch(tester);

      expect(find.textContaining('도보'), findsNothing);
    });
  });

  // 정렬 규칙 자체는 domain/search_result_order.dart의 테스트가 덮는다. 여기서는
  // **패널이 그 규칙을 실제로 태우는지**와, 정렬 뒤에도 추천 이유가 제 매장에
  // 붙어 있는지를 본다.
  group('검색 결과 정렬', () {
    late DestinationRepository originalDestination;
    late BuildingRepository originalBuilding;

    setUp(() {
      originalDestination = destinationRepository;
      originalBuilding = buildingRepository;
      buildingRepository = _FakeBuildingRepository();
    });

    tearDown(() {
      destinationRepository = originalDestination;
      buildingRepository = originalBuilding;
    });

    Widget buildSubject({Map<String, NodeReach>? reachByNodeId}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: SearchPanel(
            buildingId: 'building-1',
            query: '나이키',
            submitTick: 0,
            onStorePicked: (_) {},
            onBuildingPicked: (_) {},
            onQueryPicked: (_) {},
            reachByNodeId: reachByNodeId,
          ),
        ),
      ),
    );

    /// 1차 디바운스(300ms)와 2차 유예(400ms)를 모두 흘려보낸다.
    Future<void> settleSearch(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
    }

    const reach = {
      '노드-먼곳': NodeReach(distanceM: 200, costM: 200),
      '노드-가까운곳': NodeReach(distanceM: 50, costM: 50),
    };

    testWidgets('위치를 잡았으면 가까운 매장이 위로 올라온다', (tester) async {
      // 서버가 준 순서는 먼 곳이 먼저다.
      destinationRepository = _FakeDestinationRepository([
        _store(name: '나이키 라이즈', floor: '5F', nodeId: '노드-먼곳', placeId: '먼곳'),
        _store(name: '나이키 키즈', floor: '3F', nodeId: '노드-가까운곳', placeId: '가까운곳'),
      ]);

      await tester.pumpWidget(buildSubject(reachByNodeId: reach));
      await settleSearch(tester);

      expect(
        tester.getTopLeft(find.text('3F')).dy,
        lessThan(tester.getTopLeft(find.text('5F')).dy),
      );
    });

    // 거리를 아무도 모르는 상태에서 억지로 세우면 "위쪽이 가깝다"는 거짓말이
    // 된다. 서버가 준 순서를 그대로 둔다.
    testWidgets('위치가 없으면 서버가 준 순서를 그대로 둔다', (tester) async {
      destinationRepository = _FakeDestinationRepository([
        _store(name: '나이키 라이즈', floor: '5F', nodeId: '노드-먼곳', placeId: '먼곳'),
        _store(name: '나이키 키즈', floor: '3F', nodeId: '노드-가까운곳', placeId: '가까운곳'),
      ]);

      await tester.pumpWidget(buildSubject());
      await settleSearch(tester);

      expect(
        tester.getTopLeft(find.text('5F')).dy,
        lessThan(tester.getTopLeft(find.text('3F')).dy),
      );
    });

    // 예전에는 추천 이유를 `_discoveryMatches[index]`로 짝지었다. 정렬이 들어오면
    // 이유가 옆 매장에 붙는데, 화면은 멀쩡해 보여서 알아채기 어렵다.
    //
    // 그리고 이 조합은 가정이 아니다 — 이름이 질의로 시작하면 `_fromSemantic`이
    // false가 되어 정렬이 도는데, `_discoveryMatches`는 그대로 차 있다.
    testWidgets('정렬 뒤에도 추천 이유가 제 매장에 붙어 있다', (tester) async {
      destinationRepository = _FakeDestinationRepository(
        const [], // 1차는 빈손 → 2차 의미 검색으로 넘어간다
        discovery: DiscoveryResult(
          mode: DiscoveryMode.results,
          query: '나이키',
          matches: [
            _match(
              name: '나이키 라이즈',
              floor: '5F',
              node: '노드-먼곳',
              id: '먼곳',
              reason: '이유-먼곳',
            ),
            _match(
              name: '나이키 키즈',
              floor: '3F',
              node: '노드-가까운곳',
              id: '가까운곳',
              reason: '이유-가까운곳',
            ),
          ],
        ),
      );

      await tester.pumpWidget(buildSubject(reachByNodeId: reach));
      await settleSearch(tester);

      // 가까운 매장이 위로 올라왔고,
      expect(
        tester.getTopLeft(find.text('이유-가까운곳')).dy,
        lessThan(tester.getTopLeft(find.text('이유-먼곳')).dy),
      );
      // 그 줄의 거리도 가까운 매장의 것이다. 인덱스로 짝지었다면 이유와 거리가
      // 서로 다른 매장의 값이 되어 여기서 걸린다.
      final nearTile = find.ancestor(
        of: find.text('이유-가까운곳'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: nearTile, matching: find.textContaining('50m')),
        findsOneWidget,
      );
    });
  });

  // 스펙은 naver-map-ui-ux-analysis.md의 「J. 검색 빈 상태(idle) 채우기」다.
  // 저장소 규칙 자체는 state/recent_searches_controller_test.dart가 덮고,
  // 여기서는 **패널이 그 값을 실제로 그리고 다시 검색으로 이어 주는지**를 본다.
  group('빈 화면의 최근 검색어', () {
    late RecentSearchesController original;

    /// 최근 검색어를 탭했을 때 상위로 올라온 값. 콜백이 실제로 불렸는지 본다.
    String? picked;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      original = recentSearchesController;
      picked = null;
    });

    tearDown(() => recentSearchesController = original);

    Future<void> useQueries(List<String> queries) async {
      final controller = RecentSearchesController(
        prefs: await SharedPreferences.getInstance(),
      );
      await controller.ready;
      for (final query in queries) {
        await controller.add(query);
      }
      recentSearchesController = controller;
    }

    Widget buildSubject() => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: SearchPanel(
            buildingId: 'building-1',
            // 빈 질의라 검색이 돌지 않고 idle에 머문다.
            query: '',
            submitTick: 0,
            onStorePicked: (_) {},
            onBuildingPicked: (_) {},
            onQueryPicked: (value) => picked = value,
          ),
        ),
      ),
    );

    testWidgets('저장된 검색어가 없으면 예전 안내 문구가 그대로 남는다', (tester) async {
      await useQueries(const []);

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.textContaining('매장 이름을 입력하면'), findsOneWidget);
      expect(find.text('최근 검색어'), findsNothing);
    });

    testWidgets('최근 검색어가 있으면 최신순으로 보여준다', (tester) async {
      await useQueries(const ['화장실', '나이키']);

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('최근 검색어'), findsOneWidget);
      // 나중에 넣은 '나이키'가 위로 온다.
      expect(
        tester.getTopLeft(find.text('나이키')).dy,
        lessThan(tester.getTopLeft(find.text('화장실')).dy),
      );
      // 안내 문구는 자리를 내준다.
      expect(find.textContaining('매장 이름을 입력하면'), findsNothing);
    });

    testWidgets('탭하면 그 검색어로 다시 검색한다', (tester) async {
      await useQueries(const ['나이키']);

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      await tester.tap(find.text('나이키'));

      expect(picked, '나이키');
    });

    testWidgets('개별 삭제하면 그 줄만 사라진다', (tester) async {
      await useQueries(const ['화장실', '나이키']);

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('recent-나이키')),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('나이키'), findsNothing);
      expect(find.text('화장실'), findsOneWidget);
    });

    testWidgets('전체 삭제하면 안내 문구로 돌아간다', (tester) async {
      await useQueries(const ['화장실', '나이키']);

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      await tester.tap(find.text('전체 삭제'));
      await tester.pumpAndSettle();

      expect(find.text('최근 검색어'), findsNothing);
      expect(find.textContaining('매장 이름을 입력하면'), findsOneWidget);
    });
  });

  group('reachLabel', () {
    // 거리는 실제 이동 거리, 시간은 비용 기준이다. 엘리베이터 대기·탑승이
    // 비용에만 들어 있어서, 시간까지 거리로 계산하면 다른 층 매장이 실제보다
    // 가깝게 느껴진다.
    test('거리는 distanceM으로, 시간은 costM으로 계산한다', () {
      final label = reachLabel(const NodeReach(distanceM: 20, costM: 200));

      // 거리 20m는 그대로, 시간은 200m 등가라 200/1.2/60 ≈ 2.8분 → 3분.
      expect(label, '20m · 도보 3분');
    });

    test('아주 가까워도 0분이 아니라 1분으로 올린다', () {
      final label = reachLabel(const NodeReach(distanceM: 3, costM: 3));

      expect(label, '3m · 도보 1분');
    });
  });
}

PoiSearchResult _result({
  required String? subcategory,
  required String? category,
}) => PoiSearchResult(
  name: '나이키 강남',
  floor: '3F',
  point: const LatLng(37.5, 127.0),
  placeId: 'place-1',
  nodeId: 'node-1',
  category: category,
  subcategory: subcategory,
);

/// 정렬 테스트용. 층 이름이 그대로 화면에 나오는 유일한 평문이라, 목록 순서는
/// 이 값의 세로 위치로 잰다(이름은 `Text.rich`라 `find.text`로 못 집는다).
PoiSearchResult _store({
  required String name,
  required String floor,
  required String nodeId,
  required String placeId,
}) => PoiSearchResult(
  name: name,
  floor: floor,
  point: const LatLng(37.5, 127.0),
  placeId: placeId,
  nodeId: nodeId,
);

DiscoveryMatch _match({
  required String name,
  required String floor,
  required String node,
  required String id,
  required String reason,
}) => DiscoveryMatch(
  storeId: id,
  name: name,
  category: '패션',
  subcategory: null,
  floorId: 'floor-$floor',
  floorName: floor,
  entranceNodeId: node,
  point: const LatLng(37.5, 127.0),
  matchedFacets: const {},
  reason: reason,
);

class _FakeDestinationRepository implements DestinationRepository {
  _FakeDestinationRepository(this.results, {this.discovery});

  final List<PoiSearchResult> results;

  /// 2차 의미 검색 응답. 주지 않으면 `no_match`라 1차에서 끝나는 경로만 탄다.
  final DiscoveryResult? discovery;

  @override
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) async => results;

  @override
  Future<DiscoveryResult> searchDestinationsAi(
    String buildingId,
    String query, {
    String? currentFloorId,
    Map<String, List<String>>? selectedFacets,
    bool showAll = false,
  }) async =>
      discovery ?? DiscoveryResult(mode: DiscoveryMode.noMatch, query: query);
}

/// 이 화면이 실제로 부르는 것은 `getAllBuildings` 하나뿐이다. 나머지는
/// [noSuchMethod]로 열어 둬 인터페이스가 늘어도 이 테스트가 깨지지 않게 한다.
class _FakeBuildingRepository implements BuildingRepository {
  @override
  Future<List<Building>> getAllBuildings() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
