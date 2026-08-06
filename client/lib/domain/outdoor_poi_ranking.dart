/// 야외 검색(TMAP POI) 결과를 **화면에 올리기 전에** 손보는 순수 규칙.
///
/// 화면 코드에서 분리한 이유는 이 규칙을 **두 곳이 함께 써야 하기 때문**이다.
/// 상단 검색창과 길찾기 시트가 각자 걸러 내면 반드시 갈리고, 이 화면에서는
/// 실제로 반복해서 갈렸다. 규칙은 여기 한 곳에 두고 호출만 두 번 한다.
library;

import '../models/outdoor_poi.dart';
import '../models/poi_search_result.dart';

/// 공백을 지우고 대소문자를 맞춘 이름. 비교의 기준 형태다.
///
/// "더현대 서울"과 "더현대서울"은 사람에게 같은 이름인데, 정규화하지 않으면
/// 어떤 규칙도 둘을 다르게 본다.
String collapseName(String value) =>
    value.replaceAll(RegExp(r'\s+'), '').toLowerCase();

/// 검색어와 **이름이 실제로 겹치는** 결과만 남긴다. 하나도 없으면 원본 그대로.
///
/// TMAP은 이름을 조각내 훑기 때문에 "더현대"로 검색하면 "장기동이지더원아파트
/// 전기차충전소", "김포한강신도시현대썬앤빌더킹오피스텔" 같은 것이 함께 온다.
/// "더"와 "현대"가 각각 들어 있을 뿐 사용자가 찾던 곳과는 아무 상관이 없는데,
/// 반경 제한이 없으니 이런 것들이 목록을 채우고 정작 "더현대 대구"는 뒤로
/// 밀려 잘려 나간다.
///
/// **한 건이라도 이름이 겹치면 그것만 남긴다.** 사용자가 이름을 알고 친 검색은
/// 그 이름이 든 결과가 답이고, 나머지는 잡음이다.
///
/// **하나도 안 겹치면 원본을 그대로 돌려준다.** 이게 중요하다 — "카페"·"약국"
/// 처럼 업종으로 찾는 검색은 이름에 그 글자가 없는 결과가 정상이고(스타벅스는
/// 이름에 "카페"가 없다), 여기서 걸러 버리면 업종 검색이 통째로 죽는다.
List<OutdoorPoi> filterByNameRelevance(String query, List<OutdoorPoi> pois) {
  final needle = collapseName(query);
  if (needle.isEmpty) return pois;
  final matched = pois
      .where((poi) => collapseName(poi.name).contains(needle))
      .toList();
  return matched.isEmpty ? pois : matched;
}

/// [poiName]과 [storeName]이 **같은 가게를 가리키는지** 브랜드 이름으로 본다.
///
/// TMAP과 우리 실내 데이터는 같은 가게를 다른 이름으로 부른다.
///
/// | TMAP | 우리 |
/// |---|---|
/// | 스타벅스 더현대서울(B2)R점 | 스타벅스 리저브 |
///
/// 전체 이름을 맞추려 하면 영영 안 맞는다. TMAP 이름은 "브랜드 + 지점 표기"
/// 형태라 **첫 어절(브랜드)** 이 그나마 공통이고, 그것으로 본다. 한쪽이 다른
/// 쪽의 앞부분이면 같은 브랜드로 친다("스타벅스" ⊂ "스타벅스리저브").
///
/// 브랜드가 한 글자면 판정하지 않는다 — 너무 넓게 걸려 남의 가게를 같은 곳으로
/// 만든다.
bool looksLikeSameBrand(String poiName, String storeName) {
  final brand = collapseName(_firstWord(poiName));
  if (brand.length < 2) return false;
  final store = collapseName(storeName);
  if (store.isEmpty) return false;
  return store.startsWith(brand) || brand.startsWith(store);
}

String _firstWord(String value) {
  final trimmed = value.trim();
  final space = trimmed.indexOf(RegExp(r'\s'));
  return space < 0 ? trimmed : trimmed.substring(0, space);
}

/// 우리 실내 데이터가 이미 아는 가게를 가리키는 POI를 뺀다.
///
/// 같은 가게가 두 줄로 뜨는 것을 막는 규칙이다. 사용자가 실제로 본 화면이
/// 그랬다 — "스타벅스 리저브 / B2"(우리)와 "스타벅스 더현대서울(B2)R점"(TMAP)이
/// 나란히 떴고, 두 줄이 하는 일이 달랐다. **아래쪽을 고르면 실내 경로가 안
/// 나온다.** 우리 줄에는 층과 노드가 붙어 있어 문을 경유해 매장 앞까지
/// 안내되지만, TMAP 줄은 좌표 하나뿐이라 건물 입구에서 끝난다.
///
/// 그래서 **우리가 아는 쪽을 남긴다.** 이름은 우리 데이터 이름으로 보이지만
/// 층이 함께 적혀 있어 같은 곳임을 알아볼 수 있고, 무엇보다 눌렀을 때 실제로
/// 매장 앞까지 데려다준다.
///
/// [isInsideBuilding]은 POI 좌표가 우리 도면이 있는 건물 안인지 판정한다.
/// 건물 밖 POI는 이름이 비슷해도 건드리지 않는다 — 길 건너 스타벅스는 우리
/// 건물 안 스타벅스와 **다른 가게**다.
List<OutdoorPoi> dropPoisCoveredByIndoorStores(
  List<OutdoorPoi> pois,
  List<PoiSearchResult> indoorStores, {
  required bool Function(OutdoorPoi poi) isInsideBuilding,
}) {
  if (indoorStores.isEmpty) return pois;
  return pois.where((poi) {
    if (!isInsideBuilding(poi)) return true;
    return !indoorStores.any(
      (store) => looksLikeSameBrand(poi.name, store.name),
    );
  }).toList();
}
