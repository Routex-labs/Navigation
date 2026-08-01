import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/models/place_detail.dart';
import 'package:navigation_client/repositories/place_detail_repository.dart';
import 'package:navigation_client/widgets/place_detail/korean_line_break.dart';
import 'package:navigation_client/widgets/place_detail_sheet.dart';

void main() {
  Widget buildSubject({
    PlaceDetailRepository? repository,
    VoidCallback? onCloseAll,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PlaceDetailSheet(
          title: '테스트 매장',
          subtitle: '1F',
          buildingId: 'building-1',
          placeId: 'place-1',
          onCloseAll: onCloseAll ?? () {},
          repository: repository,
        ),
      ),
    );
  }

  testWidgets('상세를 불러오는 동안에도 코어와 길찾기 버튼을 즉시 그린다', (
    tester,
  ) async {
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

  testWidgets('매장 정보가 없어도 소개는 제목을 갖는다', (tester) async {
    await tester.pumpWidget(
      buildSubject(repository: _FakeRepository(Future.value(_detailWithSummary()))),
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
}

class _FakeRepository implements PlaceDetailRepository {
  _FakeRepository(this.response);

  final Future<PlaceDetail?> response;

  @override
  Future<PlaceDetail?> getPlaceDetail(String buildingId, String placeId) => response;
}

PlaceDetail _detail({
  required List<Map<String, dynamic>> sections,
  String kind = 'store',
  String source = 'manual',
  String? updatedAt,
}) =>
    PlaceDetail.fromJson({
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
}) =>
    _detail(
      kind: kind,
      source: source,
      updatedAt: updatedAt,
      sections: const [
        {'type': 'summary', 'text': '상세 섹션'},
      ],
    );
