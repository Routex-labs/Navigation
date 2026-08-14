/// 야외 검색(TMAP POI) 결과를 **화면에 올리기 전에** 손보는 순수 규칙.
/// 상단 검색창과 길찾기 시트가 함께 쓴다 — 각자 걸러 내면 반드시 갈린다.
///
/// 규칙마다의 근거는 `docs/client/search-result-list-ux.md` X절이 단일 출처다.
library;

import '../../models/place/outdoor_poi.dart';
import '../../models/place/poi_search_result.dart';

/// 공백을 지우고 대소문자를 맞춘 이름. 비교의 기준 형태다.
///
/// "더현대 서울"과 "더현대서울"은 사람에게 같은 이름인데, 정규화하지 않으면
/// 어떤 규칙도 둘을 다르게 본다.
String collapseName(String value) =>
    value.replaceAll(RegExp(r'\s+'), '').toLowerCase();

/// 검색어와 **이름이 실제로 겹치는** 결과만 남긴다.
///
/// **하나도 안 겹치면 원본을 그대로 돌려준다** — 업종으로 찾는 검색은 이름에 그
/// 글자가 없는 게 정상이라(스타벅스에 "카페"가 없다) 걸러 버리면 통째로 죽는다.
List<OutdoorPoi> filterByNameRelevance(String query, List<OutdoorPoi> pois) {
  final needle = collapseName(query);
  if (needle.isEmpty) return pois;
  final matched = pois
      .where((poi) => collapseName(poi.name).contains(needle))
      .toList();
  return matched.isEmpty ? pois : matched;
}

/// [poiName]과 [storeName]이 **같은 가게인지** 브랜드(첫 어절)로 본다.
/// 한쪽이 다른 쪽의 앞부분이면 같은 브랜드로 친다("스타벅스" ⊂ "스타벅스리저브").
/// 브랜드가 한 글자면 판정하지 않는다 — 남의 가게를 같은 곳으로 만든다.
bool looksLikeSameBrand(String poiName, String storeName) {
  final brand = collapseName(_firstWord(poiName));
  if (brand.length < 2) return false;
  final store = collapseName(storeName);
  if (store.isEmpty) return false;
  return store.startsWith(brand) || brand.startsWith(store);
}

/// 이름의 **브랜드 부분**(첫 어절). "스타벅스 더현대서울(B2)R점" → `스타벅스`
/// 우리 백엔드에 다시 물어볼 때 쓰는 검색어이기도 하다.
String brandOf(String name) {
  final trimmed = name.trim();
  final space = trimmed.indexOf(RegExp(r'\s'));
  return space < 0 ? trimmed : trimmed.substring(0, space);
}

String _firstWord(String value) => brandOf(value);

/// TMAP 지점명 괄호 안의 **층 힌트**를 뽑는다("…더현대서울**(B2)**R점" → `B2`).
/// **좌표로는 층을 고를 수 없다** — 열두 개 층이 같은 위경도에 쌓여 있고 TMAP은
/// 층 필드를 주지 않는다. 층이 아닌 괄호(`(주)`)는 숫자가 없어 안 걸린다.
String? floorHintFrom(String poiName) {
  final match = RegExp(
    r'\((B?\d{1,2}F?)\)',
    caseSensitive: false,
  ).firstMatch(poiName);
  return match?.group(1)?.toUpperCase();
}

/// 층 이름 두 개가 같은 층을 가리키는지. "B2" == "B2F", "1" == "1F".
///
/// TMAP 지점명과 우리 층 이름이 F를 붙이는 규칙이 다르다. 글자 그대로 비교하면
/// 층 힌트가 있어도 매번 어긋나 매칭이 통째로 실패한다.
bool sameFloor(String a, String b) => _normalizeFloor(a) == _normalizeFloor(b);

String _normalizeFloor(String value) =>
    value.trim().toUpperCase().replaceAll('F', '');

/// [poi]가 가리키는 **우리 실내 매장**을 찾는다. 못 찾으면 null.
///
/// 브랜드로 추리고 층 힌트로 좁혀 **정확히 하나일 때만** 확정한다. 애매하면
/// 포기한다 — 잘못 고르면 사용자가 엉뚱한 매장 앞에 도착한다.
/// 노드가 없는 매장은 후보에서 뺀다(연결해도 실내 경로를 못 만든다).
PoiSearchResult? matchIndoorStore(
  OutdoorPoi poi,
  List<PoiSearchResult> indoorStores,
) {
  final byBrand = indoorStores
      .where((store) => store.nodeId != null && store.nodeId!.isNotEmpty)
      .where((store) => looksLikeSameBrand(poi.name, store.name))
      .toList();
  if (byBrand.isEmpty) return null;
  if (byBrand.length == 1) return byBrand.first;

  final hint = floorHintFrom(poi.name);
  if (hint == null) return null;
  final byFloor = byBrand.where((s) => sameFloor(s.floor, hint)).toList();
  return byFloor.length == 1 ? byFloor.first : null;
}

/// 바깥 목록의 한 줄. 여기까지 온 POI는 **우리가 모르는 곳**이다 — 아는 가게를
/// 가리키는 POI는 [mergeOutdoorResults]에서 이미 빠진다.
class OutdoorSearchRow {
  const OutdoorSearchRow(this.poi);

  final OutdoorPoi poi;
}

/// 바깥 결과와 우리 실내 결과를 **한 목록으로** 합친다.
///
/// 방향은 **우리 쪽으로** — 우리 줄을 남기고 겹치는 POI 줄을 뺀다. 반대로 하면
/// 매칭이 성공해야만 실내 안내가 되는데, 이름 휴리스틱은 언제든 빗나간다.
class MergedOutdoorResults {
  const MergedOutdoorResults(this.outdoorRows, this.indoorStores);

  /// "주변 장소" 섹션에 그릴 줄. 우리가 아는 가게를 가리키는 POI는 빠져 있다.
  final List<OutdoorSearchRow> outdoorRows;

  /// 위쪽 실내 섹션에 그릴 매장. **전부 그대로 남는다.**
  final List<PoiSearchResult> indoorStores;
}

/// POI 이름이 우리 건물을 **직접 부르고 있는지**. 좌표 판정의 짝이다 — POI 좌표는
/// 도로 접근점이라 거리 하나로는 어느 쪽으로도 안전한 값이 없다.
bool mentionsBuilding(String poiName, List<String> buildingNames) {
  final name = collapseName(poiName);
  return buildingNames.any((building) {
    final needle = collapseName(building);
    return needle.length >= 2 && name.contains(needle);
  });
}

/// [isAtBuilding]은 좌표로, [buildingNames]는 이름으로 "우리 건물 것"을 판정한다.
///
/// **두 신호를 OR로 묶는 것이 핵심이다** — 넓게 후보로 올리고 좁게 확정한다
/// ([matchIndoorStore]). 어느 쪽에도 안 걸리면 이름이 비슷해도 연결하지 않는다.
MergedOutdoorResults mergeOutdoorResults({
  required List<OutdoorPoi> pois,
  required List<PoiSearchResult> indoorStores,
  required bool Function(OutdoorPoi poi) isAtBuilding,
  List<String> buildingNames = const [],
}) {
  final rows = <OutdoorSearchRow>[];

  for (final poi in pois) {
    final atBuilding =
        isAtBuilding(poi) || mentionsBuilding(poi.name, buildingNames);
    // 우리 줄이 대신 보여줄 가게면 POI 줄은 뺀다. 못 찾으면 남긴다 — 우리가
    // 모르는 가게이므로 좌표까지라도 안내하는 편이 낫다.
    if (atBuilding && matchIndoorStore(poi, indoorStores) != null) continue;
    rows.add(OutdoorSearchRow(poi));
  }

  return MergedOutdoorResults(rows, indoorStores);
}
