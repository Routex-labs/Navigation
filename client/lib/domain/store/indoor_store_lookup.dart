import '../../models/outdoor_poi.dart';
import '../../models/poi_search_result.dart';
import 'outdoor_poi_ranking.dart';

/// 한 번의 검색에서 브랜드로 되물을 최대 가짓수.
///
/// 글자 하나 칠 때마다 검색이 돌기 때문에 상한이 필요하다. 상한이 없으면
/// "카페"처럼 넓은 검색어에서 우리 건물 POI가 열 건씩 걸리고, 타이핑 한 번에
/// 백엔드 요청이 열 개씩 나간다.
const _maxBrandLookups = 3;

/// 사용자가 친 말로는 못 찾은 **우리 건물 안 매장**을 브랜드 이름으로 다시 묻는다.
///
/// "더현대 스타벅스"를 치면 우리 DB는 그 가게를 "스타벅스 리저브"로 갖고 있어
/// `no_match`가 난다. 그러면 겹침을 판정할 실내 후보가 0건이라 TMAP 줄이 그대로
/// 남고, 그 줄은 층·노드가 없어 **실내 경로가 아예 시작되지 않는다.**
///
/// 되묻는 말은 검색어가 아니라 **POI 이름의 첫 어절**이다([brandOf]) — 검색어의
/// 첫 어절은 건물 이름이라 소용이 없다. 실패하면 그 브랜드만 조용히 건너뛴다.
Future<List<PoiSearchResult>> lookUpIndoorStoresByBrand({
  required List<OutdoorPoi> pois,
  required List<PoiSearchResult> indoorStores,
  required bool Function(OutdoorPoi poi) isAtBuilding,
  required List<String> buildingNames,
  required Future<List<PoiSearchResult>> Function(String brand) search,
}) async {
  final brands = <String>{};
  for (final poi in pois) {
    if (brands.length >= _maxBrandLookups) break;
    final atBuilding =
        isAtBuilding(poi) || mentionsBuilding(poi.name, buildingNames);
    if (!atBuilding) continue;
    // 이미 짝이 있으면 되물을 이유가 없다.
    if (matchIndoorStore(poi, indoorStores) != null) continue;
    final brand = brandOf(poi.name);
    // 한 글자 브랜드는 너무 넓게 걸려 남의 가게를 끌어온다([looksLikeSameBrand]).
    if (brand.length < 2) continue;
    brands.add(brand);
  }
  if (brands.isEmpty) return indoorStores;

  final found = <PoiSearchResult>[];
  for (final brand in brands) {
    try {
      found.addAll(await search(brand));
    } on Object {
      continue;
    }
  }
  if (found.isEmpty) return indoorStores;

  // 원래 목록을 앞에 두고 새로 찾은 것을 뒤에 붙인다. 사용자가 친 말로 걸린
  // 결과가 위에 남아야, 되묻기가 목록 순서를 바꿔 놓지 않는다.
  final merged = <PoiSearchResult>[...indoorStores];
  final seen = indoorStores.map(_identity).toSet();
  for (final store in found) {
    if (seen.add(_identity(store))) merged.add(store);
  }
  return merged;
}

/// 같은 매장인지 가리는 키. `nodeId`가 있으면 그것이 유일하고, 없으면 층+이름을
/// 쓴다 — 이름만으로는 화장실·에스컬레이터처럼 동명이 층마다 있어 겹친다.
String _identity(PoiSearchResult store) {
  final nodeId = store.nodeId;
  if (nodeId != null && nodeId.isNotEmpty) return 'node:$nodeId';
  return 'name:${store.floor}/${store.name}';
}
