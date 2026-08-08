import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/domain/dijkstra.dart';
import 'package:navigation_client/models/building.dart';
import 'package:navigation_client/models/discovery_result.dart';
import 'package:navigation_client/models/poi_search_result.dart';
import 'package:navigation_client/models/store_index_entry.dart';
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
            indoorContextActive: true,
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
            indoorContextActive: true,
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
      // 층이 앞에 붙는다 — 근거가 층을 밀어내지 않는다(domain/reason_text.dart).
      expect(
        tester.getTopLeft(find.text('3F · 이유-가까운곳')).dy,
        lessThan(tester.getTopLeft(find.text('5F · 이유-먼곳')).dy),
      );
      // 그 줄의 거리도 가까운 매장의 것이다. 인덱스로 짝지었다면 이유와 거리가
      // 서로 다른 매장의 값이 되어 여기서 걸린다.
      final nearTile = find.ancestor(
        of: find.text('3F · 이유-가까운곳'),
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
            indoorContextActive: true,
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

  // 후보 산출 규칙 자체는 domain/store_suggestions_test.dart가 덮는다. 여기서는
  // **패널이 그 후보를 어느 화면에 띄우는지**와, 목록을 못 받았을 때 검색이
  // 그대로 도는지를 본다(설계: search-input-assist.md K·L절).
  group('자동완성 후보', () {
    late DestinationRepository originalDestination;
    late BuildingRepository originalBuilding;
    String? picked;

    setUp(() {
      originalDestination = destinationRepository;
      originalBuilding = buildingRepository;
      picked = null;
    });

    tearDown(() {
      destinationRepository = originalDestination;
      buildingRepository = originalBuilding;
    });

    Widget buildSubject(String query, {bool indoor = true}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 500,
          child: SearchPanel(
            buildingId: 'building-1',
            query: query,
            submitTick: 0,
            onStorePicked: (_) {},
            onBuildingPicked: (_) {},
            onQueryPicked: (value) => picked = value,
            indoorContextActive: indoor,
          ),
        ),
      ),
    );

    // 디바운스가 끝나기 **전**. 서버는 아직 아무 말도 안 했다.
    Future<void> pumpWhileTyping(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('서버를 기다리는 동안 후보가 먼저 뜬다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('나이키 라이즈', '3F')],
      );
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(buildSubject('나이'));
      await pumpWhileTyping(tester);

      expect(find.text('검색어 제안'), findsOneWidget);
      expect(find.text('3F'), findsOneWidget);
    });

    // 초성은 서버 경량 매칭이 전혀 못 잡는다. 온디바이스 후보만이 답을 낸다.
    testWidgets('초성으로도 후보가 나온다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('나이키 라이즈', '3F')],
      );
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(buildSubject('ㄴㅇㅋ'));
      await pumpWhileTyping(tester);

      expect(find.text('검색어 제안'), findsOneWidget);
    });

    // L이 실제로 값을 내는 자리. 서버가 못 찾은 뒤에도 표기 실수를 잡아 준다.
    testWidgets('서버가 못 찾아도 오타 교정 후보를 되묻는다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('샤넬 뷰티', '1F')],
      );
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(buildSubject('샤낼 뷰티'));
      // 경량(300ms) + 의미(400ms)까지 모두 지나 noMatch가 확정된 뒤.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(find.text('이걸 찾으셨나요?'), findsOneWidget);
      expect(find.text('1F'), findsOneWidget);
    });

    testWidgets('후보를 탭하면 그 이름으로 다시 검색한다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('나이키 라이즈', '3F')],
      );
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(buildSubject('나이'));
      await pumpWhileTyping(tester);
      await tester.tap(find.byKey(const Key('suggestion-PO-나이키 라이즈')));

      // 좌표를 들고 바로 이동하지 않고 이름으로 재검색한다(StoreIndexEntry 주석).
      expect(picked, '나이키 라이즈');
    });

    // **실기기에서 잡은 회귀다.** `apc`는 서버 경량 매칭이 `name LIKE %apc%`라
    // 구두점이 든 `A.P.C.`를 못 잡고 no_match를 준다. 예전에는 그 뒤 의미 검색이
    // 돌아 임계값을 겨우 넘긴 **주차구역**을 "뜻이 비슷한 매장"이라며 확정했다 —
    // 정답이 이미 화면에 떠 있는데 오답으로 갈아치웠다.
    testWidgets('이름이 걸린 후보가 있으면 의미 검색으로 넘어가지 않는다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('A.P.C.', '3F')],
      );
      final repository = _FakeDestinationRepository(
        const [],
        discovery: const DiscoveryResult(
          mode: DiscoveryMode.results,
          query: 'apc',
          matches: [],
        ),
      );
      destinationRepository = repository;

      await tester.pumpWidget(buildSubject('apc'));
      // 경량(300ms) + 의미 유예(400ms)를 모두 지나도
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      // 의미 검색을 아예 부르지 않는다.
      expect(repository.aiCallCount, 0);
      // 후보가 그대로 남아 있다.
      expect(find.text('검색어 제안'), findsOneWidget);
      expect(find.text('3F'), findsOneWidget);
    });

    // 교정 후보만 있을 때는 추측이라 의미 검색에 기회를 준다.
    testWidgets('교정 후보뿐이면 의미 검색으로 넘어간다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('샤넬 뷰티', '1F')],
      );
      final repository = _FakeDestinationRepository(const []);
      destinationRepository = repository;

      await tester.pumpWidget(buildSubject('샤낼 뷰티'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(repository.aiCallCount, 1);
      expect(find.text('이걸 찾으셨나요?'), findsOneWidget);
    });

    // **실기기에서 잡은 회귀다.** 1F에서 3F 매장 후보를 탭하면 그 이름으로 다시
    // 검색하는데, 층 스코프 때문에 1차가 또 빈손이 되어 후보 화면으로 되돌아왔다.
    // 몇 번을 눌러도 매장에 닿지 못한다.
    testWidgets('후보를 탭한 검색은 층으로 좁히지 않는다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('A.P.C.', '3F')],
      );
      final repository = _FakeDestinationRepository(const []);
      destinationRepository = repository;

      // 상위(MapShellScreen)와 같게 배선한다 — 후보를 고르면 검색창 글자를 바꾸고
      // 확정 카운터를 올려 검색을 한 바퀴 더 돌린다. 이 되먹임이 없으면 탭이
      // 만드는 두 번째 검색 자체가 일어나지 않아 검증이 성립하지 않는다.
      final query = ValueNotifier<String>('apc');
      final submitTick = ValueNotifier<int>(0);
      addTearDown(query.dispose);
      addTearDown(submitTick.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: ListenableBuilder(
                listenable: Listenable.merge([query, submitTick]),
                builder: (_, _) => SearchPanel(
                  buildingId: 'building-1',
                  query: query.value,
                  submitTick: submitTick.value,
                  // 지금 1F를 보고 있다.
                  currentFloorId: 'FL-1F',
                  onStorePicked: (_) {},
                  onBuildingPicked: (_) {},
                  onQueryPicked: (value) {
                    query.value = value;
                    submitTick.value++;
                  },
                  indoorContextActive: true,
                ),
              ),
            ),
          ),
        ),
      );
      // 디바운스를 지나 1차 검색이 실제로 나가게 둔다. 그래야 "탭 전에는 층을
      // 실어 보냈다"를 비교할 수 있다.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('suggestion-PO-A.P.C.')));
      await tester.pumpAndSettle();

      expect(query.value, 'A.P.C.');
      expect(repository.floorScopes.length, 2);
      expect(repository.floorScopes.first, 'FL-1F');
      expect(repository.floorScopes.last, isNull);
    });

    // 후보의 원본이 건물 하나의 매장 목록이라, 야외에서 쓰면 지금 서 있는 곳과
    // 무관한 매장을 제안한다. 실기기에서 시청 앞 야외 지도에 더현대서울 3층
    // 매장이 후보로 떠서 잡았다. 야외 장소 검색은 외부 API로 따로 채운다.
    testWidgets('야외에서는 후보를 만들지 않고 원본도 받지 않는다', (tester) async {
      final repository = _FakeBuildingRepository(
        storeIndex: [_entry('A.P.C.', '3F')],
      );
      buildingRepository = repository;
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(buildSubject('apc', indoor: false));
      await pumpWhileTyping(tester);

      expect(find.text('검색어 제안'), findsNothing);
      // 쓰지도 않을 목록을 내려받지 않는다.
      expect(repository.storeIndexCallCount, 0);
    });

    // 자동완성은 부가 기능이다. 원본을 못 받아도 검색을 막아서는 안 된다.
    testWidgets('목록을 못 받으면 후보만 사라지고 검색은 그대로 돈다', (tester) async {
      buildingRepository = _FakeBuildingRepository(storeIndexFails: true);
      destinationRepository = _FakeDestinationRepository([
        _result(subcategory: '여성패션', category: '패션'),
      ]);

      await tester.pumpWidget(buildSubject('나이키'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('검색어 제안'), findsNothing);
      // 서버 결과는 정상적으로 나온다.
      expect(find.text('여성패션'), findsOneWidget);
    });

    // 층마다 있는 시설은 한 줄로 묶여 온다. 몇 곳인지 안 적으면 사용자는
    // "왜 한 층만 나오지"로 읽는다.
    testWidgets('같은 이름 시설은 한 줄로 묶고 몇 곳인지 적는다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [
          _entry('화장실', 'B2'),
          _entry('화장실', 'B1'),
          _entry('화장실', '1F'),
        ],
      );
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(buildSubject('화장실'));
      await pumpWhileTyping(tester);

      expect(find.textContaining('3곳'), findsOneWidget);
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

  /// 의미 검색을 몇 번 불렀는지. "아예 안 불렀다"를 검증하려면 결과가 아니라
  /// 호출 자체를 세야 한다.
  int aiCallCount = 0;

  /// 경량 검색이 받은 층 스코프를 순서대로 기록한다.
  final List<String?> floorScopes = [];

  @override
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) async {
    floorScopes.add(currentFloorId);
    return results;
  }

  @override
  Future<DiscoveryResult> searchDestinationsAi(
    String buildingId,
    String query, {
    String? currentFloorId,
    Map<String, List<String>>? selectedFacets,
    bool showAll = false,
  }) async {
    aiCallCount++;
    return discovery ??
        DiscoveryResult(mode: DiscoveryMode.noMatch, query: query);
  }
}

StoreIndexEntry _entry(String name, String floor) => StoreIndexEntry(
  id: 'PO-$name',
  name: name,
  floorId: 'FL-$floor',
  floorName: floor,
);

/// 이 화면이 실제로 부르는 것은 `getAllBuildings`·`getStoreIndex` 둘뿐이다.
/// 나머지는 [noSuchMethod]로 열어 둬 인터페이스가 늘어도 이 테스트가 깨지지
/// 않게 한다.
class _FakeBuildingRepository implements BuildingRepository {
  _FakeBuildingRepository({this.storeIndex, this.storeIndexFails = false});

  final List<StoreIndexEntry>? storeIndex;

  /// 자동완성 원본을 못 받는 상태. 앱이 죽지 않고 후보만 사라져야 한다.
  final bool storeIndexFails;

  @override
  Future<List<Building>> getAllBuildings() async => const [];

  /// 원본을 몇 번 받아갔는지. 야외에서 "받지 않는다"를 검증하려면 결과가 아니라
  /// 호출 자체를 세야 한다.
  int storeIndexCallCount = 0;

  @override
  Future<List<StoreIndexEntry>?> getStoreIndex(String buildingId) async {
    storeIndexCallCount++;
    if (storeIndexFails) throw Exception('store-index 실패');
    return storeIndex;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
