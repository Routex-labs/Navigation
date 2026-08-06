import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/discovery_result.dart';
import 'package:navigation_client/widgets/directions_sheet.dart';

/// 길찾기 시트의 검색이 상단 검색창과 같은 두 단계로 도는지 고정한다.
///
/// 예전에는 이 시트만 경량 매칭 한 번으로 끝나서 "밥 먹을 곳"처럼 이름이 아닌
/// 말은 항상 "검색 결과가 없습니다"였다. 여기서 지키려는 계약은 "경량이 잡으면
/// 거기서 끝, 빈손일 때만 의미 검색"이다. 두 방향 모두 회귀가 뼈아프다 —
/// 승격이 빠지면 자연어가 다시 영영 결과 없음이 되고, 반대로 항상 승격하면
/// 매장 이름을 정확히 아는 흔한 검색까지 임베딩 모델을 태워 몇 초씩 느려진다.
void main() {
  const point = LatLng(37.5, 127.0);

  DirectionsCandidate store(String name) => DirectionsCandidate(
    title: name,
    subtitle: 'B2',
    point: point,
    nodeId: 'node-$name',
    floor: 'B2',
  );

  /// 호출 인자를 그대로 기록하는 스텁. 승격 여부를 "몇 번 불렀나"로 검증한다.
  late List<String> lightCalls;
  late List<String> semanticCalls;
  late List<Map<String, List<String>>?> semanticFacets;
  late List<bool> semanticShowAll;

  setUp(() {
    lightCalls = [];
    semanticCalls = [];
    semanticFacets = [];
    semanticShowAll = [];
  });

  DirectionsSearchCallback lightReturning(
    List<DirectionsCandidate> results, {
    Object? throws,
  }) {
    return (query) async {
      lightCalls.add(query);
      if (throws != null) throw throws;
      return results;
    };
  }

  DirectionsSemanticSearchCallback semanticReturning(
    DirectionsDiscovery discovery,
  ) {
    return (query, {selectedFacets, required showAll}) async {
      semanticCalls.add(query);
      semanticFacets.add(selectedFacets);
      semanticShowAll.add(showAll);
      return discovery;
    };
  }

  /// 두 디바운스(경량 300ms, 의미 검색 +400ms)와 각 응답 반영을 모두 통과시킨다.
  /// `pumpAndSettle`은 프레임이 예약된 동안만 시간을 밀기 때문에, 화면이 조용한
  /// 사이에 도는 타이머는 이렇게 명시적으로 넘겨야 한다.
  Future<void> settleSearch(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.pump();
  }

  Future<void> pumpSheet(
    WidgetTester tester, {
    required DirectionsSearchCallback search,
    DirectionsSemanticSearchCallback? semanticSearch,
    bool focusOrigin = false,
  }) async {
    // 기본 테스트 화면(800x600)에서는 시트(높이의 60%)에 헤더를 빼면 목록이
    // 몇 줄 안 남아 chip이 화면 밖으로 밀린다. 실제 단말에 가깝게 키운다.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DirectionsSheet(
            originLabel: '현재 위치',
            search: search,
            semanticSearch: semanticSearch,
            focusOrigin: focusOrigin,
          ),
        ),
      ),
    );
    await settleSearch(tester);
  }

  Future<void> typeDestination(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).last, text);
    await settleSearch(tester);
  }

  testWidgets('빈 입력에서는 의미 검색을 부르지 않고 안내 문구를 보여준다', (tester) async {
    await pumpSheet(
      tester,
      search: lightReturning(const []),
      semanticSearch: semanticReturning(
        const DirectionsDiscovery(mode: DiscoveryMode.noMatch),
      ),
    );

    // 경량은 빈 질의로도 한 번 부른다 — 야외 모드에서 이 호출이 건물 목록을
    // 채운다. 의미 검색은 빈 질의로 부를 수 없다(서버가 422).
    expect(lightCalls, ['']);
    expect(semanticCalls, isEmpty);
    expect(find.textContaining('밥 먹을 곳'), findsOneWidget);
    expect(find.text('검색 결과가 없습니다'), findsNothing);
  });

  testWidgets('경량이 잡으면 의미 검색으로 넘어가지 않는다', (tester) async {
    await pumpSheet(
      tester,
      search: lightReturning([store('딥티크')]),
      semanticSearch: semanticReturning(
        const DirectionsDiscovery(mode: DiscoveryMode.noMatch),
      ),
    );

    await typeDestination(tester, '딥티크');

    expect(semanticCalls, isEmpty);
    // 검색창에도 같은 글자가 있으므로 목록 행으로 좁혀 찾는다.
    expect(find.widgetWithText(ListTile, '딥티크'), findsOneWidget);
    expect(find.textContaining('뜻이 비슷한'), findsNothing);
  });

  testWidgets('경량이 빈손이면 의미 검색 후보를 보여준다', (tester) async {
    await pumpSheet(
      tester,
      search: lightReturning(const []),
      semanticSearch: semanticReturning(
        DirectionsDiscovery(
          mode: DiscoveryMode.results,
          candidates: [store('한식당')],
        ),
      ),
    );

    await typeDestination(tester, '밥 먹을 곳');

    expect(semanticCalls, ['밥 먹을 곳']);
    expect(find.text('한식당'), findsOneWidget);
    expect(find.text('뜻이 비슷한 곳을 찾았어요'), findsOneWidget);
  });

  testWidgets('타이핑 중간 글자는 서버로 나가지 않는다', (tester) async {
    await pumpSheet(
      tester,
      search: lightReturning(const []),
      semanticSearch: semanticReturning(
        const DirectionsDiscovery(mode: DiscoveryMode.noMatch),
      ),
    );
    lightCalls.clear();

    final field = find.byType(TextField).last;
    await tester.enterText(field, '밥');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, '밥 먹');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, '밥 먹을 곳');
    await settleSearch(tester);

    // 디바운스가 없던 예전 코드는 여기서 세 번 나갔다.
    expect(lightCalls, ['밥 먹을 곳']);
    expect(semanticCalls, ['밥 먹을 곳']);
  });

  testWidgets('의미 검색을 쓸 수 없는 야외 모드는 경량에서 결론을 낸다', (tester) async {
    await pumpSheet(tester, search: lightReturning(const []));

    await typeDestination(tester, '밥 먹을 곳');

    expect(semanticCalls, isEmpty);
    expect(find.textContaining('찾지 못했어요'), findsOneWidget);
  });

  testWidgets('clarify 선택지를 고르면 선택을 실어 다시 묻는다', (tester) async {
    await pumpSheet(
      tester,
      search: lightReturning(const []),
      semanticSearch: semanticReturning(
        DirectionsDiscovery(
          mode: DiscoveryMode.clarify,
          question: '어떤 음식이 좋으세요?',
          options: const [
            DiscoveryOption(
              facet: 'cuisines',
              value: '한식',
              label: '한식',
              count: 3,
            ),
          ],
          candidates: [store('한식당')],
        ),
      ),
    );

    await typeDestination(tester, '밥 먹을 곳');
    expect(find.text('어떤 음식이 좋으세요?'), findsOneWidget);

    final chip = find.byKey(const Key('directions-facet-option-cuisines-한식'));
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(semanticCalls.length, 2);
    expect(semanticFacets.last, {
      'cuisines': ['한식'],
    });
    expect(semanticShowAll.last, isFalse);

    await tester.tap(find.byKey(const Key('directions-show-all')));
    await tester.pumpAndSettle();
    expect(semanticShowAll.last, isTrue);
  });

  testWidgets('출발지 칸에서는 검색이 실패해도 현재 위치를 고를 수 있다', (tester) async {
    await pumpSheet(
      tester,
      search: lightReturning(const [], throws: Exception('boom')),
      semanticSearch: semanticReturning(
        const DirectionsDiscovery(mode: DiscoveryMode.noMatch),
      ),
      focusOrigin: true,
    );

    await tester.enterText(find.byType(TextField).first, '나이키');
    await settleSearch(tester);

    // 서버 장애를 "결과 없음"으로 말하지 않는다 — 사용자가 할 행동이 다르다.
    expect(find.textContaining('지금은 검색할 수 없어요'), findsOneWidget);
    expect(find.text('현재 위치'), findsOneWidget);
  });

  testWidgets('입구 노드가 없는 후보는 경로 안내 불가라고 알린다', (tester) async {
    await pumpSheet(
      tester,
      search: lightReturning(const [
        DirectionsCandidate(
          title: '팝업스토어',
          subtitle: 'B2',
          point: point,
          floor: 'B2',
        ),
      ]),
    );

    await typeDestination(tester, '팝업');

    expect(find.text('B2 · 경로 안내 불가'), findsOneWidget);
  });
}
