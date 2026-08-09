import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/domain/dijkstra.dart';
import 'package:navigation_client/models/favorite_place.dart';
import 'package:navigation_client/models/place_detail.dart';
import 'package:navigation_client/models/poi_search_result.dart';
import 'package:navigation_client/repositories/place_detail_repository.dart';
import 'package:navigation_client/state/favorites_controller.dart';
import 'package:navigation_client/widgets/place_detail/korean_line_break.dart';
import 'package:navigation_client/widgets/place_detail_sheet.dart';
import 'package:navigation_client/widgets/sheet_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _favorite = FavoritePlace.fromPoiSearchResult(
  const PoiSearchResult(
    name: '테스트 매장',
    floor: '1F',
    point: LatLng(37.5, 127.0),
    placeId: 'place-1',
    nodeId: 'node-1',
  ),
  buildingId: 'building-1',
);

void main() {
  Widget buildSubject({
    PlaceDetailRepository? repository,
    VoidCallback? onCloseAll,
    String subtitle = '1F',
    String? category,
    String? subcategory,
    FavoritePlace? favorite,
    NodeReach? reach,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PlaceDetailSheet(
          title: '테스트 매장',
          subtitle: subtitle,
          buildingId: 'building-1',
          placeId: 'place-1',
          category: category,
          subcategory: subcategory,
          favorite: favorite,
          reach: reach,
          onCloseAll: onCloseAll ?? () {},
          repository: repository,
        ),
      ),
    );
  }

  testWidgets('상세를 불러오는 동안에도 코어와 길찾기 버튼을 즉시 그린다', (tester) async {
    final completer = Completer<PlaceDetail?>();
    await tester.pumpWidget(
      buildSubject(repository: _FakeRepository(completer.future)),
    );

    expect(find.text('테스트 매장'), findsOneWidget);
    expect(find.text('1F'), findsOneWidget);
    expect(find.text('출발'), findsOneWidget);
    expect(find.text('도착'), findsOneWidget);
    expect(find.byKey(const ValueKey('place-detail-loading')), findsOneWidget);

    completer.complete(_detailWithSummary());
    await tester.pumpAndSettle();

    expect(find.text(keepWordsWhole('상세 섹션')), findsOneWidget);
    expect(find.byKey(const ValueKey('place-detail-loading')), findsNothing);
  });

  // --- 설계 7-A-3·7-A-4 ---

  testWidgets('섹션이 0개여도 길찾기 버튼은 남는다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(Future.value(_detail(sections: const []))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('출발'), findsOneWidget);
    expect(find.text('도착'), findsOneWidget);
  });

  testWidgets('excluded는 섹션이 와도 본문을 그리지 않고 길찾기는 남긴다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(
          Future.value(_detailWithSummary(kind: 'excluded')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(keepWordsWhole('상세 섹션')), findsNothing);
    expect(find.text('출발'), findsOneWidget);
    expect(find.text('도착'), findsOneWidget);
  });

  testWidgets('businessInfo는 라벨과 값을 그린다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(
          Future.value(
            _detail(
              sections: const [
                {
                  'type': 'businessInfo',
                  'items': [
                    {'label': '주소', 'value': '서울특별시 영등포구 여의대로 108'},
                  ],
                },
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('매장 정보'), findsOneWidget);
    expect(find.text('주소'), findsOneWidget);
    expect(find.text(keepWordsWhole('서울특별시 영등포구 여의대로 108')), findsOneWidget);
  });

  // 주소는 페이지 맨 아래로 내려가 소개와 떨어졌다. 둘은 각자 제목을 갖는다.
  testWidgets('소개와 매장 정보는 각각 제 제목을 갖는다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(
          Future.value(
            _detail(
              sections: const [
                {'type': 'summary', 'text': '한 줄 소개'},
                {
                  'type': 'businessInfo',
                  'items': [
                    {'label': '주소', 'value': '여의대로 108'},
                  ],
                },
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('매장 정보'), findsOneWidget);
    expect(find.text('소개'), findsOneWidget);
    expect(find.text(keepWordsWhole('한 줄 소개')), findsOneWidget);
    expect(find.text(keepWordsWhole('여의대로 108')), findsOneWidget);
  });

  // 지도 미리보기가 붙기 전까지 map 섹션은 층 이름만 적힌 중복 블록이다.
  // 그 층은 헤더 배지에 이미 있으므로 본문에 그리지 않는다.
  testWidgets('map 섹션은 본문에 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(
          Future.value(
            _detail(
              sections: const [
                {'type': 'map', 'polygon_local_m': []},
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1F 위치'), findsNothing);
    // 층은 헤더 배지로 여전히 보인다.
    expect(find.text('1F'), findsOneWidget);
  });

  testWidgets('매장 정보가 없어도 소개는 제목을 갖는다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(Future.value(_detailWithSummary())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('소개'), findsOneWidget);
    expect(find.text('매장 정보'), findsNothing);
  });

  // 길찾기는 이름 바로 아래 한 줄에만 있다. 본문이 길어도 중복 없이 하나씩이어야
  // "언제든 길찾기"(F5)를 한 자리에서 지킨다.
  testWidgets('본문이 길어도 길찾기 버튼은 이름 아래 한 벌만 있다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(
          Future.value(
            _detail(
              sections: [
                for (var i = 0; i < 12; i++)
                  {'type': 'summary', 'text': '긴 본문 $i'},
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bar = find.byKey(const ValueKey('place-detail-actions'));
    expect(bar, findsOneWidget);

    // DraggableScrollableSheet는 첫 드래그를 시트 확장에 쓴다. 실제 본문 스크롤은
    // 시트가 maxChildSize에 닿은 뒤부터라서 두 번 끈다.
    final scrollable = find.byType(SingleChildScrollView);
    await tester.drag(scrollable, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.drag(scrollable, const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(bar, findsOneWidget);
    // 상단에 복제본이 없으므로 버튼은 항상 하나씩이다.
    expect(find.text('출발'), findsOneWidget);
    expect(find.text('도착'), findsOneWidget);
  });

  // 이 시트는 스크롤 제스처를 이미 두 가지로 쓴다(위로 끌면 커지고, 끝에서
  // 아래로 끌면 닫힌다). 끝에서 내용이 늘어나는 표시까지 겹치면 "더 볼 게
  // 남았다"는 잘못된 신호가 된다.
  testWidgets('본문 끝에서 늘어나는 overscroll 표시를 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(
          Future.value(
            _detail(
              sections: [
                for (var i = 0; i < 12; i++)
                  {'type': 'summary', 'text': '긴 본문 $i'},
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    expect(find.byType(GlowingOverscrollIndicator), findsNothing);
    // 표시만 끈 것이라 스크롤 자체는 그대로 동작해야 한다.
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  group('현재 위치 기준 거리', () {
    // 목록에 74m라고 적혀 있는데 눌러 들어온 상세가 다른 값을 말하면 어느 쪽도
    // 못 믿게 된다. 두 화면이 같은 reachLabel을 쓰는지 값으로 확인한다.
    testWidgets('거리와 도보 시간을 층·업종 아래에 보여준다', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          repository: _FakeRepository(Future.value(null)),
          reach: const NodeReach(distanceM: 124.4, costM: 124.4),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('124m · 도보 2분'), findsOneWidget);
    });

    testWidgets('위치가 없으면 거리 줄을 아예 그리지 않는다', (tester) async {
      await tester.pumpWidget(
        buildSubject(repository: _FakeRepository(Future.value(null))),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('도보'), findsNothing);
      // 층·업종 줄은 그대로다.
      expect(find.textContaining('1F'), findsOneWidget);
    });
  });

  group('저장 토글', () {
    late FavoritesController original;

    setUp(() async {
      original = favoritesController;
      SharedPreferences.setMockInitialValues({});
      favoritesController = FavoritesController(
        prefs: await SharedPreferences.getInstance(),
      );
    });

    tearDown(() => favoritesController = original);

    // 저장은 눌러도 화면이 그대로 남는 유일한 버튼이다. 시트를 닫는 출발·도착과
    // 같은 줄에 두면 무엇이 화면을 바꾸는 버튼인지 예측할 수 없다.
    testWidgets('저장은 길찾기 줄이 아니라 헤더에 있다', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          favorite: _favorite,
          repository: _FakeRepository(Future.value(null)),
        ),
      );
      await tester.pumpAndSettle();

      final save = find.byKey(const ValueKey('place-detail-save'));
      expect(save, findsOneWidget);
      expect(
        find.descendant(of: find.byType(SheetHeader), matching: save),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('place-detail-actions')),
          matching: save,
        ),
        findsNothing,
      );
    });

    testWidgets('저장할 대상이 없으면 헤더에 토글을 그리지 않는다', (tester) async {
      await tester.pumpWidget(
        buildSubject(repository: _FakeRepository(Future.value(null))),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('place-detail-save')), findsNothing);
      // 토글이 빠져도 헤더의 뒤로·X는 그대로다.
      expect(find.byTooltip('뒤로'), findsOneWidget);
      expect(find.byTooltip('전체 닫기'), findsOneWidget);
    });

    testWidgets('저장을 눌러도 시트가 닫히지 않고 상태만 바뀐다', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          favorite: _favorite,
          repository: _FakeRepository(Future.value(null)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('장소에 저장'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('place-detail-save')));
      await tester.pumpAndSettle();

      // 시트는 그대로 있고, 토글만 저장됨 상태가 된다.
      expect(find.text('테스트 매장'), findsOneWidget);
      expect(find.byTooltip('저장 취소'), findsOneWidget);
      expect(favoritesController.contains(_favorite.key), isTrue);
    });
  });

  testWidgets('출발 버튼은 기존 StoreInfoAction 계약으로 닫힌다', (tester) async {
    StoreInfoAction? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await PlaceDetailSheet.show(
                context,
                title: '테스트 매장',
                subtitle: '1F',
                buildingId: 'building-1',
                placeId: 'place-1',
                repository: _FakeRepository(Future.value(null)),
                onCloseAll: () {},
              );
            },
            child: const Text('열기'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('출발'));
    await tester.pumpAndSettle();

    expect(result, StoreInfoAction.setOrigin);
  });

  testWidgets('X는 전체 닫기 콜백을 호출하고 현재 시트를 닫는다', (tester) async {
    var closedAll = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => PlaceDetailSheet.show(
              context,
              title: '테스트 매장',
              subtitle: '1F',
              buildingId: 'building-1',
              placeId: 'place-1',
              repository: _FakeRepository(Future.value(null)),
              onCloseAll: () => closedAll = true,
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('전체 닫기'));
    await tester.pumpAndSettle();

    expect(closedAll, isTrue);
    expect(find.text('테스트 매장'), findsNothing);
  });

  testWidgets('뒤로는 전체 닫기 없이 현재 시트만 닫는다', (tester) async {
    var closedAll = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => PlaceDetailSheet.show(
              context,
              title: '테스트 매장',
              subtitle: '1F',
              buildingId: 'building-1',
              placeId: 'place-1',
              repository: _FakeRepository(Future.value(null)),
              onCloseAll: () => closedAll = true,
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();

    expect(closedAll, isFalse);
    expect(find.text('테스트 매장'), findsNothing);
  });

  // --- 헤더: 카테고리 아이콘 + 층 pill ---

  testWidgets('층이 없으면 pill을 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        subtitle: '',
        subcategory: '카페·베이커리',
        repository: _FakeRepository(Future.value(null)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('카페·베이커리'), findsOneWidget);
    expect(find.text('1F'), findsNothing);
  });

  testWidgets('층도 업종도 없으면 이름만 남는다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        subtitle: '',
        repository: _FakeRepository(Future.value(null)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('테스트 매장'), findsOneWidget);
  });

  testWidgets('영어 subcategory는 한글 라벨로 바꿔 그린다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        category: '편의시설',
        subcategory: 'restroom',
        repository: _FakeRepository(Future.value(null)),
      ),
    );
    await tester.pumpAndSettle();

    // 층과 한 줄로 합쳐 그리므로 부분 일치로 본다.
    expect(find.textContaining('화장실'), findsOneWidget);
    expect(find.textContaining('restroom'), findsNothing);
  });

  testWidgets('헤더 아이콘은 세부 규칙을 대분류보다 먼저 쓴다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        category: '식음료',
        subcategory: '카페·베이커리',
        repository: _FakeRepository(Future.value(null)),
      ),
    );
    await tester.pumpAndSettle();

    // 식음료 대분류는 restaurant지만, 카페 세부 규칙이 이겨야 한다.
    expect(find.byIcon(Icons.local_cafe_outlined), findsOneWidget);
    expect(find.byIcon(Icons.restaurant), findsNothing);
  });

  testWidgets('세부 규칙에 걸리지 않으면 대분류 아이콘으로 떨어진다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        category: '패션',
        subcategory: '명품',
        repository: _FakeRepository(Future.value(null)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.checkroom), findsOneWidget);
    expect(find.byIcon(Icons.storefront), findsNothing);
  });

  testWidgets('카테고리가 없으면 상점 아이콘으로 떨어진다', (tester) async {
    await tester.pumpWidget(
      buildSubject(repository: _FakeRepository(Future.value(null))),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.storefront), findsOneWidget);
  });
}

class _FakeRepository implements PlaceDetailRepository {
  _FakeRepository(this.response);

  final Future<PlaceDetail?> response;

  @override
  Future<PlaceDetail?> getPlaceDetail(String buildingId, String placeId) =>
      response;
}

PlaceDetail _detail({
  required List<Map<String, dynamic>> sections,
  String kind = 'store',
  String source = 'manual',
  String? updatedAt,
}) => PlaceDetail.fromJson({
  'kind': kind,
  'id': 'place-1',
  'name': '테스트 매장',
  'subtitle': '1F',
  'category': null,
  'subcategory': null,
  'location': {
    'building_id': 'building-1',
    'floor_label': '1F',
    'position_local_m': {'x': 0, 'y': 0},
    'entrance_node_id': null,
  },
  'actions': [],
  'sections': sections,
  'provenance': {'source': source, 'updated_at': updatedAt},
});

PlaceDetail _detailWithSummary({
  String kind = 'store',
  String source = 'manual',
  String? updatedAt,
}) => _detail(
  kind: kind,
  source: source,
  updatedAt: updatedAt,
  sections: const [
    {'type': 'summary', 'text': '상세 섹션'},
  ],
);
