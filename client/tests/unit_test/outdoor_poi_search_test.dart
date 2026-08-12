import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:navigation_client/models/outdoor_poi.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';
import 'package:navigation_client/repositories/outdoor_poi_repository.dart';
import 'package:navigation_client/widgets/search_panel.dart';

/// 결과를 고정으로 돌려주는 야외 POI 리포지토리. 네트워크 없이 "바깥에서
/// 찾았다"는 상황만 만든다.
class _FakeOutdoorPoiRepository implements OutdoorPoiRepository {
  _FakeOutdoorPoiRepository(this.results);

  final List<OutdoorPoi> results;
  LatLng? lastCenter;
  int callCount = 0;

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
    return results;
  }
}

final _starbucks = OutdoorPoi(
  id: '1',
  name: '스타벅스 여의도점',
  point: const LatLng(37.5253, 126.9251),
  category: '커피전문점',
  address: '서울 영등포구 국제금융로 10',
  distanceMeters: 240,
);

void main() {
  final originalBuildingRepository = buildingRepository;
  final originalDestinationRepository = destinationRepository;
  final originalPoiRepository = outdoorPoiRepository;
  late _FakeOutdoorPoiRepository fakePoiRepository;

  setUp(() {
    buildingRepository = MockBuildingRepository();
    destinationRepository = MockDestinationRepository(buildingRepository);
    fakePoiRepository = _FakeOutdoorPoiRepository([_starbucks]);
    outdoorPoiRepository = fakePoiRepository;
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    outdoorPoiRepository = originalPoiRepository;
  });

  Future<void> pumpPanel(
    WidgetTester tester, {
    required String query,
    LatLng? center,
    ValueChanged<OutdoorPoi>? onPoiPicked,
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
            onQueryPicked: (_) {},
            onSuggestionPicked: (_) {},
            // 바깥을 찾는 상황이므로 실내 컨텍스트는 꺼 둔다. 이 값이 참이면
            // 온디바이스 자동완성이 목록을 대신 채운다(SearchPanel 주석).
            indoorContextActive: false,
            outdoorSearchCenter: center,
            onOutdoorPoiPicked: onPoiPicked ?? (_) {},
          ),
        ),
      ),
    );
    // 경량 검색 디바운스(300ms) + 의미 검색 대기(400ms)를 모두 지난다.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
  }

  testWidgets('건물 안에 없어도 밖에서 찾은 장소를 보여준다', (tester) async {
    await pumpPanel(
      tester,
      query: '스타벅스',
      center: const LatLng(37.5260, 126.9270),
    );

    // 실내 검색이 빈손이어도 "찾지 못했어요"로 끝나지 않는다 — 바깥에 답이 있다.
    expect(find.textContaining('찾지 못했어요'), findsNothing);
    expect(find.text('건물 밖 주변 장소'), findsOneWidget);
    expect(find.textContaining('스타벅스 여의도점'), findsOneWidget);
    // 층 대신 거리·주소로 어느 지점인지 가른다.
    expect(find.textContaining('약 240m'), findsOneWidget);
    expect(find.textContaining('국제금융로 10'), findsOneWidget);
  });

  testWidgets('바깥 장소를 누르면 상위에 그 장소를 넘긴다', (tester) async {
    OutdoorPoi? picked;
    await pumpPanel(
      tester,
      query: '스타벅스',
      center: const LatLng(37.5260, 126.9270),
      onPoiPicked: (poi) => picked = poi,
    );

    await tester.tap(find.textContaining('스타벅스 여의도점'));
    await tester.pump();

    expect(picked?.name, '스타벅스 여의도점');
  });

  testWidgets('기준점이 없으면(실내 도면을 보는 중) 바깥 검색을 하지 않는다', (tester) async {
    await pumpPanel(tester, query: '스타벅스', center: null);

    expect(fakePoiRepository.callCount, 0);
    expect(find.text('건물 밖 주변 장소'), findsNothing);
  });

  testWidgets('검색 기준점을 그대로 리포지토리에 넘긴다', (tester) async {
    await pumpPanel(
      tester,
      query: '스타벅스',
      center: const LatLng(37.5260, 126.9270),
    );

    expect(fakePoiRepository.lastCenter, const LatLng(37.5260, 126.9270));
  });
}
