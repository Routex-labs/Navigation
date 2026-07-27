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
import 'package:navigation_client/widgets/floor_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 건물 안에서는 GPS를 쓰지 않는다는 규칙에 대한 회귀 테스트.
///
/// 예전에는 야외 지도가 실내 진입 오버레이를 켠 뒤에도 위치 스트림을 그대로
/// 구독했고, 위치 보정 버튼도 GPS를 다시 조회해 카메라를 GPS 좌표로 옮겼다.
/// 그래서 (1) 실내 도면 위에 건물 밖 GPS 점이 찍히고, (2) 실내 위치를 지정한
/// 직후 보정을 누르면 지도가 건물 밖으로 튀었다.
///
/// MapLibre 레이어는 위젯 트리에 없어 마커 픽셀을 직접 볼 수 없다. 대신
/// **위치 스트림 구독이 실제로 해제되는지**(= GPS를 더 이상 쓰지 않음)와
/// **GPS 신호 배지가 사라지는지**로 검증한다. 위치 보정은 어떤 안내가 뜨는지로
/// 분기를 구분한다 — GPS 경로를 탔다면 테스트 환경에 geolocator 플러그인
/// 채널이 없어 '위치를 다시 확인하지 못했습니다'가 떴을 것이다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  // 파일 전체에서 인스턴스 하나를 공유한다. MockBuildingRepository는 asset을
  // 인스턴스별로 캐시하므로, 테스트마다 새로 만들면 매번 실제 파일 I/O가 필요해진다.
  final testBuildingRepository = MockBuildingRepository();

  // 데모 건물 입구(37.5665, 126.9779) 바로 위 + 신호 저하. 자동 실내 진입
  // 조건(입구 20m 이내 + accuracy가 15m를 넘고 직전 값의 1.3배보다 나빠짐)을
  // 모두 만족한다. accuracy 60m는 '약함' 임계값(30m)도 넘으므로, 이 위치에서도
  // 배지가 안 뜬다면 그건 GPS 표시를 실제로 껐다는 뜻이다.
  Position atEntrance() => Position(
        latitude: 37.5665,
        longitude: 126.9779,
        timestamp: DateTime(2024, 1, 1),
        accuracy: 60,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

  // 입구에서 약 185m 떨어진 좌표 + 약한 신호. 자동 진입 반경 밖이라 야외
  // 상태를 유지하면서 'GPS 신호 약함' 배지만 띄운다.
  Position farAway() => Position(
        latitude: 37.5665,
        longitude: 126.9800,
        timestamp: DateTime(2024, 1, 1),
        accuracy: 40,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

  // 실내 진입 오버레이는 건물 로드(asset)와 여러 비동기 sync를 거쳐 뜬다.
  // pumpAndSettle은 지도 오버레이의 반복 애니메이션·타이머 때문에 정착하지
  // 않으므로, 정해진 횟수만큼 프레임을 진행해 큐를 비운다.
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // 주의: 이 파일의 위치 스트림 컨트롤러는 일부러 close()하지 않는다.
  // 구독이 이미 취소된 컨트롤러를 위젯 테스트 안에서 close()하면 그 뒤의
  // tester.pump()(테스트 본문이든 프레임워크의 사후 pump든)가 영원히 반환하지
  // 않아 테스트가 "did not complete"로 매달린다. 여기서 검증하려는 것이 바로
  // "구독이 취소되는가"이므로 close()는 넣지 않고, 컨트롤러는 테스트가 끝나면
  // 그대로 버린다(구독자가 없어 누수도 없다).

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalBuildingRepository = buildingRepository;
    originalDestinationRepository = destinationRepository;
    buildingRepository = testBuildingRepository;
    destinationRepository = MockDestinationRepository(buildingRepository);
    requestStartupPermissions = () async => {};
    // 건물 asset을 여기서 미리 읽어 캐시를 채운다. 위젯 테스트의 가짜 시계는
    // 실제 파일 I/O를 기다려 주지 않으므로, 캐시가 비어 있으면 테스트 안에서
    // 아무리 pump해도 건물 입구 좌표가 도착하지 않아 자동 실내 진입이 일어나지
    // 않는다(파일 안 테스트 순서에 따라 됐다 안 됐다 하는 원인이었다).
    await testBuildingRepository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  testWidgets('실내 진입 오버레이가 켜지면 위치 구독을 끊고 GPS 배지도 감춘다', (
    WidgetTester tester,
  ) async {
    var cancelled = false;
    final positions = StreamController<Position>(
      onCancel: () => cancelled = true,
    );
    watchPosition = () => positions.stream;

    await tester.pumpWidget(const MaterialApp(home: MapShellScreen()));
    // 위치를 흘리기 전에 건물(입구 좌표) 로드가 끝날 때까지 프레임을 진행한다.
    // 자동 실내 진입 판정은 입구 좌표가 있어야 성립하므로, 이걸 기다리지 않으면
    // asset 로드 속도에 따라 진입이 됐다 안 됐다 하는 플래키 테스트가 된다.
    await drain(tester);

    // 아직 야외 — 약한 신호 배지가 정상적으로 뜬다.
    positions.add(farAway());
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('GPS 신호 약함'), findsOneWidget);
    expect(cancelled, isFalse);

    // 입구에서 신호가 나빠지면 자동으로 실내 진입 오버레이가 켜진다.
    positions.add(atEntrance());
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);

    expect(find.byType(FloorSelector), findsOneWidget);
    // 실내로 들어간 순간 GPS 구독이 해제되고, GPS 기반 표시도 사라진다.
    expect(cancelled, isTrue);
    expect(find.text('GPS 신호 약함'), findsNothing);
  });

  testWidgets('실내 탭으로 전환하면 뒤에 남은 야외 지도도 GPS를 구독하지 않는다', (
    WidgetTester tester,
  ) async {
    var cancelled = false;
    final positions = StreamController<Position>(
      onCancel: () => cancelled = true,
    );
    watchPosition = () => positions.stream;

    await tester.pumpWidget(const MaterialApp(home: MapShellScreen()));
    // 위치를 흘리기 전에 건물(입구 좌표) 로드가 끝날 때까지 프레임을 진행한다.
    // 자동 실내 진입 판정은 입구 좌표가 있어야 성립하므로, 이걸 기다리지 않으면
    // asset 로드 속도에 따라 진입이 됐다 안 됐다 하는 플래키 테스트가 된다.
    await drain(tester);
    positions.add(farAway());
    await tester.pump(const Duration(milliseconds: 50));
    expect(cancelled, isFalse);

    // 하단 세그먼트로 실내 탭 전환. IndexedStack이라 야외 화면은 트리에 남는다.
    await tester.tap(find.text('실내'));
    await tester.pump();

    expect(cancelled, isTrue);
  });

  testWidgets('실내 상태의 위치 보정은 GPS를 조회하지 않고 실내 위치를 안내한다', (
    WidgetTester tester,
  ) async {
    final positions = StreamController<Position>();
    watchPosition = () => positions.stream;

    await tester.pumpWidget(const MaterialApp(home: MapShellScreen()));
    // 위치를 흘리기 전에 건물(입구 좌표) 로드가 끝날 때까지 프레임을 진행한다.
    // 자동 실내 진입 판정은 입구 좌표가 있어야 성립하므로, 이걸 기다리지 않으면
    // asset 로드 속도에 따라 진입이 됐다 안 됐다 하는 플래키 테스트가 된다.
    await drain(tester);
    // 첫 위치는 반드시 건물에서 떨어진 곳이어야 한다 — 자동 진입 판정에 쓰는
    // 건물 입구 좌표는 asset 로드가 끝난 뒤에야 채워지므로, 입구 좌표를 첫
    // 이벤트로 흘리면 아직 입구를 몰라 진입이 일어나지 않는다.
    positions.add(farAway());
    await tester.pump(const Duration(milliseconds: 50));
    positions.add(atEntrance());
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(find.byType(FloorSelector), findsOneWidget);

    // 자동 진입이 띄운 '건물 감지 중...' 스낵바가 하단 바를 덮고 있으므로,
    // 사라질 때까지(기본 4초 + 퇴장 애니메이션) 프레임을 진행한 뒤에 누른다.
    // 그러지 않으면 탭이 스낵바에 먹혀 위치 보정이 호출되지 않는다.
    await tester.pump(const Duration(seconds: 5));
    await drain(tester);
    expect(find.text('건물 감지 중...'), findsNothing);

    // 위치 보정(하단 바 우측 원형 버튼) 탭. 아직 실내 위치를 지정하지 않았으므로
    // 실내 분기의 안내가 떠야 한다. GPS 분기였다면 geolocator 플러그인 채널이
    // 없어 '위치를 다시 확인하지 못했습니다'가 떴을 것이다.
    await tester.tap(find.byIcon(Icons.my_location));
    await tester.pump();

    expect(find.textContaining('아직 현재 위치가 없습니다'), findsOneWidget);
    expect(find.textContaining('위치를 다시 확인하지 못했습니다'), findsNothing);
  });
}
