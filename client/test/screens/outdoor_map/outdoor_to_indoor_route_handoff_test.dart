import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/models/poi_search_result.dart';
import 'package:navigation_client/repositories/building_repository.dart';
import 'package:navigation_client/repositories/destination_repository.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/floor_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **밖에 서서 도면만 펴 놓은 상태**에서 건물 안 매장까지 안내를 시작했을 때,
/// 실내 오버레이를 접고 야외 구간부터 보여주는지에 대한 회귀 테스트.
///
/// 지키려는 증상: **실내 경로가 영영 안 그려지는 것.**
///
/// 문을 경유하는 안내([OutdoorMapBodyState.showOutdoorToIndoorRouteTo])는 실내
/// 구간을 미리 풀어 두었다가 사용자가 건물에 **들어가는 순간** 이어 붙인다. 그
/// "순간"이 유일한 트리거인데, 오버레이는 확대·건물 탭·"건물 안에서 매장 고르기"
/// 만으로도 켜지므로 밖에 선 사용자가 이미 들어와 있는 상태로 여기 도착할 수 있다.
/// 그러면 트리거가 다시 오지 않아 실내 구간이 대기 상태에 갇히고, 화면에는 도면
/// 위에 야외 구간만 얹힌 채로 남는다.
///
/// 오버레이를 먼저 접으면 두 가지가 동시에 맞는다 — 지금 필요한 안내(문까지
/// 걸어가기)가 야외 지도에 제대로 보이고, 실제로 들어가거나 다시 확대하는 순간
/// 트리거가 정상으로 발화해 실내 구간이 이어 붙는다.
///
/// 실내 여부는 층 선택기([FloorSelector]) 노출로 판정한다 — 실내 오버레이가
/// 켜졌을 때만 뜨는 위젯이다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final testBuildingRepository = MockBuildingRepository();

  // 데모 건물 footprint는 위도 37.5663~37.5667, 경도 126.9777~126.9783 사각형이다.
  const insideBuilding = ll.LatLng(37.5665, 126.9780);

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
    buildingRepository = testBuildingRepository;
    destinationRepository = MockDestinationRepository(buildingRepository);
    requestStartupPermissions = () async => {};
    // 건물 asset을 미리 읽어 캐시를 채운다. 위젯 테스트의 가짜 시계는 실제 파일
    // I/O를 기다려 주지 않아, 캐시가 비면 footprint가 도착하지 않는다.
    await testBuildingRepository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
  });

  testWidgets('도면을 펴 놓은 채 안내를 시작하면 오버레이를 접는다', (WidgetTester tester) async {
    final key = GlobalKey<OutdoorMapBodyState>();
    // Scaffold로 감싼다 — 진입·안내 경로가 스낵바를 띄울 수 있고, 하위에
    // ScaffoldMessenger가 없으면 그 자리에서 예외로 끊긴다.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OutdoorMapBody(key: key)),
      ),
    );
    await drain(tester);

    // 건물을 직접 탭해 오버레이를 켠다. GPS 자동 진입과 달리 **실내 위치(PDR
    // 앵커)가 잡히지 않는다** — 사용자는 아직 밖에 서 있고, 이 테스트가 재현하려는
    // 상태가 정확히 그것이다.
    // ignore: invalid_use_of_visible_for_testing_member
    await key.currentState!.handleMapClickForTest(insideBuilding);
    await drain(tester);
    expect(
      find.byType(FloorSelector),
      findsOneWidget,
      reason: '테스트 전제(도면이 펴진 상태)가 성립하지 않았다',
    );

    await key.currentState!.showOutdoorToIndoorRouteTo(
      const PoiSearchResult(
        name: '강의실 101',
        floor: '1F',
        point: ll.LatLng(37.5665, 126.9780),
        nodeId: 'FL-1:ND-1',
      ),
    );
    await drain(tester);

    expect(
      find.byType(FloorSelector),
      findsNothing,
      reason: '안내를 시작했는데 도면이 그대로 펴져 있으면 실내 구간이 영영 안 그려진다',
    );
  });

  testWidgets('건물 벽 바로 밖의 POI도 "이 건물의 가게"로 본다', (WidgetTester tester) async {
    // TMAP POI 좌표는 건물 대표점이 아니라 **도로에서 들어오는 접근점**이라,
    // 백화점 입점 매장도 벽 바깥 인도에 찍힌다. 외곽선 안인지만 보면 입점
    // 매장이 전부 "건물 밖"이 되고, 우리 실내 데이터와 합쳐지지 않아 같은
    // 가게가 두 줄로 남는다 — "스타벅스 리저브"와 "스타벅스 더현대서울(B2)R점"이
    // 나란히 떴던 화면이 그것이다.
    final key = GlobalKey<OutdoorMapBodyState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OutdoorMapBody(key: key)),
      ),
    );
    await drain(tester);

    final state = key.currentState!;
    expect(state.isAtIndoorBuilding(insideBuilding), isTrue);
    // 북쪽 벽에서 약 20 m 밖(위도 0.00018° ≈ 20 m).
    expect(
      state.isAtIndoorBuilding(const ll.LatLng(37.56688, 126.9780)),
      isTrue,
      reason: '벽 바로 밖 접근점을 건물 밖으로 보면 입점 매장이 합쳐지지 않는다',
    );
    // 약 100 m 밖. 길 건너 가게까지 삼키면 남의 가게를 같은 곳으로 만든다.
    expect(
      state.isAtIndoorBuilding(const ll.LatLng(37.5676, 126.9780)),
      isFalse,
      reason: '여유를 너무 넓게 주면 길 건너 가게가 이 건물 것이 된다',
    );
  });
}
