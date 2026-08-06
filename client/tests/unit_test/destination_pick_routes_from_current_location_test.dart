import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/repositories/building_repository.dart';
import 'package:navigation_client/repositories/destination_repository.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 매장 정보 시트의 "도착"을 눌렀을 때 경로 계산까지 실제로 이어지는지에 대한
/// 회귀 테스트.
///
/// 지키려는 증상: **출발지를 명시적으로 고르지 않았을 때 아무 일도 안 일어나는
/// 것.** 상위 화면은 "출발지 = 현재 위치"를 `_selectedOrigin == null`로 표현하는데,
/// 같은 null이 "출발지가 아직 없음"도 뜻한다. 이 둘을 구분하지 않고 "null이면
/// 계산하지 않는다"로 묶으면, 위치 지정으로 현재 위치를 찍어둔 사용자가 매장에서
/// "도착"을 눌러도 도착 초안만 저장되고 경로가 그려지지 않는다.
///
/// 여기서는 야외 컨텍스트로 검증한다. 야외의 출발지는 GPS이고 테스트에는 GPS가
/// 없으므로, 계산까지 이어졌다는 증거는 야외 화면이 돌려주는 **"현재 위치를 아직
/// 못 잡았습니다"** 안내다. 그 안내가 뜨면 `_startRoute`가 불렸다는 뜻이고, 아무
/// 안내도 없으면 호출 자체가 막힌 것이다 — 이 테스트가 잡으려는 상태가 그것이다.
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

  /// 상단 검색으로 건물을 찾아 건물 시트를 띄운다.
  ///
  /// 매장이 아니라 건물을 쓰는 이유는, 밖에서의 검색이 건물만 찾기 때문이다
  /// (`SearchPanel.indoorContextActive`). 여기서 확인하려는 것은 "무엇을
  /// 골랐는가"가 아니라 **출발지를 안 골랐을 때도 계산까지 가는가**이므로,
  /// 밖에서 실제로 고를 수 있는 대상으로 검증하는 편이 맞다.
  Future<void> openBuildingSheetBySearch(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapShellScreen()));
    await drain(tester);

    await tester.tap(find.byType(TextField).first);
    await drain(tester);
    await tester.enterText(find.byType(TextField).first, '데모');
    await drain(tester);

    final result = find.byIcon(Icons.apartment_outlined);
    expect(result, findsOneWidget, reason: '테스트 전제(검색 결과에 건물 줄이 나옴)가 성립하지 않았다');
    await tester.tap(result);
    await drain(tester);

    expect(
      find.byKey(const ValueKey('building-set-destination')),
      findsOneWidget,
      reason: '테스트 전제(건물 시트 열림)가 성립하지 않았다',
    );
  }

  /// 시트의 "도착". 좁은 뷰포트에서는 초기 높이 아래에 있을 수 있어 먼저
  /// 보이게 만든다.
  Future<void> tapDestination(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('building-set-destination'));
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await drain(tester);
  }

  testWidgets('출발지를 고르지 않아도 "도착"을 누르면 경로 계산으로 이어진다', (
    WidgetTester tester,
  ) async {
    await openBuildingSheetBySearch(tester);

    await tapDestination(tester);

    // 계산까지 이어졌다는 증거. 이 안내가 없으면 "도착을 눌렀는데 아무 일도
    // 안 일어남"이고, 그게 이 테스트가 막으려는 회귀다.
    expect(
      find.textContaining('현재 위치를 아직 못 잡았습니다'),
      findsOneWidget,
      reason: '출발지가 null(=현재 위치)이라는 이유로 경로 계산이 건너뛰어졌다',
    );
  });

  testWidgets('상단 출발 행은 매장을 안 골랐어도 "현재 위치"로 적는다', (WidgetTester tester) async {
    // 같은 null 겹침이 라벨에서도 드러난다. 상위가 출발지를 null로 넘기면 상단
    // 바는 "출발지를 선택하세요" placeholder를 띄우는데, 그건 위치를 방금 찍어둔
    // 사용자에게 출발지가 비어 있다고 잘못 알리는 것이다. 그 상태에서는 출발 행을
    // 눌러 매장을 고르지 않는 한 문구가 바뀌지 않아, 위치 지정이 무시된 것처럼 보인다.
    await openBuildingSheetBySearch(tester);

    await tapDestination(tester);

    expect(
      find.text('출발지를 선택하세요'),
      findsNothing,
      reason: '현재 위치를 출발지로 쓸 수 있는데도 출발지가 비어 있다고 표시했다',
    );
    expect(find.text('현재 위치'), findsOneWidget);
  });
}
