import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/models/building.dart';
import 'package:navigation_client/models/outdoor_poi.dart';
import 'package:navigation_client/repositories/building_repository.dart';
import 'package:navigation_client/repositories/destination_repository.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';
import 'package:navigation_client/repositories/outdoor_poi_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/outdoor_map/indoor_entry_zoom.dart';
import 'package:navigation_client/widgets/building_sheet.dart';
import 'package:navigation_client/widgets/search_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "밖에서 건물을 목적지로 검색했을 때" 흐름의 회귀 테스트.
///
/// 이 흐름에서 가장 깨지기 쉬운 지점은 **고르고 나서 아무 데도 못 가는 것**이다.
/// 건물은 좌표 하나가 아니라 "안에 매장이 있는 곳"이라, 건물 좌표로 안내를
/// 끝내면 정문 앞에서 안내가 끊기고 사용자는 검색을 처음부터 다시 한다. 반대로
/// 묻지 않고 건물 안으로 끌고 들어가면, 그 앞까지만 가려던 사용자가 원치 않는
/// 도면을 보게 된다. 그래서 두 갈래를 **묻고**, 어느 쪽을 골라도 다음 화면이
/// 실제로 이어지는지를 확인한다.
void main() {
  group('Building.outdoorAnchor', () {
    test('출입구 좌표가 있으면 그것을 쓴다', () {
      const building = Building(
        id: 'b',
        name: '건물',
        floors: ['1F'],
        entrance: LatLng(37.5, 126.9),
        footprintWgs84: [
          LatLng(37.0, 126.0),
          LatLng(37.0, 127.0),
          LatLng(38.0, 127.0),
          LatLng(38.0, 126.0),
        ],
      );

      expect(building.outdoorAnchor, const LatLng(37.5, 126.9));
    });

    test('출입구가 없으면 외곽선 중심으로 떨어진다', () {
      // 백엔드가 출입구 좌표를 안 내려주는 지금 상태다. 폴백이 없으면 건물이
      // 길찾기 후보 목록에서 통째로 사라진다.
      const building = Building(
        id: 'b',
        name: '건물',
        floors: ['1F'],
        footprintWgs84: [
          LatLng(37.0, 126.0),
          LatLng(37.0, 127.0),
          LatLng(38.0, 127.0),
          LatLng(38.0, 126.0),
        ],
      );

      expect(building.outdoorAnchor, const LatLng(37.5, 126.5));
    });

    test('출입구도 외곽선도 없으면 null이다', () {
      const building = Building(id: 'b', name: '건물', floors: ['1F']);

      expect(building.outdoorAnchor, isNull);
    });
  });

  group('건물 미리보기 zoom', () {
    test('미리보기 zoom은 실내로 끌고 들어가지 않는다', () {
      // "건물까지만 가겠다"고 고른 사용자에게 도면을 펴 주면 안 된다.
      // 화면 폭이 좁아 진입 임계값이 내려간 경우까지 함께 본다.
      for (final entryZoom in [indoorEntryZoomThreshold, 16.8, 16.0]) {
        expect(
          indoorEntryTransitionForZoom(
            entryZoom - buildingPreviewZoomGap,
            buildingNearby: true,
            entryZoom: entryZoom,
          ),
          IndoorEntryTransition.keep,
          reason: '진입 임계값 $entryZoom에서 미리보기가 실내 진입을 발화시켰다',
        );
      }
    });

    test('미리보기 zoom은 야외로 튕겨 나가지도 않는다', () {
      // 히스테리시스 밴드 밖으로 나가면 오버레이가 접히며 화면이 야외로 되돌아가,
      // 방금 맞춘 건물 view를 잃는다.
      expect(
        indoorEntryZoomThreshold - buildingPreviewZoomGap,
        greaterThan(indoorExitZoomThreshold),
      );
    });
  });

  group('검색 결과 중복', () {
    final originalBuildingRepository = buildingRepository;
    final originalDestinationRepository = destinationRepository;
    final originalPoiRepository = outdoorPoiRepository;

    setUp(() {
      buildingRepository = MockBuildingRepository();
      destinationRepository = MockDestinationRepository(buildingRepository);
    });

    tearDown(() {
      buildingRepository = originalBuildingRepository;
      destinationRepository = originalDestinationRepository;
      outdoorPoiRepository = originalPoiRepository;
    });

    Future<void> pumpPanel(WidgetTester tester, String query) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchPanel(
              buildingId: 'thehyundai-seoul',
              query: query,
              submitTick: 0,
              onStorePicked: (_) {},
              onBuildingPicked: (_) {},
              outdoorSearchCenter: const LatLng(37.5665, 126.9779),
              onOutdoorPoiPicked: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
    }

    testWidgets('건물 줄과 같은 곳을 가리키는 바깥 결과는 빠진다', (tester) async {
      // TMAP도 같은 건물을 POI 한 건으로 돌려준다. 두 줄이 나란히 뜨면 헷갈리는
      // 것으로 끝나지 않고, 아래쪽을 누른 사용자는 건물 안으로 못 들어간다.
      outdoorPoiRepository = _FakeOutdoorPoiRepository([
        OutdoorPoi(
          id: '1',
          // 띄어쓰기가 달라도 같은 곳으로 본다.
          name: '데모건물',
          point: const LatLng(37.5665, 126.9779),
        ),
      ]);

      await pumpPanel(tester, '데모 건물');

      // 이름은 검색어 강조 때문에 Text.rich로 그려지므로 findRichText가 필요하다.
      expect(find.text('데모 건물', findRichText: true), findsOneWidget);
      expect(find.text('데모건물', findRichText: true), findsNothing);
      expect(find.text('건물 밖 주변 장소'), findsNothing);
    });

    testWidgets('이름이 다른 바깥 결과는 그대로 남는다', (tester) async {
      // 중복을 지우려다 "건물 이름을 앞에 단 진짜 매장"까지 지우면 훨씬 나쁘다.
      outdoorPoiRepository = _FakeOutdoorPoiRepository([
        OutdoorPoi(
          id: '1',
          name: '데모 건물 스타벅스',
          point: const LatLng(37.5665, 126.9779),
        ),
      ]);

      await pumpPanel(tester, '데모 건물');

      expect(find.text('건물 밖 주변 장소'), findsOneWidget);
      expect(find.textContaining('스타벅스', findRichText: true), findsOneWidget);
    });
  });
}

/// 결과를 고정으로 돌려주는 야외 POI 리포지토리.
class _FakeOutdoorPoiRepository implements OutdoorPoiRepository {
  _FakeOutdoorPoiRepository(this.results);

  final List<OutdoorPoi> results;

  @override
  bool get isAvailable => true;

  @override
  Future<List<OutdoorPoi>> searchNearby(
    String keyword, {
    required LatLng center,
    int radiusMeters = 1000,
    int limit = 10,
  }) async => results;
}
