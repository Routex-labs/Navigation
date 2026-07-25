import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/main.dart' as app;
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final originalBuildingRepository = buildingRepository;
  final originalDestinationRepository = destinationRepository;
  final originalRequestStartupPermissions = requestStartupPermissions;
  final originalWatchPosition = watchPosition;

  setUpAll(() {
    // Linux CI에는 GPS/권한 플러그인과 개발용 API 서버가 없다. 이 테스트의
    // 목적은 앱 부팅이므로, 외부 의존성을 메모리 기반 대역으로 고정한다.
    // 야외 지도가 MapLibre로 옮겨간 뒤로는 배경 타일도 별도 fake provider가
    // 필요 없다 — 데스크톱에서는 _isMapSupportedOnThisPlatform이 false라
    // MapLibreMap 위젯 자체가 생성되지 않아 네트워크 요청이 발생하지 않는다.
    final mockBuildingRepository = MockBuildingRepository();
    buildingRepository = mockBuildingRepository;
    destinationRepository = MockDestinationRepository(mockBuildingRepository);
    requestStartupPermissions = () async => {};
    watchPosition = () => const Stream.empty();
  });

  tearDownAll(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = originalRequestStartupPermissions;
    watchPosition = originalWatchPosition;
  });

  testWidgets('app launches and reaches a settled state', (
    WidgetTester tester,
  ) async {
    // flutter test의 기본 플랫폼은 Android라 platform view를 만들지만,
    // CI는 Linux desktop을 대상으로 한다. 실제 CI 경로와 같은 fallback을
    // 타도록 강제하고, 테스트 뒤에는 반드시 null로 되돌린다.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      app.main();
      // 지도 위젯은 카메라/타일 갱신으로 계속 프레임을 만들 수 있어
      // pumpAndSettle을 쓰면 실제 부팅이 끝난 뒤에도 CI가 기다리게 된다.
      // 이 테스트는 초기 화면 렌더만 보므로 필요한 프레임만 진행한다.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      // 앱은 이제 스플래시 화면 없이 바로 야외(홈) 지도로 시작한다.
      expect(find.text('홈'), findsOneWidget);
      expect(find.text('실내'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
