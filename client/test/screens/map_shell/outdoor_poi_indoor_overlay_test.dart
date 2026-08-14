import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/models/outdoor_poi.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';
import 'package:navigation_client/repositories/outdoor_poi_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 호출 여부만 기록하는 스텁.
class _RecordingPoiRepository implements OutdoorPoiRepository {
  int callCount = 0;
  LatLng? lastCenter;

  @override
  bool get isAvailable => true;

  @override
  Future<List<OutdoorPoi>> searchNearby(
    String keyword, {
    required LatLng center,
    int radiusMeters = 1000,
    int limit = 10,
  }) async {
    callCount++;
    lastCenter = center;
    return const [];
  }
}

// 데모 건물 입구 좌표 + 신호 저하. 이 두 건이 순서대로 흘러야 자동 실내 진입이
// 판정된다(widget_test.dart의 같은 픽스처와 규칙이 같다).
final _approaching = Position(
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

final _atEntrance = Position(
  latitude: 37.5665,
  longitude: 126.9779,
  timestamp: DateTime(2024, 1, 1),
  accuracy: 45,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  final originalBuildingRepository = buildingRepository;
  final originalDestinationRepository = destinationRepository;
  final originalPoiRepository = outdoorPoiRepository;
  late _RecordingPoiRepository recording;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    requestStartupPermissions = () async => {};
    buildingRepository = MockBuildingRepository();
    destinationRepository = MockDestinationRepository(buildingRepository);
    recording = _RecordingPoiRepository();
    outdoorPoiRepository = recording;
  });

  tearDown(() {
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    outdoorPoiRepository = originalPoiRepository;
  });

  // 이 테스트가 잡는 회귀는 실제로 기능을 통째로 죽였던 것이다.
  //
  // 처음에는 "실내 도면을 보는 중이면 바깥 검색을 끈다"는 조건을 뒀는데, 폰에서는
  // 실내 진입 임계 zoom이 화면 폭에 맞춰 내려가고(indoor_entry_zoom.dart) 건물
  // 근처에서는 GPS로도 자동 진입한다. 즉 실기기에서 그 조건이 거의 항상 참이라
  // TMAP POI 검색이 **한 번도 실행되지 않았다.** 화면에는 그냥 "바깥 결과가 없다"로
  // 보여서 원인을 알 수 없었다.
  testWidgets('실내 진입 오버레이가 켜져 있어도 건물 밖 검색은 그대로 돈다', (tester) async {
    watchPosition = () => Stream.fromIterable([_approaching, _atEntrance]);

    await tester.pumpWidget(const MaterialApp(home: MapShellScreen()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    // 상단 검색창에 입력해 검색을 활성화한다.
    await tester.enterText(find.byType(TextField).first, '스타벅스');
    // **두 번 나눠 pump한다.** 첫 pump에서 비로소 SearchPanel이 트리에 들어오고
    // 그때 디바운스 타이머가 걸리므로, 같은 pump의 남은 시간으로는 그 타이머가
    // 안 지나간다. 두 번째 pump가 300ms 디바운스를 넘긴다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      recording.callCount,
      greaterThan(0),
      reason: '실내 오버레이 상태에서도 바깥 POI 검색이 호출돼야 한다',
    );
    expect(recording.lastCenter, isNotNull);
  });
}
