import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/repositories/building_repository.dart';
import 'package:navigation_client/repositories/destination_repository.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "지도에서 선택"을 누른 뒤 화면(MapShellScreen)이 어떤 상태로 넘어가는지에
/// 대한 회귀 테스트.
///
/// 가장 깨지기 쉬운 지점은 **시트가 닫힌 뒤 아무 표시도 남지 않는 것**이다.
/// 그러면 사용자는 방금 누른 버튼이 먹지 않은 것으로 보고, 다음에 매장을
/// 눌렀을 때 매장 정보 시트 대신 경로가 그려지는 이유도 알 수 없다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
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

  /// 상단 바 길찾기 아이콘으로 시트를 연 뒤 "지도에서 선택"을 누른다.
  Future<void> pickOnMap(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapShellScreen()));
    await drain(tester);

    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    expect(
      find.text('지도에서 선택'),
      findsOneWidget,
      reason: '테스트 전제(길찾기 시트 열림)가 성립하지 않았다',
    );

    await tester.tap(find.text('지도에서 선택'));
    await drain(tester);
  }

  testWidgets('지도에서 선택을 누르면 지도 위에 안내가 남는다', (WidgetTester tester) async {
    await pickOnMap(tester);

    // 시트는 닫히고,
    expect(find.text('지도에서 선택'), findsNothing);
    // 지금 무엇을 해야 하는지는 지도 위에 남는다.
    expect(find.textContaining('도착지로 지정할 매장이나 복도를 지도에서 눌러주세요'), findsOneWidget);
    // 출발지가 무엇으로 잡혀 있는지도 함께 보여준다.
    expect(find.textContaining('출발: 현재 위치'), findsOneWidget);
  });

  testWidgets('안내의 X를 누르면 지도에서 고르기를 그만둔다', (WidgetTester tester) async {
    // 빠져나갈 길이 없으면, 마음이 바뀐 사용자는 매장을 눌러 원치 않는 경로를
    // 그리는 것 말고 선택지가 없다.
    await pickOnMap(tester);

    await tester.tap(find.byTooltip('지도에서 선택 취소'));
    await drain(tester);

    expect(find.textContaining('도착지로 지정할 매장이나 복도를 지도에서 눌러주세요'), findsNothing);
  });

  testWidgets('검색을 시작하면 지도에서 고르기가 풀린다', (WidgetTester tester) async {
    // 안내만 남으면, 검색 결과로 목적지를 정한 뒤에도 다음 매장 탭이 도착지로
    // 먹혀 엉뚱한 경로가 그려진다.
    await pickOnMap(tester);

    await tester.tap(find.byType(TextField).first);
    await drain(tester);
    await tester.tap(find.byTooltip('검색 닫기'));
    await drain(tester);

    expect(find.textContaining('도착지로 지정할 매장이나 복도를 지도에서 눌러주세요'), findsNothing);
  });
}
