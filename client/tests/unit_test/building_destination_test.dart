import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/models/building.dart';
import 'package:navigation_client/models/discovery_result.dart';
import 'package:navigation_client/models/outdoor_poi.dart';
import 'package:navigation_client/models/poi_search_result.dart';
import 'package:navigation_client/repositories/destination_repository.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';
import 'package:navigation_client/repositories/outdoor_poi_repository.dart';
import 'package:navigation_client/screens/outdoor_map/indoor_entry_zoom.dart';
import 'package:navigation_client/widgets/search_panel.dart';

/// "밖에서 건물을 목적지로 찾을 때" 쓰이는 재료들의 단위 테스트.
///
/// 건물을 고른 뒤의 화면 흐름은 `map_shell_building_sheet_test.dart`가 본다.
/// 여기서는 그 흐름이 서 있는 바닥 세 가지를 고정한다 — 건물을 가리킬 좌표,
/// 건물을 보여줄 지도 줌, 그리고 검색 결과에 무엇이 올라오는가.
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

    setUp(() async {
      buildingRepository = MockBuildingRepository();
      await buildingRepository.getAllBuildings();
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

  group('밖에서는 건물만 찾는다', () {
    final originalBuildingRepository = buildingRepository;
    final originalDestinationRepository = destinationRepository;
    final originalPoiRepository = outdoorPoiRepository;
    late _CountingDestinationRepository counting;

    setUp(() async {
      buildingRepository = MockBuildingRepository();
      // asset을 미리 읽어 캐시를 채운다. 안 하면 패널 안에서 도는 첫 조회가
      // 진짜 파일 I/O라 pump 몇 번으로는 안 끝나고, 화면이 스피너에 멈춘 채로
      // 단언에 걸린다 — 코드가 아니라 테스트가 못 기다린 것이다.
      await buildingRepository.getAllBuildings();
      counting = _CountingDestinationRepository(
        MockDestinationRepository(buildingRepository),
      );
      destinationRepository = counting;
      // TMAP 키가 없는 상태를 흉내낸다. 바깥 조회가 그 자리에서 끝나므로,
      // "결론을 누가 내는가"가 그대로 드러난다.
      outdoorPoiRepository = _FakeOutdoorPoiRepository(const []);
    });

    tearDown(() {
      buildingRepository = originalBuildingRepository;
      destinationRepository = originalDestinationRepository;
      outdoorPoiRepository = originalPoiRepository;
    });

    Future<void> pumpPanel(
      WidgetTester tester, {
      required String query,
      required bool indoorContextActive,
    }) async {
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
              indoorContextActive: indoorContextActive,
            ),
          ),
        ),
      );
      // 경량 디바운스(300ms)와 의미 검색 대기(400ms)를 모두 지난다.
      await tester.pump(const Duration(milliseconds: 800));
      // 리포지토리는 asset을 읽는 진짜 비동기라 pump 한 번으로는 다 안 풀린다.
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    testWidgets('밖에서는 건물 안 매장을 아예 조회하지 않는다', (tester) async {
      await pumpPanel(tester, query: '데모', indoorContextActive: false);

      // 결과를 화면에서 숨기는 게 아니라 요청 자체를 안 보낸다. 숨기기만 하면
      // 밖에 서 있는 사용자마다 쓰지도 않을 검색이 매번 서버로 나간다.
      expect(counting.lightCalls, 0);
      expect(counting.semanticCalls, 0);
      // 대신 건물은 그대로 뜬다.
      expect(find.text('데모 건물', findRichText: true), findsOneWidget);
    });

    testWidgets('건물 안에서는 매장을 그대로 찾는다', (tester) async {
      await pumpPanel(tester, query: '데모', indoorContextActive: true);

      expect(counting.lightCalls, 1);
    });

    testWidgets('밖에서 아무것도 못 찾으면 스피너로 멈추지 않는다', (tester) async {
      // 밖에서는 실내 검색도 의미 검색도 안 도니, 결론을 낼 사람이 바깥 조회
      // 하나뿐이다. 여기서 결론을 안 내면 사용자는 영원히 도는 스피너를 본다.
      await pumpPanel(tester, query: '없는건물이름', indoorContextActive: false);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('찾지 못했어요'), findsOneWidget);
    });
  });
}

/// 실내 검색이 실제로 나갔는지 세는 껍데기. "화면에 안 보인다"와 "요청을 안
/// 보냈다"는 다른 이야기라, 후자를 직접 확인한다.
class _CountingDestinationRepository implements DestinationRepository {
  _CountingDestinationRepository(this.inner);

  final DestinationRepository inner;
  int lightCalls = 0;
  int semanticCalls = 0;

  @override
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) {
    lightCalls++;
    return inner.searchDestinations(
      buildingId,
      query,
      currentFloorId: currentFloorId,
    );
  }

  @override
  Future<DiscoveryResult> searchDestinationsAi(
    String buildingId,
    String query, {
    String? currentFloorId,
    Map<String, List<String>>? selectedFacets,
    bool showAll = false,
  }) {
    semanticCalls++;
    return inner.searchDestinationsAi(
      buildingId,
      query,
      currentFloorId: currentFloorId,
      selectedFacets: selectedFacets,
      showAll: showAll,
    );
  }
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
