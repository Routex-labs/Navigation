import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/repositories/building_repository.dart';
import 'package:navigation_client/repositories/destination_repository.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/widgets/building_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 밖에서 **건물을 목적지로 검색했을 때** 화면(MapShellScreen)이 어떤 상태로
/// 넘어가는지에 대한 회귀 테스트.
///
/// 가장 깨지기 쉬운 지점은 **고르고 나서 아무 데도 못 가는 것**이다. 예전에는
/// 건물 줄을 누르면 이름과 층 수를 적은 카드만 떴고, 거기서 사용자가 할 수 있는
/// 일이 하나도 없었다 — 길찾기로도, 건물 안으로도 이어지지 않았다.
///
/// 건물은 좌표 하나가 아니라 "안에 매장이 있는 곳"이라, 갈 곳이 두 갈래로
/// 갈린다. 어느 쪽을 골라도 **다음 화면이 실제로 이어지는지**를 확인한다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalBuildingRepository = buildingRepository;
    originalDestinationRepository = destinationRepository;
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    requestStartupPermissions = () async => {};
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
  });

  /// 상단 검색창에 건물 이름을 치고, 결과의 건물 줄을 눌러 시트까지 간다.
  ///
  /// 건물 줄은 검색어 강조 때문에 이름이 `Text.rich`라 `find.text`로 못 잡는다.
  /// 그래서 그 줄의 leading 아이콘으로 찾는다.
  Future<void> openBuildingSheet(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapShellScreen()));
    await drain(tester);

    await tester.enterText(find.byType(TextField).first, '데모');
    await drain(tester);
    expect(
      find.byIcon(Icons.apartment_outlined),
      findsOneWidget,
      reason: '테스트 전제(검색 결과에 건물 줄이 있음)가 성립하지 않았다',
    );

    await tester.tap(find.byIcon(Icons.apartment_outlined));
    await drain(tester);
  }

  testWidgets('건물을 고르면 갈 곳을 묻는 시트가 뜬다', (WidgetTester tester) async {
    await openBuildingSheet(tester);

    expect(find.byType(BuildingSheet), findsOneWidget);
    // 두 갈래가 모두 보여야 한다. 하나만 있으면 사용자는 나머지 의도를 이룰
    // 방법이 없다 — 묻지 않은 것과 같다.
    expect(find.text('건물 안에서 매장 고르기'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('building-set-destination')),
      findsOneWidget,
    );
  });

  testWidgets('매장 고르기를 누르면 지도에서 고르는 상태로 넘어간다', (WidgetTester tester) async {
    await openBuildingSheet(tester);

    await tester.tap(find.text('건물 안에서 매장 고르기'));
    await drain(tester);

    expect(find.byType(BuildingSheet), findsNothing);
    // 시트만 닫히고 끝나면 사용자는 버튼이 먹지 않은 것으로 본다.
    expect(find.textContaining('도착지로 지정할 매장을 지도에서 눌러주세요'), findsOneWidget);
  });

  testWidgets('도착을 누르면 건물이 도착지로 잡힌다', (WidgetTester tester) async {
    await openBuildingSheet(tester);

    // 좁은 뷰포트에서는 액션 줄이 시트의 초기 높이 아래에 있을 수 있다. 여기서
    // 확인하려는 것은 레이아웃이 아니라 흐름이므로 먼저 보이게 만든다.
    final destinationButton = find.byKey(
      const ValueKey('building-set-destination'),
    );
    await tester.ensureVisible(destinationButton);
    await tester.pump();
    await tester.tap(destinationButton);
    await drain(tester);

    expect(find.byType(BuildingSheet), findsNothing);
    // 상단 초안 바에 남아야 한다 — 출발 위치가 아직 없어 경로가 안 그려져도
    // 방금 고른 목적지가 화면에서 사라지면 안 된다.
    expect(find.textContaining('데모 건물', findRichText: true), findsWidgets);
  });
}
