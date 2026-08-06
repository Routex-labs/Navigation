import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/repositories/building_repository.dart';
import 'package:navigation_client/repositories/destination_repository.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 상단 초안 바에서 어느 행을 눌렀는지에 따라 길찾기 시트가 그 칸을 활성으로
/// 열어야 한다는 테스트.
///
/// 지키려는 증상: **출발 행을 눌렀는데 도착지 칸이 활성인 채로 열리는 것.** 그러면
/// 후보 목록도 도착지 기준이라, 출발지를 바꾸려던 사용자는 시트 안에서 출발지 칸을
/// 한 번 더 눌러야 한다. 방금 누른 곳과 커서가 있는 곳이 다르다.
///
/// 활성 칸은 후보 목록으로 구분한다 — 출발지가 활성일 때만 맨 위에 "현재 위치"
/// 고정 행이 붙는다.
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

  /// 도착지를 정해 상단 초안 바가 뜬 상태를 만든다. 경로 계산까지 갈 필요는
  /// 없으므로(GPS 없음) 초안 바가 떴는지만 확인한다.
  Future<void> openRouteDraft(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapShellScreen()));
    await drain(tester);

    await tester.tap(find.byType(TextField).first);
    await drain(tester);
    await tester.enterText(find.byType(TextField).first, '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    await tester.tap(find.text('도착'));
    await drain(tester);

    expect(
      find.byKey(const Key('route-draft-origin')),
      findsOneWidget,
      reason: '테스트 전제(상단 초안 바가 뜸)가 성립하지 않았다',
    );
  }

  /// 후보 목록의 "현재 위치" 고정 행. 출발지 칸이 활성일 때만 붙는다. 상단 초안
  /// 바에도 같은 문구가 있으므로 목록 항목(ListTile)으로 좁힌다.
  Finder currentLocationRow() => find.descendant(
    of: find.byType(ListTile),
    matching: find.text('현재 위치'),
  );

  testWidgets('출발 행을 누르면 출발지 칸이 활성인 채로 시트가 열린다', (
    WidgetTester tester,
  ) async {
    await openRouteDraft(tester);

    await tester.tap(find.byKey(const Key('route-draft-origin')));
    await drain(tester);

    expect(
      currentLocationRow(),
      findsOneWidget,
      reason: '출발 행을 눌렀으면 후보 목록이 출발지 기준이어야 한다',
    );
    // 출발지 칸에 적혀 있던 "현재 위치"는 값이 아니라 안내문이므로 비워, 사용자가
    // 먼저 지우지 않고 바로 칠 수 있어야 한다.
    expect(find.text('출발지를 입력하세요'), findsOneWidget);
  });

  testWidgets('도착 행을 누르면 도착지 칸이 활성인 채로 열린다', (
    WidgetTester tester,
  ) async {
    // 기본 흐름이 뒤집히지 않는지 함께 고정한다.
    await openRouteDraft(tester);

    await tester.tap(find.byKey(const Key('route-draft-destination')));
    await drain(tester);

    expect(
      currentLocationRow(),
      findsNothing,
      reason: '도착 행을 눌렀는데 출발지 후보 목록이 나왔다',
    );
  });
}
