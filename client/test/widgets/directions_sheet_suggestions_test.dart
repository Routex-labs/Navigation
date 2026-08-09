import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/dijkstra.dart';
import 'package:navigation_client/models/discovery_result.dart';
import 'package:navigation_client/models/store_index_entry.dart';
import 'package:navigation_client/widgets/directions_sheet.dart';

/// 길찾기 검색에도 상단 검색과 같은 **온디바이스 후보**를 붙인 것.
///
/// 예전에는 길찾기에서 초성(`ㄴㅇㅋ`)·구두점(`A.P.C.`)·오타(`샤낼 뷰티`)가 아예
/// 안 걸렸다. 서버 경량 매칭이 `name LIKE`라 못 잡는 것들인데, 상단 검색에는
/// 기기 안 인덱스가 있고 길찾기에는 없었다 — 같은 앱에서 같은 말을 쳐도 자리에
/// 따라 결과가 달랐다.
///
/// 설계는 `docs/client/map-ui-redesign-plan.md`의 「7+E 합동 설계」 2단계다.

StoreIndexEntry _entry(String name, String floor, {String? nodeId}) =>
    StoreIndexEntry(
      id: 'PO-$name-$floor',
      name: name,
      floorId: 'FL-$floor',
      floorName: floor,
      entranceNodeId: nodeId,
    );

DirectionsCandidate _candidate(String title, String floor) =>
    DirectionsCandidate(
      title: title,
      subtitle: floor,
      point: const LatLng(37.5, 127.0),
      nodeId: 'N-$title',
      floor: floor,
    );

void main() {
  late List<String> queries;
  late List<String?> floorScopes;

  setUp(() {
    queries = [];
    floorScopes = [];
  });

  Widget subject({
    required List<StoreIndexEntry> index,
    List<DirectionsCandidate> Function(String query)? serverResults,
    Map<String, NodeReach>? reachByNodeId,
  }) => MaterialApp(
    home: Scaffold(
      body: DirectionsSheet(
        originLabel: '현재 위치',
        search: (query, {String? floorId}) async {
          queries.add(query);
          floorScopes.add(floorId);
          return serverResults?.call(query) ?? const [];
        },
        // 의미 검색이 있어야 "후보가 있으면 2차로 안 넘어간다"를 잴 수 있다.
        semanticSearch: (query, {selectedFacets, required showAll}) async {
          return const DirectionsDiscovery(mode: DiscoveryMode.noMatch);
        },
        storeIndex: Future.value(index),
        reachByNodeId: reachByNodeId,
      ),
    ),
  );

  /// 경량(300ms) + 의미(400ms)를 모두 지나 결론이 날 때까지 흘려보낸다.
  Future<void> settle(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).last, query);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
  }

  testWidgets('서버가 못 잡는 구두점 상호를 온디바이스 후보가 잡는다', (tester) async {
    await tester.pumpWidget(subject(index: [_entry('A.P.C.', '3F')]));
    await tester.pumpAndSettle();

    await settle(tester, 'apc');

    expect(find.text('검색어 제안'), findsOneWidget);
    expect(find.text('A.P.C.'), findsOneWidget);
    expect(find.text('3F'), findsOneWidget);
  });

  testWidgets('초성으로도 후보가 나온다', (tester) async {
    await tester.pumpWidget(subject(index: [_entry('나이키 라이즈', 'B2')]));
    await tester.pumpAndSettle();

    await settle(tester, 'ㄴㅇㅋ');

    expect(find.text('나이키 라이즈'), findsOneWidget);
  });

  // 상단 검색 패널이 실기기에서 겪은 사고와 같은 것을 막는다 — 정답이 이미
  // 화면에 있는데 임계값을 겨우 넘긴 의미 검색이 엉뚱한 곳으로 갈아치우는 것.
  // 막는 대상은 임베딩 **결과**지 호출이 아니다.
  testWidgets('이름이 걸린 후보는 임베딩 결과에 덮이지 않는다', (tester) async {
    var aiCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DirectionsSheet(
            originLabel: '현재 위치',
            search: (query, {String? floorId}) async => const [],
            semanticSearch: (query, {selectedFacets, required showAll}) async {
              aiCalls++;
              return DirectionsDiscovery(
                mode: DiscoveryMode.results,
                source: DiscoverySource.semantic,
                candidates: [_candidate('6A', 'B5')],
              );
            },
            storeIndex: Future.value([_entry('A.P.C.', '3F')]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await settle(tester, 'apc');

    expect(aiCalls, 1);
    expect(find.text('A.P.C.'), findsOneWidget);
    expect(find.text('6A'), findsNothing);
  });

  // `커피`가 상호에 그 글자가 든 몇 곳으로 끝나던 문제. 서버 어휘는 이름
  // 후보와 같은 등급이라 이긴다.
  testWidgets('어휘로 잡은 결과는 이름 후보를 대체한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DirectionsSheet(
            originLabel: '현재 위치',
            search: (query, {String? floorId}) async => const [],
            semanticSearch: (query, {selectedFacets, required showAll}) async =>
                DirectionsDiscovery(
                  mode: DiscoveryMode.results,
                  source: DiscoverySource.light,
                  candidates: [_candidate('블루보틀', '5F')],
                ),
            storeIndex: Future.value([_entry('더커피', 'B1')]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await settle(tester, '커피');

    expect(find.text('블루보틀'), findsOneWidget);
  });

  // 교정은 추측이라 2차에 기회를 준다. 그러고도 못 찾으면 되묻는다.
  testWidgets('오타는 의미 검색까지 지난 뒤 되묻는다', (tester) async {
    await tester.pumpWidget(subject(index: [_entry('샤넬 뷰티', '1F')]));
    await tester.pumpAndSettle();

    await settle(tester, '샤낼 뷰티');

    expect(find.text('이걸 찾으셨나요?'), findsOneWidget);
    expect(find.text('샤넬 뷰티'), findsOneWidget);
  });

  testWidgets('후보에도 거리와 도보 시간이 붙는다', (tester) async {
    await tester.pumpWidget(
      subject(
        index: [_entry('A.P.C.', '3F', nodeId: 'N1')],
        reachByNodeId: const {'N1': NodeReach(distanceM: 124.4, costM: 124.4)},
      ),
    );
    await tester.pumpAndSettle();

    await settle(tester, 'apc');

    expect(find.text('124m · 도보 2분'), findsOneWidget);
  });

  // 묶인 시설의 대표는 최근접이다 — 상단 검색과 같은 규칙.
  testWidgets('묶인 시설은 최근접을 대표로 세우고 개수를 남긴다', (tester) async {
    await tester.pumpWidget(
      subject(
        index: [
          _entry('화장실', '6F', nodeId: 'N6'),
          _entry('화장실', 'B2', nodeId: 'NB2'),
          _entry('화장실', '1F', nodeId: 'N1'),
        ],
        reachByNodeId: const {
          'N6': NodeReach(distanceM: 310, costM: 310),
          'NB2': NodeReach(distanceM: 48, costM: 48),
          'N1': NodeReach(distanceM: 120, costM: 120),
        },
      ),
    );
    await tester.pumpAndSettle();

    await settle(tester, '화장실');

    expect(find.text('B2 등 3곳'), findsOneWidget);
  });

  // T와 같은 규칙 — 화면에 적힌 층과 실제로 가는 층이 어긋나면 안 된다.
  testWidgets('후보를 탭하면 그 후보의 층으로 좁혀 다시 검색한다', (tester) async {
    await tester.pumpWidget(
      subject(
        index: [
          _entry('화장실', '6F', nodeId: 'N6'),
          _entry('화장실', 'B2', nodeId: 'NB2'),
        ],
        serverResults: (query) =>
            query == '화장실' ? [_candidate('화장실', 'B2')] : const [],
        reachByNodeId: const {
          'N6': NodeReach(distanceM: 310, costM: 310),
          'NB2': NodeReach(distanceM: 48, costM: 48),
        },
      ),
    );
    await tester.pumpAndSettle();

    await settle(tester, '화장');
    await tester.tap(find.byKey(const Key('directions-suggestion-PO-화장실-B2')));
    await tester.pumpAndSettle();

    // 사용자가 직접 친 질의에는 층을 안 보낸다(「항상 건물 전체」 규칙).
    expect(floorScopes.first, isNull);
    // 후보를 콕 집은 검색에만 그 층이 실린다.
    expect(floorScopes.last, 'FL-B2');
  });

  // 인덱스를 못 받았거나 야외라 안 넘긴 경우. 후보만 조용히 사라지고 검색은
  // 그대로 돌아야 한다.
  testWidgets('인덱스가 없으면 후보만 사라지고 검색은 그대로 돈다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DirectionsSheet(
            originLabel: '현재 위치',
            search: (query, {String? floorId}) async {
              queries.add(query);
              return [_candidate('MLB', 'B2')];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await settle(tester, 'mlb');

    expect(find.text('검색어 제안'), findsNothing);
    expect(find.text('MLB'), findsOneWidget);
  });

  // U. 길찾기는 원래 층을 안 보낸다(「항상 건물 전체」). 그런데 층마다 있는
  // 시설에서는 그게 정반대라, 1F에 서서 `화장`을 치면 B6가 답이었다.
  group('U. 시설 질의만 가장 가까운 층으로 좁힌다', () {
    testWidgets('층마다 있는 시설이면 최근접 층을 실어 보낸다', (tester) async {
      await tester.pumpWidget(
        subject(
          index: [
            _entry('화장실', '6F', nodeId: 'N6'),
            _entry('화장실', 'B2', nodeId: 'NB2'),
            _entry('화장실', '1F', nodeId: 'N1'),
          ],
          reachByNodeId: const {
            'N6': NodeReach(distanceM: 310, costM: 310),
            'NB2': NodeReach(distanceM: 48, costM: 48),
            'N1': NodeReach(distanceM: 120, costM: 120),
          },
        ),
      );
      await tester.pumpAndSettle();

      await settle(tester, '화장');

      expect(floorScopes.last, 'FL-B2');
    });

    // 매장은 다른 층에 있는 게 정상이라 규칙이 그대로여야 한다.
    testWidgets('매장 질의는 여전히 건물 전체를 본다', (tester) async {
      await tester.pumpWidget(
        subject(
          index: [
            _entry('나이키스윔', '4F', nodeId: 'N4'),
            _entry('나이키 라이즈', 'B2', nodeId: 'NB2'),
          ],
          reachByNodeId: const {
            'N4': NodeReach(distanceM: 118, costM: 118),
            'NB2': NodeReach(distanceM: 168, costM: 168),
          },
        ),
      );
      await tester.pumpAndSettle();

      await settle(tester, '나이키');

      expect(floorScopes.last, isNull);
    });

    testWidgets('위치를 모르면 좁히지 않는다', (tester) async {
      await tester.pumpWidget(
        subject(
          index: [
            _entry('화장실', '6F', nodeId: 'N6'),
            _entry('화장실', 'B2', nodeId: 'NB2'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await settle(tester, '화장');

      expect(floorScopes.last, isNull);
    });
  });
}
