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

PoiSearchResult _store(String name, String floor) =>
    PoiSearchResult(name: name, floor: floor, point: const LatLng(37.5, 126.9));

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

  group('dropPoisCoveredByIndoorStores', () {
    test('건물 안 POI 중 우리가 아는 가게는 뺀다', () {
      // 남는 쪽(우리 실내 데이터)에는 층과 노드가 붙어 있어 매장 앞까지
      // 안내되지만, 빠지는 쪽은 좌표 하나뿐이라 건물 입구에서 끝난다.
      final pois = [_poi('스타벅스 더현대서울(B2)R점'), _poi('스타벅스 여의도브라이튼점')];

      final result = dropPoisCoveredByIndoorStores(pois, [
        _store('스타벅스 리저브', 'B2'),
      ], isInsideBuilding: (poi) => poi.name.contains('더현대'));

      expect(result.map((p) => p.name), ['스타벅스 여의도브라이튼점']);
    });

    test('건물 밖 POI는 이름이 비슷해도 남긴다', () {
      // 길 건너 스타벅스는 우리 건물 안 스타벅스와 다른 가게다.
      final pois = [_poi('스타벅스 여의도브라이튼점')];

      final result = dropPoisCoveredByIndoorStores(pois, [
        _store('스타벅스 리저브', 'B2'),
      ], isInsideBuilding: (_) => false);

      expect(result, hasLength(1));
    });

    test('우리가 모르는 건물 안 가게는 남긴다', () {
      // 실내 데이터에 없는 매장까지 지우면 검색 결과에서 통째로 사라진다.
      final pois = [_poi('배스킨라빈스 더현대서울점')];

      final result = dropPoisCoveredByIndoorStores(pois, [
        _store('스타벅스 리저브', 'B2'),
      ], isInsideBuilding: (_) => true);

      expect(result, hasLength(1));
    });
  });
}
