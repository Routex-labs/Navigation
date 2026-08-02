import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/models/building.dart';
import 'package:navigation_client/models/discovery_result.dart';
import 'package:navigation_client/models/poi_search_result.dart';
import 'package:navigation_client/repositories/building_repository.dart';
import 'package:navigation_client/repositories/destination_repository.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/search_panel.dart';

void main() {
  group('highlightedNameSpans', () {
    test('검색어와 일치하는 구간만 강조하고 나머지는 원문 그대로 둔다', () {
      final spans = highlightedNameSpans('죠죠 더현대서울점', '더현대서울');

      expect(spans.map((span) => span.text).toList(), [
        '죠죠 ',
        '더현대서울',
        '점',
      ]);
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

    Widget buildSubject() => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: SearchPanel(
            buildingId: 'building-1',
            query: '나이키',
            submitTick: 0,
            onStorePicked: (_) {},
            onBuildingPicked: (_) {},
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
  });
}

PoiSearchResult _result({required String? subcategory, required String? category}) =>
    PoiSearchResult(
      name: '나이키 강남',
      floor: '3F',
      point: const LatLng(37.5, 127.0),
      placeId: 'place-1',
      nodeId: 'node-1',
      category: category,
      subcategory: subcategory,
    );

class _FakeDestinationRepository implements DestinationRepository {
  _FakeDestinationRepository(this.results);

  final List<PoiSearchResult> results;

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
  }) async => DiscoveryResult(mode: DiscoveryMode.noMatch, query: query);
}

/// 이 화면이 실제로 부르는 것은 `getAllBuildings` 하나뿐이다. 나머지는
/// [noSuchMethod]로 열어 둬 인터페이스가 늘어도 이 테스트가 깨지지 않게 한다.
class _FakeBuildingRepository implements BuildingRepository {
  @override
  Future<List<Building>> getAllBuildings() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
