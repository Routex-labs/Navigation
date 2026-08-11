import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/repositories/building_repository.dart';
import 'package:navigation_client/repositories/destination_repository.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 상단 초안 바의 ⇅(출발↔도착 바꾸기)가 **실제로 반대 방향 경로를 다시 그리는지**
/// 에 대한 회귀 테스트.
///
/// 라벨만 뒤바뀌고 경로는 그대로면 사용자는 뒤집혔다고 믿은 채 원래 방향으로
/// 걷게 된다. 그래서 검증은 초안 바의 글자가 아니라 **ETA 카드가 가리키는
/// 도착지**로 한다 — 카드는 실제로 계산된 경로를 따라 그려지기 때문이다.
/// 판정 규칙 자체(무엇을 고르고 언제 못 고르는지)는
/// `test/domain/route_endpoint_swap_test.dart`가 경우별로 못 박는다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

  Position fix() => Position(
    latitude: 37.5665,
    longitude: 126.9779,
    timestamp: DateTime(2024, 1, 1),
    accuracy: 10,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

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
    watchPosition = defaultWatchPosition;
  });

  /// 출발지·도착지가 **둘 다 실제 지점**인 경로를 만든다. 뒤집기의 기본 경우다
  /// (현재 위치를 매장으로 굳히는 분기를 타지 않는다).
  Future<void> startRouteBetweenTwoPlaces(WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    await tester.pumpWidget(const MaterialApp(home: MapShellScreen()));
    await drain(tester);
    positions.add(fix());
    await drain(tester);

    // 도착지 먼저 정해 초안 바를 띄운다.
    await tester.tap(find.byType(TextField).first);
    await drain(tester);
    await tester.enterText(find.byType(TextField).first, '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    await tester.tap(find.text('도착'));
    await drain(tester);

    // 출발 행 → 시트에서 출발지를 실제 지점으로 채운다. 시트의 입력창은
    // [출발지, 도착지] 순서다.
    await tester.tap(find.byKey(const Key('route-draft-origin')));
    await drain(tester);
    await tester.enterText(find.byType(TextField).at(0), '데모');
    await drain(tester);
    await tester.tap(
      find
          .descendant(of: find.byType(ListTile), matching: find.text('데모 건물'))
          .first,
    );
    await drain(tester);
  }

  testWidgets('⇅를 누르면 출발지와 도착지가 뒤바뀌고 반대 방향 경로가 다시 그려진다', (
    WidgetTester tester,
  ) async {
    await startRouteBetweenTwoPlaces(tester);

    expect(
      find.descendant(of: find.byType(EtaCard), matching: find.text('강의실 101')),
      findsOneWidget,
      reason: '테스트 전제(뒤집기 전 도착지가 강의실 101)가 성립하지 않았다',
    );

    await tester.tap(find.byKey(const Key('route-draft-swap')));
    await drain(tester);

    // 초안 바의 두 줄이 서로 자리를 바꿨다.
    expect(
      find.descendant(
        of: find.byKey(const Key('route-draft-origin')),
        matching: find.text('강의실 101'),
      ),
      findsOneWidget,
      reason: '뒤집었으면 이전 도착지가 출발지 줄로 올라와야 한다',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('route-draft-destination')),
        matching: find.text('데모 건물'),
      ),
      findsOneWidget,
      reason: '뒤집었으면 이전 출발지가 도착지 줄로 내려와야 한다',
    );

    // 그리고 **경로가 실제로 다시 계산됐다.** 라벨만 바뀌고 카드가 이전
    // 도착지를 가리키면 화면과 실제 안내가 어긋난 것이다.
    expect(
      find.descendant(of: find.byType(EtaCard), matching: find.text('데모 건물')),
      findsOneWidget,
      reason: '끝점을 뒤집었으면 경로를 끊지 말고 곧바로 반대 방향으로 다시 그려야 한다',
    );
  });

  testWidgets('출발지가 현재 위치이고 측위가 없으면 ⇅는 비활성이다', (WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    await tester.pumpWidget(const MaterialApp(home: MapShellScreen()));
    await drain(tester);
    positions.add(fix());
    await drain(tester);

    await tester.tap(find.byType(TextField).first);
    await drain(tester);
    await tester.enterText(find.byType(TextField).first, '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    await tester.tap(find.text('도착'));
    await drain(tester);

    // 출발지는 "현재 위치"(= _selectedOrigin이 null)이고, 이 테스트 환경에는
    // 실내 도달 거리 맵이 없다. 대신 놓을 매장을 고를 근거가 없으므로 눌러도
    // 아무 일도 하지 않는 버튼이 되어서는 안 된다.
    final button = tester.widget<IconButton>(
      find.byKey(const Key('route-draft-swap')),
    );
    expect(button.onPressed, isNull, reason: '고를 근거가 없으면 활성처럼 보여서는 안 된다');
  });
}
