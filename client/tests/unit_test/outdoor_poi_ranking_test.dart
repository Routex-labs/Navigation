import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/outdoor_poi_ranking.dart';
import 'package:navigation_client/models/outdoor_poi.dart';
import 'package:navigation_client/models/poi_search_result.dart';

/// 야외 검색 결과를 화면에 올리기 전에 손보는 규칙의 테스트.
///
/// 두 증상을 실제 화면에서 잡아 그대로 픽스처로 옮겼다.
///
/// 1. "더현대"를 쳤더니 "장기동이지더원아파트 전기차충전소" 같은 무관한 곳이
///    목록을 채우고, 정작 "더현대 대구"는 보이지 않았다.
/// 2. "스타벅스"를 쳤더니 같은 가게가 두 줄로 떴고("스타벅스 리저브"와
///    "스타벅스 더현대서울(B2)R점"), 그중 한 줄은 눌러도 실내 경로가 안 나왔다.
OutdoorPoi _poi(String name, {LatLng point = const LatLng(37.5, 126.9)}) =>
    OutdoorPoi(id: name, name: name, point: point);

PoiSearchResult _store(String name, String floor) => PoiSearchResult(
  name: name,
  floor: floor,
  point: const LatLng(37.5, 126.9),
  nodeId: 'ND-$name',
);

void main() {
  group('filterByNameRelevance', () {
    test('이름이 겹치는 결과가 있으면 그것만 남긴다', () {
      final pois = [
        _poi('장기동이지더원아파트 2 전기차충전소'),
        _poi('더현대 서울'),
        _poi('김포한강신도시현대썬앤빌더킹오피스텔'),
        _poi('더현대 대구'),
        _poi('조앤더주스 현대백화점킨텍스점'),
      ];

      final result = filterByNameRelevance('더현대', pois);

      expect(result.map((p) => p.name), ['더현대 서울', '더현대 대구']);
    });

    test('띄어쓰기가 달라도 같은 이름으로 본다', () {
      final pois = [_poi('더현대서울'), _poi('현대썬앤빌더킹')];

      final result = filterByNameRelevance('더현대 서울', pois);

      expect(result.map((p) => p.name), ['더현대서울']);
    });

    test('이름이 하나도 안 겹치면 원본을 그대로 돌려준다', () {
      // 업종으로 찾는 검색이 여기 걸린다 — 스타벅스는 이름에 "카페"가 없다.
      // 여기서 걸러 버리면 업종 검색이 통째로 죽는다.
      final pois = [_poi('스타벅스 여의도점'), _poi('투썸플레이스')];

      final result = filterByNameRelevance('카페', pois);

      expect(result.map((p) => p.name), ['스타벅스 여의도점', '투썸플레이스']);
    });
  });

  group('looksLikeSameBrand', () {
    test('TMAP 지점명과 우리 매장명을 브랜드로 잇는다', () {
      // 실제로 화면에 나란히 떴던 두 이름이다.
      expect(looksLikeSameBrand('스타벅스 더현대서울(B2)R점', '스타벅스 리저브'), isTrue);
    });

    test('브랜드가 다르면 잇지 않는다', () {
      expect(looksLikeSameBrand('투썸플레이스 여의도점', '스타벅스 리저브'), isFalse);
    });

    test('한 글자 브랜드는 판정하지 않는다', () {
      // 너무 넓게 걸려 남의 가게를 같은 곳으로 만든다.
      expect(looksLikeSameBrand('밀 더현대점', '밀라노커피'), isFalse);
    });
  });

  group('floorHintFrom', () {
    test('지점명 괄호 안의 층을 뽑는다', () {
      // 좌표로는 층을 고를 수 없다 — 열두 개 층이 같은 위경도 위에 쌓여 있고
      // TMAP은 층 필드를 안 준다. 층은 이름에만 있다.
      expect(floorHintFrom('스타벅스 더현대서울(B2)R점'), 'B2');
      expect(floorHintFrom('스타벅스 여의도IFC몰(L2)STREET점'), isNull);
      expect(floorHintFrom('스타벅스 여의도점'), isNull);
    });

    test('층 이름의 F 표기 차이를 흡수한다', () {
      expect(sameFloor('B2', 'B2F'), isTrue);
      expect(sameFloor('1F', '1'), isTrue);
      expect(sameFloor('B2', 'B3'), isFalse);
    });
  });

  group('matchIndoorStore', () {
    test('브랜드 후보가 하나면 그것으로 확정한다', () {
      final store = matchIndoorStore(_poi('스타벅스 더현대서울(B2)R점'), [
        _store('스타벅스 리저브', 'B2'),
        _store('투썸플레이스', '1F'),
      ]);

      expect(store?.name, '스타벅스 리저브');
    });

    test('브랜드 후보가 여럿이면 이름의 층 힌트로 좁힌다', () {
      final store = matchIndoorStore(_poi('스타벅스 더현대서울(B2)R점'), [
        _store('스타벅스 리저브', 'B2'),
        _store('스타벅스', '6F'),
      ]);

      expect(store?.floor, 'B2');
    });

    test('층 힌트가 없어 좁히지 못하면 포기한다', () {
      // 잘못 고르면 사용자는 "안내가 안 된다"가 아니라 엉뚱한 매장 앞에
      // 도착한다. 포기하면 호출부가 건물 입구까지 안내로 떨어뜨린다.
      final store = matchIndoorStore(_poi('스타벅스 더현대서울점'), [
        _store('스타벅스 리저브', 'B2'),
        _store('스타벅스', '6F'),
      ]);

      expect(store, isNull);
    });

    test('노드가 없는 매장은 후보가 아니다', () {
      // 연결해 봐야 실내 경로를 못 만든다.
      final store = matchIndoorStore(_poi('스타벅스 더현대서울(B2)R점'), [
        PoiSearchResult(
          name: '스타벅스 리저브',
          floor: 'B2',
          point: const LatLng(37.5, 126.9),
        ),
      ]);

      expect(store, isNull);
    });
  });

  group('mergeOutdoorResults', () {
    test('건물 안 POI에 우리 매장을 실어 준다', () {
      // 이름은 POI 것이 남고(사용자가 검색해서 본 이름), 층·노드는 우리 것이
      // 붙는다(실내까지 안내하는 능력). 우리 매장 줄은 목록에서 빠진다.
      final merged = mergeOutdoorResults(
        pois: [_poi('스타벅스 더현대서울(B2)R점'), _poi('스타벅스 여의도브라이튼점')],
        indoorStores: [_store('스타벅스 리저브', 'B2')],
        isAtBuilding: (poi) => poi.name.contains('더현대'),
      );

      expect(merged.outdoorRows, hasLength(2));
      final linked = merged.outdoorRows.first;
      expect(linked.poi.name, '스타벅스 더현대서울(B2)R점');
      expect(linked.indoorStore?.name, '스타벅스 리저브');
      expect(merged.outdoorRows[1].leadsIndoors, isFalse);
      expect(merged.indoorStores, isEmpty);
    });

    test('좌표가 안 걸려도 이름이 건물을 부르면 연결한다', () {
      // 실제로 여기서 두 번 틀렸다. TMAP POI 좌표는 도로 접근점이라 큰 건물에서
      // 외곽선 밖에 찍히고, 얼마나 떨어질지는 건물마다 다르다 — 허용 거리 하나로는
      // 어느 쪽으로도 안전한 값이 없다. 이름은 그 애매함이 없다.
      final merged = mergeOutdoorResults(
        pois: [_poi('스타벅스 더현대서울(B2)R점')],
        indoorStores: [_store('스타벅스 리저브', 'B2')],
        isAtBuilding: (_) => false,
        buildingNames: const ['더현대 서울'],
      );

      expect(merged.outdoorRows.single.indoorStore?.name, '스타벅스 리저브');
      expect(merged.indoorStores, isEmpty);
    });

    test('건물 밖 POI는 이름이 비슷해도 연결하지 않는다', () {
      // 길 건너 스타벅스는 우리 건물 안 스타벅스와 다른 가게다.
      final merged = mergeOutdoorResults(
        pois: [_poi('스타벅스 여의도브라이튼점')],
        indoorStores: [_store('스타벅스 리저브', 'B2')],
        isAtBuilding: (_) => false,
      );

      expect(merged.outdoorRows.single.leadsIndoors, isFalse);
      // 연결되지 않았으니 우리 매장 줄은 그대로 남는다.
      expect(merged.indoorStores, hasLength(1));
    });

    test('우리가 모르는 건물 안 가게는 좌표 줄로 남는다', () {
      final merged = mergeOutdoorResults(
        pois: [_poi('배스킨라빈스 더현대서울점')],
        indoorStores: [_store('스타벅스 리저브', 'B2')],
        isAtBuilding: (_) => true,
      );

      expect(merged.outdoorRows.single.leadsIndoors, isFalse);
      expect(merged.indoorStores, hasLength(1));
    });
  });
}
