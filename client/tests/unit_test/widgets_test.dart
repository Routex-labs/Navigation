import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/models/building.dart';
import 'package:navigation_client/models/building_graph.dart';
import 'package:navigation_client/models/indoor_route.dart';
import 'package:navigation_client/models/poi_search_result.dart';
import 'package:navigation_client/repositories/building_repository.dart';
import 'package:navigation_client/repositories/destination_repository.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:navigation_client/widgets/location_marker.dart';
import 'package:navigation_client/widgets/ai_search_sheet.dart';
import 'package:navigation_client/widgets/search_panel.dart';
import 'package:navigation_client/widgets/status_badge.dart';
import 'package:navigation_client/widgets/uncertainty_circle.dart';

void main() {
  testWidgets('LocationMarker uses the outdoor mode color by default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LocationMarker(mode: LocationMode.outdoor),
      ),
    );

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.navigation);
    expect(icon.color, AppColors.primary);
  });

  testWidgets('LocationMarker colorOverride wins over the mode color', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LocationMarker(
          mode: LocationMode.outdoor,
          colorOverride: Colors.amber,
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, Colors.amber);
  });

  testWidgets('UncertaintyCircle renders with the requested diameter', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: UncertaintyCircle(diameter: 40, color: Colors.purple),
      ),
    );

    final box = tester.widget<SizedBox>(find.byType(SizedBox));
    expect(box.width, 40);
    expect(box.height, 40);
  });

  testWidgets('StatusBadge shows the given label', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StatusBadge(label: 'GPS 신호 약함'),
      ),
    );

    expect(find.text('GPS 신호 약함'), findsOneWidget);
  });

  testWidgets('EtaCard shows the distance and minutes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: EtaCard(distanceMeters: 150, minutes: 2),
      ),
    );

    expect(find.text('목적지까지'), findsOneWidget);
    expect(find.textContaining('약 2분', findRichText: true), findsOneWidget);
    expect(find.textContaining('150m', findRichText: true), findsOneWidget);
  });

  group('AiSearchSheet', () {
    // 전역을 선언 시점에 읽으면 lazy 초기화가 테스트 존 밖에서 일어나
    // HttpDestinationRepository의 http.Client 생성이 터진다. setUp 안에서 잡는다.
    late DestinationRepository originalRepository;

    setUp(() => originalRepository = destinationRepository);
    tearDown(() => destinationRepository = originalRepository);

    Future<void> pumpPanel(WidgetTester tester) => tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AiSearchSheet(buildingId: 'thehyundai-seoul')),
      ),
    );

    testWidgets('질의 전에는 안내 문구만 보여준다', (WidgetTester tester) async {
      destinationRepository = _FakeDestinationRepository();
      await pumpPanel(tester);

      expect(find.text('AI 매장 찾기'), findsOneWidget);
      expect(find.textContaining('의미가 가장 가까운 매장'), findsOneWidget);
    });

    testWidgets('찾은 매장의 이름과 층을 답으로 보여준다', (WidgetTester tester) async {
      destinationRepository = _FakeDestinationRepository(
        result: const PoiSearchResult(
          name: '스시코우지',
          floor: 'B1',
          point: LatLng(37.52, 126.92),
          nodeId: 'FL-1:ND-1',
        ),
      );
      await pumpPanel(tester);

      await tester.enterText(find.byType(TextField), '밥 먹을 곳');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      // 사용자 질의와 결과가 모두 남는다.
      expect(find.text('밥 먹을 곳'), findsOneWidget);
      expect(find.textContaining('스시코우지'), findsOneWidget);
      expect(find.textContaining('B1'), findsOneWidget);
    });

    testWidgets('응답을 기다리는 동안 진행 표시를 띄운다', (WidgetTester tester) async {
      // 2차 의미 검색은 임베딩 모델 로드로 수 초 걸릴 수 있어, 그 동안 UI가
      // 멈춘 것처럼 보이면 안 된다.
      final repository = _FakeDestinationRepository(
        result: const PoiSearchResult(
          name: '스시코우지',
          floor: 'B1',
          point: LatLng(37.52, 126.92),
          nodeId: 'FL-1:ND-1',
        ),
        delay: const Duration(seconds: 3),
      );
      destinationRepository = repository;
      await pumpPanel(tester);

      await tester.enterText(find.byType(TextField), '밥 먹을 곳');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(find.text('찾는 중…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 4));
      expect(find.text('찾는 중…'), findsNothing);
      expect(find.textContaining('스시코우지'), findsOneWidget);
    });

    testWidgets('no_match면 못 찾았다고 안내한다', (WidgetTester tester) async {
      destinationRepository = _FakeDestinationRepository();
      await pumpPanel(tester);

      await tester.enterText(find.byType(TextField), 'asdfqwerzxcv');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.textContaining('찾지 못했어요'), findsOneWidget);
    });

    testWidgets('ok_no_route면 경로 안내가 어렵다고 덧붙인다', (WidgetTester tester) async {
      // nodeId가 null이면 온디바이스 다익스트라의 도착점이 없다.
      destinationRepository = _FakeDestinationRepository(
        result: const PoiSearchResult(
          name: '팝업스토어',
          floor: '5F',
          point: LatLng(37.52, 126.92),
        ),
      );
      await pumpPanel(tester);

      await tester.enterText(find.byType(TextField), '팝업');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.textContaining('경로 안내는 어려워요'), findsOneWidget);
    });

    testWidgets('서버 장애에도 패널이 살아 있고 안내만 바뀐다', (WidgetTester tester) async {
      destinationRepository = _FakeDestinationRepository(fail: true);
      await pumpPanel(tester);

      await tester.enterText(find.byType(TextField), '밥 먹을 곳');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.textContaining('잠시 후 다시 시도'), findsOneWidget);
      // 다음 질의를 계속 받을 수 있어야 한다.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('공백만 입력하면 백엔드를 호출하지 않는다', (WidgetTester tester) async {
      // 백엔드가 공백 질의를 422로 막으므로 아예 보내지 않는다.
      final repository = _FakeDestinationRepository();
      destinationRepository = repository;
      await pumpPanel(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(repository.aiQueries, isEmpty);
    });
  });

  group('SearchPanel', () {
    // 이 그룹의 관심사는 "의미 검색이 언제 도는가"와 "최종 없음 문구가 언제
    // 나오는가" 두 가지다. 예전에는 엔터(submitTick)가 올라야만 의미 검색이
    // 돌았고, 그 전까지 경량이 빈손이면 화면에는 "찾지 못했어요"가 최종
    // 결론처럼 떠 있었다. 한글 IME에서 첫 엔터가 조합 확정에 쓰이면 엔터가
    // 아예 안 와서 의미 검색이 시작조차 안 됐다.
    late DestinationRepository originalDestinations;
    late BuildingRepository originalBuildings;

    setUp(() {
      originalDestinations = destinationRepository;
      originalBuildings = buildingRepository;
      buildingRepository = _FakeBuildingRepository();
    });
    tearDown(() {
      destinationRepository = originalDestinations;
      buildingRepository = originalBuildings;
    });

    // 상위가 검색어와 엔터 횟수를 내려주는 구조라, 테스트에서도 그 두 값만
    // 바꿔 끼운다. 패널 내부 메서드를 직접 부르지 않는 게 실제 사용 경로다.
    final query = ValueNotifier<String>('');
    final submitTick = ValueNotifier<int>(0);

    Future<void> pumpPanel(WidgetTester tester, {String? currentFloorId}) {
      query.value = '';
      submitTick.value = 0;
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: Listenable.merge([query, submitTick]),
              builder: (_, _) => SearchPanel(
                buildingId: 'thehyundai-seoul',
                query: query.value,
                submitTick: submitTick.value,
                onStorePicked: (_) {},
                onBuildingPicked: (_) {},
                currentFloorId: currentFloorId,
              ),
            ),
          ),
        ),
      );
    }

    /// 마이크로태스크만 흘려보낸다(가짜 시계는 그대로). 대기 시간을 실제로
    /// 건너뛰었는지 확인해야 하는 검증에서 시간을 흘리면 의미가 없어진다.
    Future<void> flush(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    /// 경량 디바운스(300ms) → 경량 응답 → 의미 대기(400ms) → 의미 응답까지
    /// 한 번에 흘려보낸다. `pumpAndSettle`을 쓰지 않는 이유는 그 함수가 **프레임이
    /// 예약돼 있는 동안만** 시계를 돌리기 때문이다. 디바운스 타이머만 남은 구간은
    /// 프레임을 예약하지 않아서 pumpAndSettle이 그냥 즉시 돌아온다.
    Future<void> settleSearch(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 350));
      await flush(tester);
      await tester.pump(const Duration(milliseconds: 450));
      await flush(tester);
    }

    /// 아직 응답을 안 준 느린 호출을 끝까지 흘려보낸다. 타이머가 남은 채 테스트가
    /// 끝나면 프레임워크가 실패로 잡는다.
    Future<void> drain(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 6));
      await flush(tester);
    }

    const store = PoiSearchResult(
      name: '스시코우지',
      floor: 'B1',
      point: LatLng(37.52, 126.92),
      nodeId: 'FL-1:ND-1',
    );

    testWidgets('경량이 빈손이어도 의미 검색 전에는 최종 없음 문구를 띄우지 않는다', (
      WidgetTester tester,
    ) async {
      // "신발"은 어떤 매장명·카테고리와도 정확히 일치하지 않아 경량이 항상 빈손이다.
      destinationRepository = _FakeSearchRepository(
        aiResults: const [store],
        aiDelay: const Duration(seconds: 5),
      );
      await pumpPanel(tester);

      query.value = '신발';
      await tester.pump();
      // 경량 디바운스(300ms)만 지난 시점 — 경량은 끝났고 의미 검색은 아직이다.
      await tester.pump(const Duration(milliseconds: 320));
      await flush(tester);

      expect(find.textContaining('찾지 못했어요'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('엔터 없이 debounce만으로 의미 검색이 호출된다', (WidgetTester tester) async {
      final repository = _FakeSearchRepository(aiResults: const [store]);
      destinationRepository = repository;
      await pumpPanel(tester);

      query.value = '신발';
      await tester.pump();
      // submitTick은 그대로 0이다. 엔터를 누르지 않았다는 뜻.
      await settleSearch(tester);

      expect(submitTick.value, 0);
      expect(repository.aiQueries, ['신발']);
      expect(find.text('스시코우지'), findsOneWidget);
      // 왜 다른 이름이 나왔는지 알려 주는 배너는 그대로 유지한다.
      expect(find.text('뜻이 비슷한 매장을 찾았어요'), findsOneWidget);
    });

    testWidgets('의미 검색 결과가 질의와 이름이 정확히 같으면 배너를 띄우지 않는다', (
      WidgetTester tester,
    ) async {
      // 층 스코프(ea315b8) 적용 뒤: 1F에서 타 층 "나이키"를 정확한 이름으로
      // 검색하면 1차(현재 층 한정)는 빈손이고 2차 의미 검색이 찾아낸다. 이때는
      // 뜻으로 찾은 게 아니라 정확한 이름 일치이므로 "뜻이 비슷한" 배너가
      // 붙으면 안 된다.
      const nike = PoiSearchResult(
        name: '나이키',
        floor: '3F',
        point: LatLng(37.52, 126.92),
        nodeId: 'FL-3:ND-1',
      );
      final repository = _FakeSearchRepository(aiResults: const [nike]);
      destinationRepository = repository;
      await pumpPanel(tester, currentFloorId: '1F');

      query.value = '나이키';
      await tester.pump();
      await settleSearch(tester);

      expect(repository.aiQueries, ['나이키']);
      expect(find.text('나이키'), findsOneWidget);
      expect(find.text('뜻이 비슷한 매장을 찾았어요'), findsNothing);
    });

    testWidgets('의미 검색까지 빈손이어야 최종 없음 문구를 띄운다', (WidgetTester tester) async {
      final repository = _FakeSearchRepository();
      destinationRepository = repository;
      await pumpPanel(tester);

      query.value = 'asdfqwerzxcv';
      await tester.pump();
      await settleSearch(tester);

      expect(repository.aiQueries, ['asdfqwerzxcv']);
      expect(find.textContaining('찾지 못했어요'), findsOneWidget);
      expect(find.text('다른 말로 바꿔서 다시 찾아보세요.'), findsOneWidget);
    });

    testWidgets('의미 검색으로 넘어가면 다른 문구를 띄운다', (WidgetTester tester) async {
      // 여기서부터 수 초가 걸릴 수 있어, 같은 스피너만 돌면 멈춘 것처럼 보인다.
      destinationRepository = _FakeSearchRepository(
        aiDelay: const Duration(seconds: 5),
      );
      await pumpPanel(tester);

      query.value = '신발';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await flush(tester);

      expect(find.text('뜻이 비슷한 매장을 찾는 중…'), findsOneWidget);
      expect(find.textContaining('찾지 못했어요'), findsNothing);

      await drain(tester);
    });

    testWidgets('엔터는 대기를 건너뛰고 즉시 의미 검색을 태운다', (WidgetTester tester) async {
      destinationRepository = _FakeSearchRepository(
        aiDelay: const Duration(seconds: 5),
      );
      await pumpPanel(tester);

      query.value = '신발';
      submitTick.value = 1;
      await tester.pump();
      // 가짜 시계를 1ms도 돌리지 않았는데 이미 의미 검색 단계다.
      await flush(tester);

      expect(find.text('뜻이 비슷한 매장을 찾는 중…'), findsOneWidget);

      await drain(tester);
    });

    testWidgets('경량이 잡으면 의미 검색을 부르지 않는다', (WidgetTester tester) async {
      final repository = _FakeSearchRepository(lightResults: const [store]);
      destinationRepository = repository;
      await pumpPanel(tester);

      query.value = '스시코우지';
      await tester.pump();
      await settleSearch(tester);

      expect(repository.aiQueries, isEmpty);
      expect(find.text('스시코우지'), findsOneWidget);
      // 경량 결과에는 "뜻으로 찾았다" 배너를 붙이지 않는다.
      expect(find.text('뜻이 비슷한 매장을 찾았어요'), findsNothing);
    });

    testWidgets('타이핑이 이어지면 중간 글자로 의미 검색을 태우지 않는다', (
      WidgetTester tester,
    ) async {
      // 의미 검색은 백엔드 모델 로드로 첫 호출이 6초대까지 간다. "신"·"신바"가
      // 각각 모델을 태우면 안 된다.
      final repository = _FakeSearchRepository();
      destinationRepository = repository;
      await pumpPanel(tester);

      query.value = '신';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await flush(tester);
      query.value = '신바';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await flush(tester);
      query.value = '신발';
      await tester.pump();
      await settleSearch(tester);

      expect(repository.aiQueries, ['신발']);
    });

    testWidgets('서버 장애는 결과 없음과 다른 문구로 구분한다', (WidgetTester tester) async {
      // 백엔드가 죽었을 뿐인데 "그런 매장은 없다"고 말하면 안 된다.
      destinationRepository = _FakeSearchRepository(fail: true);
      await pumpPanel(tester);

      query.value = '신발';
      await tester.pump();
      await settleSearch(tester);

      expect(find.textContaining('찾지 못했어요'), findsNothing);
      expect(find.textContaining('다시 시도'), findsOneWidget);
    });

    testWidgets('현재 층이 주어지면 경량·의미 검색 요청 모두에 실어 보낸다', (
      WidgetTester tester,
    ) async {
      // "화장실"은 tier 1(카테고리 정확 일치)로 경량이 빈손이라, 의미 검색까지
      // 이어진다 — 두 요청 모두 층이 실제로 실리는지 확인해야 한다.
      final repository = _FakeSearchRepository(aiResults: const [store]);
      destinationRepository = repository;
      await pumpPanel(tester, currentFloorId: '1F');

      query.value = '화장실';
      await tester.pump();
      await settleSearch(tester);

      expect(repository.lightFloorIds, ['1F']);
      expect(repository.aiFloorIds, ['1F']);
    });

    testWidgets('현재 층이 없으면(야외 모드 등) null을 그대로 보낸다', (
      WidgetTester tester,
    ) async {
      final repository = _FakeSearchRepository();
      destinationRepository = repository;
      await pumpPanel(tester);

      query.value = '화장실';
      await tester.pump();
      await settleSearch(tester);

      expect(repository.lightFloorIds, [null]);
      expect(repository.aiFloorIds, [null]);
    });

    testWidgets('검색어를 지우면 안내 문구로 돌아간다', (WidgetTester tester) async {
      destinationRepository = _FakeSearchRepository();
      await pumpPanel(tester);

      query.value = 'asdfqwerzxcv';
      await tester.pump();
      await settleSearch(tester);
      expect(find.textContaining('찾지 못했어요'), findsOneWidget);

      query.value = '';
      await tester.pump();
      await settleSearch(tester);

      expect(find.textContaining('찾지 못했어요'), findsNothing);
      expect(find.textContaining('매장 이름을 입력하면'), findsOneWidget);
    });
  });
}

/// [SearchPanel]은 경량·의미 두 경로를 모두 쓰므로 각각 따로 흉내내야 한다.
class _FakeSearchRepository implements DestinationRepository {
  _FakeSearchRepository({
    this.lightResults = const [],
    this.aiResults = const [],
    this.aiDelay,
    this.fail = false,
  });

  final List<PoiSearchResult> lightResults;
  final List<PoiSearchResult> aiResults;
  final Duration? aiDelay;
  final bool fail;

  /// 의미 검색이 **몇 번, 어떤 글자로** 갔는지. 중간 글자로 모델을 태우지
  /// 않는지 확인하는 게 이 목록의 목적이다.
  final aiQueries = <String>[];

  /// 두 호출 각각에 실제로 실린 `currentFloorId`. 패널이 상위에서 받은 값을
  /// 그대로 넘기는지(빼먹거나 다른 값으로 바꾸지 않는지) 확인하는 데 쓴다.
  final lightFloorIds = <String?>[];
  final aiFloorIds = <String?>[];

  @override
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) async {
    lightFloorIds.add(currentFloorId);
    if (fail) throw Exception('boom');
    return lightResults;
  }

  @override
  Future<List<PoiSearchResult>> searchDestinationsAi(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) async {
    aiQueries.add(query);
    aiFloorIds.add(currentFloorId);
    if (aiDelay != null) await Future<void>.delayed(aiDelay!);
    if (fail) throw Exception('boom');
    return aiResults;
  }
}

/// 패널은 건물 이름 검색 때문에 getAllBuildings만 부른다. 나머지는 부르지
/// 않으므로 호출되면 테스트가 틀린 것이라 그대로 던진다.
class _FakeBuildingRepository implements BuildingRepository {
  @override
  Future<List<Building>> getAllBuildings() async => const [];

  @override
  Future<Building?> getBuilding(String buildingId) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  ) => throw UnimplementedError();

  @override
  Future<IndoorRoute?> getShortestRoute(
    String buildingId,
    String floor,
    String startNodeId,
    String endNodeId,
  ) => throw UnimplementedError();

  @override
  Future<BuildingGraph?> getBuildingGraph(
    String buildingId, {
    String vertical = 'auto',
  }) => throw UnimplementedError();
}

/// [AiSearchSheet]가 쓰는 것은 searchDestinationsAi 하나뿐이라 그 경로만 흉내낸다.
class _FakeDestinationRepository implements DestinationRepository {
  _FakeDestinationRepository({this.result, this.fail = false, this.delay});

  final PoiSearchResult? result;
  final bool fail;
  final Duration? delay;
  final aiQueries = <String>[];

  @override
  Future<List<PoiSearchResult>> searchDestinationsAi(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) async {
    aiQueries.add(query);
    if (delay != null) await Future<void>.delayed(delay!);
    if (fail) throw Exception('boom');
    return result == null ? const [] : [result!];
  }

  @override
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) async => const [];
}
