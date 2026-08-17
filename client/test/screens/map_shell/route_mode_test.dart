import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:navigation_client/screens/map_shell/widgets/search/route_field_results.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 길찾기가 **상단 바 안에서** 끝나는지에 대한 회귀 테스트.
///
/// 한동안 길찾기는 전체 화면(`screens/route_planner/`)이었다. 지도를 새로 만들지
/// 않으려고 오버레이로 얹었지만 화면이 통째로 바뀌는 것은 마찬가지라, 목적지를
/// 고치려면 지도를 잃고 그 화면을 다시 열어야 했다. 지금은 상단 바가 출발/도착
/// 두 칸이 되고 그 아래에 이동 수단 줄이 붙는다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

  // 건물 밖 좌표(외곽선에서 약 185 m 동쪽). 건물 안이면 GPS가 실내 진입을
  // 발동시켜 야외 흐름이 아니라 실내 안내로 갈라진다.
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

  /// 지도만 떠 있는 첫 화면을 만든다.
  Future<void> pumpShell(WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MapShellScreen()));
    await drain(tester);
    positions.add(fix());
    await drain(tester);
  }

  Finder destinationField() => find.descendant(
    of: find.byKey(const Key('route-draft-destination')),
    matching: find.byType(TextField),
  );

  testWidgets('길찾기를 누르면 두 칸과 이동 수단 줄이 상단에 뜬다', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    // 전체 화면이 아니라는 것부터 고정한다 — 지도가 그대로 보여야 한다.
    expect(find.byKey(const Key('route-draft-origin')), findsNothing);

    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);

    expect(find.byKey(const Key('route-draft-origin')), findsOneWidget);
    expect(find.byKey(const Key('route-draft-destination')), findsOneWidget);
    expect(find.byKey(const ValueKey('travel-mode-bar')), findsOneWidget);
    // 수단이 나란히 있다. 테스트 환경에는 카카오 키가 없어 대중교통은 빠지므로
    // (그 규칙은 travel_mode_bar_test가 따로 지킨다) 나머지 둘로 확인한다.
    expect(find.text('자동차'), findsOneWidget);
    expect(find.text('도보'), findsOneWidget);

    // 수단 줄은 두 칸보다 **위**다. "어떻게 갈지"를 먼저 정하고 목적지를 넣는
    // 순서이며, 아래에 두면 두 칸과 후보 목록 사이에 끼어 시선을 가로막는다.
    expect(
      tester.getRect(find.byKey(const ValueKey('travel-mode-bar'))).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const Key('route-draft-origin'))).top,
      ),
    );
  });

  testWidgets('야외에서 아직 아무것도 안 쳤으면 빈 후보 카드를 남기지 않는다', (
    WidgetTester tester,
  ) async {
    // 야외 + 도착 칸이면 지름길 두 줄("지도에서 선택"·"현재 위치")이 모두 빠지고
    // 빈 검색어의 후보도 없다. 그런데도 카드를 그리면 이동 수단 줄 아래에 아무
    // 내용 없는 흰 막대가 떠 있게 된다.
    await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);

    // 위젯은 트리에 있어도 그리는 높이가 0이어야 한다 — 흰 막대의 정체가
    // "내용 없는 카드"였으므로 높이로 확인한다.
    expect(tester.getSize(find.byType(RouteFieldResults)).height, 0);
  });

  testWidgets('도착지를 그 자리에서 쳐서 고르면 경로가 그려진다', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);

    // 열자마자 도착 칸이 활성이라 바로 칠 수 있다.
    await tester.enterText(destinationField(), '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);

    expect(find.byType(EtaCard), findsOneWidget);
    // 고른 값이 그 칸에 그대로 남아, 다시 눌러 고칠 수 있다.
    expect(
      tester.widget<TextField>(destinationField()).controller?.text,
      '강의실 101',
    );
  });

  testWidgets('X를 누르면 길찾기 바와 경로가 함께 사라진다', (WidgetTester tester) async {
    await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    await tester.enterText(destinationField(), '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    expect(find.byType(EtaCard), findsOneWidget);

    await tester.tap(find.byKey(const Key('route-draft-clear')));
    await drain(tester);

    expect(find.byKey(const Key('route-draft-origin')), findsNothing);
    expect(find.byType(EtaCard), findsNothing);
    // 검색창이 돌아온다 — 길찾기가 끝났으니 상단 바는 원래 얼굴이어야 한다.
    expect(find.byTooltip('길찾기'), findsOneWidget);
  });

  testWidgets('출발 칸을 누르면 "현재 위치"로 되돌릴 길이 목록에 있다', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('route-draft-origin')),
        matching: find.byType(TextField),
      ),
    );
    await drain(tester);

    // 따로 고르지 않으면 현재 위치가 출발지이므로, 되돌아올 길이 목록 안에
    // 있어야 한다. 도착 칸에서는 뜨지 않는다.
    expect(
      find.byKey(const Key('route-field-current-location')),
      findsOneWidget,
    );
    // 야외에서는 "지도에서 선택"을 주지 않는다 — 이름 없는 좌표가 잡히는 줄이라
    // 매장 이름으로 고르는 줄과 나란히 두면 같은 무게로 읽힌다.
    expect(find.byKey(const Key('route-field-pick-on-map')), findsNothing);
  });
}
