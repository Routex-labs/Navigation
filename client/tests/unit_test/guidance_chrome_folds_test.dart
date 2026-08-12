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
import 'package:navigation_client/widgets/map_bottom_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 안내가 시작되면 지도 위 사전 조작 chrome을 접는지에 대한 회귀 테스트.
///
/// 프로모션 영상의 안내 화면은 지도와 안내 카드만 남는다. 그걸 옮기면서 지켜야
/// 하는 불변식은 하나다 — **접는 조건은 빠져나갈 수단이 있는 조건과 같아야
/// 한다.** 접힌 화면에서 종료 버튼까지 없으면 사용자가 갇힌다.
///
/// 판정 자체(어떤 상태에서 접는지)는 `test/domain/guidance_chrome_test.dart`가
/// 경우별로 못 박는다. 여기서는 그 판정이 **실제 화면에 배선됐는지**를 본다 —
/// 안내를 시작하면 접히고, 끝내면 되돌아오는지.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

  /// 건물 **밖** 좌표(외곽선에서 약 185 m 동쪽).
  ///
  /// 입구와 같은 좌표를 쓰면 지금 진입 판정에서는 곧바로 실내로 들어간다
  /// (judgeBuildingFromGps — 믿을 수 있는 좌표가 외곽선 안). 그러면 출발지
  /// 기준이 PDR 앵커로 바뀌어 "도착"이 경로를 그리지 못하고, 이 테스트가
  /// 보려는 chrome 접기까지 가지 못한다.
  Position fix() => Position(
    latitude: 37.5665,
    longitude: 126.9800,
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

  /// 안내를 시작하기 **전** 상태까지만 띄운다. 접히기 전에 무엇이 있었는지
  /// 확인해야 "접혔다"가 의미를 갖는다 — 원래 없던 걸 없다고 하면 통과해 버린다.
  Future<void> pumpShell(WidgetTester tester) async {
    // broadcast여야 한다. 화면이 상황에 따라 위치를 다시 구독하는데, 단일 구독
    // 스트림은 취소 뒤 재구독하면 'already been listened to'로 터진다.
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    await tester.pumpWidget(const MaterialApp(home: MapShellScreen()));
    await drain(tester);
    positions.add(fix());
    await drain(tester);
  }

  Future<void> startGuidance(WidgetTester tester) async {
    await pumpShell(tester);

    await tester.tap(find.byType(TextField).first);
    await drain(tester);
    await tester.enterText(find.byType(TextField).first, '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    await tester.tap(find.text('도착'));
    await drain(tester);
  }

  testWidgets('안내를 시작하면 하단 바가 접히고, 빠져나갈 종료 버튼이 남는다', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    expect(
      find.byType(MapBottomBar),
      findsOneWidget,
      reason: '테스트 전제(안내 전에는 하단 바가 있음)가 성립하지 않았다',
    );

    await startGuidance(tester);

    expect(
      find.byType(EtaCard),
      findsOneWidget,
      reason: '테스트 전제(도착을 누르면 경로가 그려짐)가 성립하지 않았다',
    );
    expect(
      find.byType(MapBottomBar),
      findsNothing,
      reason: '안내 중에는 위치 지정·위치 보정 버튼을 접어 지도를 비워야 한다',
    );
    // 접었으면 반드시 나갈 구멍이 있어야 한다. 이 둘은 한 쌍이다.
    expect(
      find.descendant(
        of: find.byType(EtaCard),
        matching: find.textContaining('종료'),
      ),
      findsOneWidget,
      reason: 'chrome을 접었는데 종료 버튼이 없으면 사용자가 화면에서 빠져나갈 수단을 잃는다',
    );
  });

  testWidgets('안내를 끝내면 접었던 하단 바가 돌아온다', (WidgetTester tester) async {
    await startGuidance(tester);
    expect(find.byType(MapBottomBar), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(EtaCard),
        matching: find.textContaining('종료'),
      ),
    );
    await drain(tester);

    expect(
      find.byType(EtaCard),
      findsNothing,
      reason: '종료를 눌렀으면 안내 카드가 사라져야 한다',
    );
    expect(
      find.byType(MapBottomBar),
      findsOneWidget,
      reason: '안내가 끝나면 접었던 chrome이 되돌아와야 한다 — 안 돌아오면 조작 수단이 영구히 사라진다',
    );
  });

  testWidgets('안내 중에도 상단 초안 바는 남아 도착지를 바꿀 수 있다', (WidgetTester tester) async {
    await startGuidance(tester);

    // 상단 바는 안내 중에 검색창이 아니라 출발/도착 초안 바로 바뀐다. 이건
    // 접어야 할 사전 조작 chrome이 아니라 "지금 어디로 가는 중"인지를 적는
    // 안내 UI이고, 길안내 중 도착지를 바꾸는 유일한 진입점이다.
    expect(
      find.byKey(const Key('route-draft-destination')),
      findsOneWidget,
      reason: '접으면 도착지를 바꾸려고 안내를 먼저 끝내야 하는 화면이 된다',
    );
  });
}
