import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/models/category_count.dart';
import 'package:navigation_client/repositories/building_repository.dart';
import 'package:navigation_client/repositories/destination_repository.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/widgets/category_stores_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 지도 위 대분류 chip을 누르면 **그 자리에서** 매장 목록 시트가 뜨는지 고정한다.
///
/// 예전에는 chip → 소분류 pill 줄 → 「목록」 버튼까지 세 번을 눌러야 이름을 볼
/// 수 있었다. 지도 강조는 "저 파란 칸이 뭔지"에 답하지 못하는데 정작 답이 있는
/// 목록이 가장 멀었다. 중간 단계가 다시 끼어들면 이 회귀가 그대로 돌아온다.
void main() {
  late BuildingRepository originalBuilding;
  late DestinationRepository originalDestination;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    originalBuilding = buildingRepository;
    originalDestination = destinationRepository;
    final repository = _CategorizedBuildingRepository();
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    // asset 캐시를 미리 채운다. 위젯 테스트의 가짜 시계는 실제 파일 I/O를
    // 기다려 주지 않아, 캐시가 비어 있으면 칩 줄이 뜨지 않는다.
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuilding;
    destinationRepository = originalDestination;
  });

  testWidgets('카테고리 chip을 누르면 매장 목록 시트가 바로 뜬다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapShellScreen()));
    await tester.pumpAndSettle();
    // 카테고리 칩은 건물 안을 보고 있을 때만 뜬다.
    await tester.tap(find.text('실내'));
    await tester.pumpAndSettle();

    expect(find.text('서비스'), findsOneWidget);
    await tester.tap(find.text('서비스'));
    await tester.pumpAndSettle();

    // 시트 고유의 표시 — 매장 이름.
    expect(find.text('우리은행 ATM'), findsOneWidget);
    // 시트 안 검색창은 없앴다. 상단 바에 이미 검색이 있는데 시트가 또 하나를
    // 들고 있으면 같은 일을 하는 입력이 화면에 둘이 된다(상단 바 것은 남는다).
    expect(
      find.descendant(
        of: find.byType(CategoryStoresSheet),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
    // 지도 위 「목록」 버튼은 사라졌다. 시트가 바로 뜨는데 한 단계를 더 두면
    // 같은 목적지로 가는 길이 두 개가 된다.
    expect(find.text('목록'), findsNothing);
  });
}

/// 목업 asset 건물에 대분류가 붙은 매장을 얹는다.
/// `assets/mock/sample_building.json`에는 category가 달린 매장이 하나도 없어
/// 그대로 쓰면 칩 줄 자체가 뜨지 않는다.
class _CategorizedBuildingRepository extends MockBuildingRepository {
  static const _storesByFloor = {
    '1F': ['우리은행 ATM'],
    '2F': ['신한은행 ATM'],
  };

  @override
  Future<List<CategoryCount>?> getCategoryCounts(String buildingId) async => [
        for (final entry in _storesByFloor.entries)
          CategoryCount(
            floor: entry.key,
            category: '서비스',
            subcategory: 'ATM',
            count: entry.value.length,
          ),
      ];

  @override
  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  ) async {
    final names = _storesByFloor[floor] ?? const <String>[];
    return {
      'footprint_wgs84': <dynamic>[],
      'stores': [
        for (var i = 0; i < names.length; i++)
          {
            'id': '$floor-$i',
            'name': names[i],
            'category': '서비스',
            'subcategory': 'ATM',
            'centroid_wgs84': {'lat': 37.5665, 'lng': 126.978},
          },
      ],
      'pois': <dynamic>[],
    };
  }
}
