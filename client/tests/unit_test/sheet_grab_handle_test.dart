import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/api_config.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/models/favorite_place.dart';
import 'package:navigation_client/repositories/building_repository.dart';
import 'package:navigation_client/repositories/destination_repository.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';
import 'package:navigation_client/widgets/app_menu_sheet.dart';
import 'package:navigation_client/widgets/category_stores_sheet.dart';
import 'package:navigation_client/widgets/directions_sheet.dart';
import 'package:navigation_client/widgets/favorites_sheet.dart';
import 'package:navigation_client/widgets/place_detail_sheet.dart';
import 'package:navigation_client/widgets/sheet_grab_handle.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 아래에서 올라오는 모달 바텀 시트에 크기 조절 손잡이가 빠지지 않는지 고정한다.
///
/// 손잡이가 없으면 시트가 고정 높이 카드처럼 보여서, 목록이 잘려 있어도
/// 사용자가 위로 끌어 올릴 수 있다는 걸 모른 채 스크롤만 하게 된다. 시트가
/// 늘어날 때마다 하나씩 빠지기 쉬운 표시라 각 시트를 열어 직접 확인한다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    originalBuildingRepository = buildingRepository;
    originalDestinationRepository = destinationRepository;
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    // asset 캐시를 미리 채운다. 위젯 테스트의 가짜 시계는 실제 파일 I/O를
    // 기다려 주지 않아, 캐시가 비어 있으면 시트가 로딩 상태에 머문다.
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
  });

  /// [open]이 여는 시트를 띄우고 손잡이가 있는지 확인한다.
  Future<void> expectGrabHandle(
    WidgetTester tester,
    void Function(BuildContext context) open,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SheetGrabHandle), findsOneWidget);
  }

  testWidgets('매장 상세 시트에 손잡이가 있다', (WidgetTester tester) async {
    await expectGrabHandle(
      tester,
      (context) => PlaceDetailSheet.show(
        context,
        title: 'MLB',
        subtitle: 'B2',
        buildingId: demoBuildingId,
        // 상세를 부르지 않는 경로(구버전 저장 항목)로 열어 손잡이만 본다.
        placeId: null,
        onCloseAll: () {},
      ),
    );
  });

  testWidgets('카테고리 매장 목록 시트에 손잡이가 있다', (WidgetTester tester) async {
    await expectGrabHandle(
      tester,
      (context) => CategoryStoresSheet.show(
        context,
        buildingId: demoBuildingId,
        category: '패션',
        onCloseAll: () {},
      ),
    );
  });

  testWidgets('저장한 장소 시트에 손잡이가 있다', (WidgetTester tester) async {
    await expectGrabHandle(
      tester,
      (context) => FavoritesSheet.show(context, onCloseAll: () {}),
    );
  });

  testWidgets('길찾기 시트에 손잡이가 있다', (WidgetTester tester) async {
    await expectGrabHandle(
      tester,
      (context) => DirectionsSheet.show(
        context,
        originLabel: '현재 위치',
        search: (query, {String? floorId}) async => const [
          DirectionsCandidate(
            title: 'MLB',
            subtitle: 'B2',
            point: LatLng(37.52, 126.92),
          ),
        ],
      ),
    );
  });

  testWidgets('앱 메뉴 시트에 손잡이가 있다', (WidgetTester tester) async {
    await expectGrabHandle(
      tester,
      (context) => AppMenuSheet.show(
        context,
        showPlaceLocation: true,
        debugEnabled: false,
      ),
    );
  });

  testWidgets('손잡이는 시트 콘텐츠보다 위에 그려진다', (WidgetTester tester) async {
    // 자리를 안 지키면(예: 헤더 아래) 표시의 의미가 사라진다. 매장 상세 시트를
    // 기준으로 세로 위치를 고정한다.
    await expectGrabHandle(
      tester,
      (context) => PlaceDetailSheet.show(
        context,
        title: 'MLB',
        subtitle: 'B2',
        buildingId: demoBuildingId,
        // 상세를 부르지 않는 경로(구버전 저장 항목)로 열어 손잡이만 본다.
        placeId: null,
        onCloseAll: () {},
      ),
    );

    final handleBottom = tester.getRect(find.byType(SheetGrabHandle)).bottom;
    final titleTop = tester.getRect(find.text('MLB')).top;
    expect(handleBottom, lessThan(titleTop));
  });

  testWidgets('저장한 장소가 있어도 손잡이는 목록 위에 남는다', (WidgetTester tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await favoritesController.add(
      const FavoritePlace(
        name: 'MLB',
        floor: 'B2',
        buildingId: demoBuildingId,
        lat: 37.52,
        lng: 126.92,
      ),
    );

    await expectGrabHandle(
      tester,
      (context) => FavoritesSheet.show(context, onCloseAll: () {}),
    );

    final handleBottom = tester.getRect(find.byType(SheetGrabHandle)).bottom;
    final headerTop = tester.getRect(find.text('저장한 장소')).top;
    expect(handleBottom, lessThan(headerTop));
  });
}
