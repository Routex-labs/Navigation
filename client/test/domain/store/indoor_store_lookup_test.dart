import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/store/indoor_store_lookup.dart';
import 'package:navigation_client/models/outdoor_poi.dart';
import 'package:navigation_client/models/poi_search_result.dart';

/// 실기기에서 잡은 그 장면 그대로다 — 사용자가 "더현대 스타벅스"라고 쳤고,
/// 우리 백엔드는 그 말로는 no_match를 냈다(배포 백엔드에서 확인).
const _starbucksPoi = OutdoorPoi(
  id: 'poi-1',
  name: '스타벅스 더현대서울(B2)R점',
  point: LatLng(37.5258, 126.9285),
);

const _acrossTheStreet = OutdoorPoi(
  id: 'poi-2',
  name: '스타벅스 여의도IFC점',
  point: LatLng(37.5250, 126.9250),
);

const _ourStarbucks = PoiSearchResult(
  name: '스타벅스 리저브',
  floor: 'B2',
  point: LatLng(37.5258, 126.9285),
  nodeId: 'FL-x:ND-y',
);

void main() {
  test('사용자 검색어로 못 찾은 매장을 POI 브랜드로 다시 찾는다', () async {
    final asked = <String>[];

    final stores = await lookUpIndoorStoresByBrand(
      pois: const [_starbucksPoi],
      indoorStores: const [], // "더현대 스타벅스" → no_match
      isAtBuilding: (_) => true,
      buildingNames: const ['더현대 서울'],
      search: (brand) async {
        asked.add(brand);
        return const [_ourStarbucks];
      },
    );

    // 되묻는 말은 검색어("더현대")가 아니라 POI 이름의 첫 어절이어야 한다.
    expect(asked, ['스타벅스']);
    expect(stores, hasLength(1));
    expect(stores.single.nodeId, 'FL-x:ND-y');
  });

  test('이미 짝이 있으면 되묻지 않는다', () async {
    var called = 0;

    final stores = await lookUpIndoorStoresByBrand(
      pois: const [_starbucksPoi],
      indoorStores: const [_ourStarbucks],
      isAtBuilding: (_) => true,
      buildingNames: const ['더현대 서울'],
      search: (brand) async {
        called++;
        return const [];
      },
    );

    expect(called, 0);
    expect(stores, const [_ourStarbucks]);
  });

  test('우리 건물 것이 아닌 POI로는 되묻지 않는다 — 길 건너 스타벅스', () async {
    var called = 0;

    await lookUpIndoorStoresByBrand(
      pois: const [_acrossTheStreet],
      indoorStores: const [],
      isAtBuilding: (_) => false,
      buildingNames: const ['더현대 서울'],
      search: (brand) async {
        called++;
        return const [];
      },
    );

    expect(called, 0);
  });

  test('되묻기가 실패해도 원래 목록을 그대로 돌려준다', () async {
    final stores = await lookUpIndoorStoresByBrand(
      pois: const [_starbucksPoi],
      indoorStores: const [],
      isAtBuilding: (_) => true,
      buildingNames: const ['더현대 서울'],
      // 보조 수단이라 여기서 던지면 원래 잘 되던 검색까지 통째로 죽는다.
      search: (brand) async => throw StateError('네트워크 실패'),
    );

    expect(stores, isEmpty);
  });

  test('한 번의 검색에서 되묻는 브랜드는 3개까지다', () async {
    final asked = <String>[];
    final pois = [
      for (var i = 0; i < 6; i++)
        OutdoorPoi(
          id: 'poi-$i',
          name: '브랜드$i 더현대서울(1F)점',
          point: const LatLng(37.5258, 126.9285),
        ),
    ];

    await lookUpIndoorStoresByBrand(
      pois: pois,
      indoorStores: const [],
      isAtBuilding: (_) => true,
      buildingNames: const ['더현대 서울'],
      search: (brand) async {
        asked.add(brand);
        return const [];
      },
    );

    // 글자 하나 칠 때마다 검색이 도는데, 상한이 없으면 타이핑 한 번에 요청이
    // 여섯 개씩 나간다.
    expect(asked, hasLength(3));
  });

  test('찾은 매장은 원래 목록 뒤에 붙고 중복은 지운다', () async {
    const other = PoiSearchResult(
      name: '런던베이글 뮤지엄',
      floor: 'B1',
      point: LatLng(37.5258, 126.9285),
      nodeId: 'FL-a:ND-b',
    );

    final stores = await lookUpIndoorStoresByBrand(
      pois: const [_starbucksPoi],
      indoorStores: const [other],
      isAtBuilding: (_) => true,
      buildingNames: const ['더현대 서울'],
      // 같은 매장을 두 번 돌려줘도 한 줄이어야 한다.
      search: (brand) async => const [_ourStarbucks, _ourStarbucks, other],
    );

    expect(stores.map((s) => s.name), ['런던베이글 뮤지엄', '스타벅스 리저브']);
  });
}
