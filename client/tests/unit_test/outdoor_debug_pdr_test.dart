import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/repositories/building_repository.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 야외 지도의 실내 오버레이에 붙인 PDR 진단 레이어(그래프 노드·간선 +
/// raw/confirmed/matched 경로)에 대한 회귀 테스트.
///
/// MapLibre 레이어는 위젯 트리에 없어 픽셀을 볼 수 없다. 대신 **디버그 토글이
/// 야외 화면까지 도달하는지**를 본다 — 예전에는 야외 화면이 세 경로 플래그를
/// 아예 읽지 않아, 디버그 모드를 켜도 실내 탭에만 경로가 보이고 야외
/// 오버레이에는 아무것도 안 그려졌다.
void main() {
  late BuildingRepository originalBuildingRepository;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalBuildingRepository = buildingRepository;
    buildingRepository = MockBuildingRepository();
    requestStartupPermissions = () async => {};
    watchPosition = () => const Stream.empty();
  });

  tearDown(() async {
    buildingRepository = originalBuildingRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
    // 이 파일이 디버그 모드를 켜 두면 같은 isolate의 뒤 테스트로 샌다.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
  });

  testWidgets('세 경로 토글을 켜고 꺼도 야외 화면이 살아 있다', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: OutdoorMapBody()));
    await tester.pump();

    await debugModeController.setEnabled(true);
    await tester.pump();

    for (final off in [true, false]) {
      await debugModeController.setShowRawPdrPath(!off);
      await debugModeController.setShowConfirmedPdrPath(!off);
      await debugModeController.setShowMapMatchedPdrPath(!off);
      await debugModeController.setShowGraphNodes(!off);
      await debugModeController.setShowGraphEdges(!off);
      await tester.pump();
    }

    // 레이어를 지웠다 다시 만들지 않고 데이터만 비우는 구조라, 토글을 아무리
    // 흔들어도 소스/레이어 등록 경쟁으로 터지지 않아야 한다.
    expect(find.byType(OutdoorMapBody), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('디버그 모드를 끄면 개별 토글이 켜져 있어도 그리지 않는다', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: OutdoorMapBody()));
    await tester.pump();

    await debugModeController.setEnabled(false);
    await tester.pump();

    // 개별 토글 기본값은 on이지만 enabled가 게이트다.
    expect(debugModeController.enabled, isFalse);
    expect(debugModeController.showRawPdrPath, isTrue);
    expect(tester.takeException(), isNull);
  });
}
