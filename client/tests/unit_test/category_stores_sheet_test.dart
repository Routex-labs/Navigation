import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/models/building.dart';
import 'package:navigation_client/repositories/building_repository.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/models/poi_search_result.dart';
import 'package:navigation_client/widgets/category_stores_sheet.dart';

/// 카테고리 매장 목록 시트가 **현재 층을 먼저** 보여주는지 고정한다.
///
/// 예전에는 "현재 층만 보기" 토글로 걸렀다. 토글을 켜면 다른 층이 통째로
/// 사라지고, 끄면 현재 층이 목록 한가운데 파묻힌다 — 어느 쪽이든 "지금 층에
/// 있나?"와 "다른 층엔 어디 있나?"를 한 번에 답하지 못했다. 묶음이 뒤섞이거나
/// 순서가 뒤집히면 이 시트를 여는 이유 자체가 사라지므로 순서까지 확인한다.
void main() {
  late BuildingRepository original;

  setUp(() {
    original = buildingRepository;
    // 시트가 두 묶음을 다 그릴 만큼 넓은 화면. 기본 800x600에서는 아래 묶음이
    // sliver 밖으로 밀려 build조차 되지 않아 finder가 헛돈다.
    _resizeTo(const Size(1200, 2400));
  });

  tearDown(() {
    buildingRepository = original;
  });

  testWidgets('현재 층 묶음이 다른 층 묶음보다 먼저 온다', (tester) async {
    buildingRepository = _FloorStoresRepository(const {
      'B1': [('와인웍스', null)],
      '1F': [('현대베이커리', null)],
      '2F': [('프룻앤코', null)],
    });

    await _openSheet(tester, currentFloor: '1F');

    expect(find.text('현재 층 · 1F'), findsOneWidget);
    expect(find.text('다른 층'), findsOneWidget);
    // 개수는 묶음별로 따로 센다. 현재 층 1곳 / 나머지 2곳.
    expect(find.text('1곳'), findsOneWidget);
    expect(find.text('2곳'), findsOneWidget);

    final currentHeader = tester.getTopLeft(find.text('현재 층 · 1F')).dy;
    final otherHeader = tester.getTopLeft(find.text('다른 층')).dy;
    expect(currentHeader, lessThan(otherHeader));
    // 층 정렬(B1 → 2F)보다 묶음이 우선이다. 1F 매장이 B1 매장 위에 와야 한다.
    expect(
      tester.getTopLeft(find.text('현대베이커리')).dy,
      lessThan(tester.getTopLeft(find.text('와인웍스')).dy),
    );
  });

  testWidgets('현재 층에 없으면 그렇다고 적고 다른 층을 잇는다', (tester) async {
    buildingRepository = _FloorStoresRepository(const {
      'B1': [('와인웍스', null)],
      '1F': <(String, String?)>[],
    });

    await _openSheet(tester, currentFloor: '1F');

    // 묶음을 통째로 빼면 "이 층에 없음"과 "목록이 고장남"이 구분되지 않는다.
    expect(find.text('현재 층 · 1F'), findsOneWidget);
    expect(find.text('이 층에는 없습니다.'), findsOneWidget);
    expect(find.text('와인웍스'), findsOneWidget);
  });

  testWidgets('층 개념이 없으면(야외) 나누지 않는다', (tester) async {
    buildingRepository = _FloorStoresRepository(const {
      'B1': [('와인웍스', null)],
      '1F': [('현대베이커리', null)],
    });

    await _openSheet(tester, currentFloor: null);

    expect(find.text('다른 층'), findsNothing);
    expect(find.text('와인웍스'), findsOneWidget);
    expect(find.text('현대베이커리'), findsOneWidget);
  });

  testWidgets('결과가 현재 층에만 있으면 머리글을 붙이지 않는다', (tester) async {
    buildingRepository = _FloorStoresRepository(const {
      '1F': [('현대베이커리', null)],
    });

    await _openSheet(tester, currentFloor: '1F');

    expect(find.text('현재 층 · 1F'), findsNothing);
    expect(find.text('다른 층'), findsNothing);
    expect(find.text('현대베이커리'), findsOneWidget);
  });

  testWidgets('층을 거르는 토글은 없다', (tester) async {
    buildingRepository = _FloorStoresRepository(const {
      'B1': [('와인웍스', null)],
      '1F': [('현대베이커리', null)],
    });

    await _openSheet(tester, currentFloor: '1F');

    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('시트 안에 검색창은 없다', (tester) async {
    // 상단 바에 이미 검색창이 있다. 시트가 또 하나를 들고 있으면 같은 일을
    // 하는 입력이 화면에 둘이 되고, 어느 쪽이 지금 목록을 거르는지 흐려진다.
    // 이 시트는 "대분류 안을 훑는" 화면이고 좁히는 수단은 소분류 pill이다.
    buildingRepository = _FloorStoresRepository(const {
      '1F': [('와인웍스', '와인·주류'), ('현대베이커리', '식품·그로서리')],
    });

    await _openSheet(tester, currentFloor: '1F');

    expect(find.byType(TextField), findsNothing);
    // pill 줄은 그대로 남는다 — 좁힐 수단까지 같이 사라지면 안 된다.
    expect(find.text('전체'), findsOneWidget);
  });

  testWidgets('소분류 pill을 누르면 목록이 좁아지고 상위에도 알린다', (tester) async {
    // 이 pill은 예전에 지도 위에 있던 줄이다. 시트로 옮기면서 **지도 강조까지
    // 같이 바꾸는 책임**도 함께 왔다 — 상위에 알리지 않으면 시트엔 한 곳,
    // 지도엔 세 곳이 칠해진 채로 갈라진다.
    buildingRepository = _FloorStoresRepository(const {
      '1F': [('와인웍스', '와인·주류'), ('현대베이커리', '식품·그로서리')],
    });
    final reported = <Object?>[];

    await _openSheet(
      tester,
      currentFloor: '1F',
      onSubcategoryChanged: reported.add,
    );

    expect(find.text('와인·주류'), findsOneWidget);
    await tester.tap(find.text('와인·주류'));
    await tester.pumpAndSettle();

    expect(find.text('와인웍스'), findsOneWidget);
    expect(find.text('현대베이커리'), findsNothing);
    expect(reported, ['와인·주류']);

    // 같은 pill을 다시 누르면 대분류 전체로 되돌아온다.
    await tester.tap(find.text('와인·주류'));
    await tester.pumpAndSettle();
    expect(find.text('현대베이커리'), findsOneWidget);
    expect(reported, ['와인·주류', null]);
  });

  testWidgets('맨 위 매장을 상위에 알린다 — 현재 층 것만', (tester) async {
    // 상위는 이 값으로 지도 카메라를 옮긴다. 다른 층 매장을 올리면 카메라가
    // 층을 갈아타야 하고, 그러면 시트 머리글이 말하는 층과 지도가 어긋난다.
    buildingRepository = _FloorStoresRepository(const {
      'B1': [('와인웍스', '와인·주류')],
      '1F': [('현대베이커리', '식품·그로서리')],
    });
    final focused = <String?>[];

    await _openSheet(
      tester,
      currentFloor: '1F',
      onFirstStoreChanged: (store) => focused.add(store?.name),
    );

    expect(focused, ['현대베이커리']);

    // 소분류로 좁혀 현재 층 결과가 사라지면 카메라를 붙들 대상도 사라진다.
    await tester.tap(find.text('와인·주류'));
    await tester.pumpAndSettle();
    expect(focused, ['현대베이커리', null]);
  });

  testWidgets('현재 층에 없으면 첫 매장으로 null을 올린다', (tester) async {
    buildingRepository = _FloorStoresRepository(const {
      'B1': [('와인웍스', null)],
      '1F': <(String, String?)>[],
    });
    final focused = <String?>[];

    await _openSheet(
      tester,
      currentFloor: '1F',
      onFirstStoreChanged: (store) => focused.add(store?.name),
    );

    expect(focused, [null]);
  });
}

void _resizeTo(Size size) {
  final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
  view.physicalSize = size;
  view.devicePixelRatio = 1.0;
  addTearDown(() {
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });
}

Future<void> _openSheet(
  WidgetTester tester, {
  required String? currentFloor,
  ValueChanged<String?>? onSubcategoryChanged,
  ValueChanged<PoiSearchResult?>? onFirstStoreChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => CategoryStoresSheet.show(
              context,
              buildingId: 'test-building',
              category: '식품관',
              onCloseAll: () {},
              currentFloor: currentFloor,
              onSubcategoryChanged: onSubcategoryChanged,
              onFirstStoreChanged: onFirstStoreChanged,
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// 층별 매장(이름·소분류)만 받아 백엔드 층 응답 형태로 돌려주는 리포지토리.
/// 목업 asset(assets/mock/sample_building.json)에는 대분류가 붙은 매장이 아예
/// 없어서 이 시트를 데이터로 검증할 수 없다.
class _FloorStoresRepository extends MockBuildingRepository {
  _FloorStoresRepository(this.storesByFloor);

  /// 층 라벨 → 그 층의 (매장 이름, 소분류). 실제 응답과 같이 **위층부터**
  /// 넘겨도 시트가 아래층부터 정렬하는지 함께 드러나도록 순서를 그대로 쓴다.
  final Map<String, List<(String, String?)>> storesByFloor;

  @override
  Future<Building?> getBuilding(String buildingId) async => Building(
        id: buildingId,
        name: '테스트 건물',
        floors: storesByFloor.keys.toList(),
      );

  @override
  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  ) async {
    final stores = storesByFloor[floor] ?? const <(String, String?)>[];
    return {
      'footprint_wgs84': <dynamic>[],
      'stores': [
        for (var i = 0; i < stores.length; i++)
          {
            'id': '$floor-$i',
            'name': stores[i].$1,
            'category': '식품관',
            'subcategory': stores[i].$2,
            'centroid_wgs84': {'lat': 37.5, 'lng': 127.0},
          },
      ],
      'pois': <dynamic>[],
    };
  }
}
