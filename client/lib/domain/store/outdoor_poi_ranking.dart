/// 야외 검색(TMAP POI) 결과를 **화면에 올리기 전에** 손보는 순수 규칙.
///
/// 화면 코드에서 분리한 이유는 이 규칙을 **두 곳이 함께 써야 하기 때문**이다.
/// 상단 검색창과 길찾기 시트가 각자 걸러 내면 반드시 갈리고, 이 화면에서는
/// 실제로 반복해서 갈렸다. 규칙은 여기 한 곳에 두고 호출만 두 번 한다.
library;

import '../../models/outdoor_poi.dart';
import '../../models/poi_search_result.dart';

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

/// 이름의 **브랜드 부분**(첫 어절). "스타벅스 더현대서울(B2)R점" → `스타벅스`
///
/// 우리 백엔드에 다시 물어볼 때 쓰는 검색어다. 사용자가 친 말("더현대 스타벅스")
/// 로는 우리 DB가 아무것도 못 찾는다 — 우리는 그 가게를 "스타벅스 리저브"라고
/// 부르기 때문이다. 브랜드만 떼어 물어야 후보가 나온다.
String brandOf(String name) {
  final trimmed = name.trim();
  final space = trimmed.indexOf(RegExp(r'\s'));
  return space < 0 ? trimmed : trimmed.substring(0, space);
}

String _firstWord(String value) => brandOf(value);

/// TMAP 지점명 안에 괄호로 들어 있는 **층 힌트**를 뽑는다. 없으면 null.
///
/// "스타벅스 더현대서울**(B2)**R점" → `B2`
///
/// 이게 왜 필요한가 — **좌표로는 층을 고를 수 없기 때문이다.** 한 건물의 열두
/// 개 층이 같은 위경도 위에 쌓여 있는데 TMAP은 층 필드를 주지 않는다. 좌표만
/// 보고 "가장 가까운 매장"을 고르면 B2 스타벅스 대신 벽에 붙은 1층 아무 매장이
/// 잡히고, 화면은 조용히 엉뚱한 곳으로 안내한다. 층은 이름에만 있다.
///
/// 지하(B)·지상 모두 받는다. 층이 아닌 괄호 내용(예: "(주)")은 숫자가 없어
/// 걸리지 않는다.
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
/// 브랜드 이름으로 후보를 추리고, 이름에 층 힌트가 있으면 그 층으로 좁힌다.
/// 남은 후보가 **정확히 하나일 때만** 확정한다.
///
/// 애매하면 포기하는 쪽이 맞다. 여기서 잘못 고르면 사용자는 "안내가 안 된다"가
/// 아니라 **엉뚱한 매장 앞에 도착한다.** 앞은 다시 시도하면 되지만 뒤는 걸어간
/// 시간을 돌려받지 못한다. 포기하면 호출부가 건물 입구까지 안내로 떨어뜨린다.
///
/// 노드가 없는 매장은 후보에서 뺀다 — 연결해 봐야 실내 경로를 못 만든다.
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

/// 바깥 목록의 한 줄.
///
/// 여기까지 온 POI는 **우리가 모르는 곳**이다. 우리 실내 데이터가 아는 가게를
/// 가리키는 POI는 목록을 만들 때 이미 빠진다([mergeOutdoorResults]) — 그 가게는
/// 우리 줄이 층·노드를 달고 대신 보여준다.
class OutdoorSearchRow {
  const OutdoorSearchRow(this.poi);

  final OutdoorPoi poi;
}

/// 바깥 결과와 우리 실내 결과를 **한 목록으로** 합친 뒤 돌려준다.
///
/// 같은 가게가 두 줄로 뜨던 화면을 고치는 자리다 — "스타벅스 리저브 / B2"(우리)와
/// "스타벅스 더현대서울(B2)R점"(TMAP)이 나란히 떴고, 아래쪽을 고르면 실내 경로가
/// 안 나왔다.
///
/// 합치는 방향은 **우리 쪽으로**다. 우리 줄을 남기고 겹치는 POI 줄을 뺀다.
///
/// 한때 반대로 했다 — POI 줄을 남기고 거기에 우리 층·노드를 실었다. 사용자가
/// 검색해서 본 이름이 POI 이름이라는 이유였는데, 그 방향은 **매칭이 성공해야만
/// 실내 안내가 된다**는 약점이 있다. 매칭은 이름 휴리스틱이라 언제든 빗나가고,
/// 빗나가면 사용자는 건물 입구에서 안내가 끊긴 화면을 본다.
///
/// 우리 쪽을 남기면 실내 안내는 **매칭과 무관하게** 확실하다(층·노드가 원래
/// 거기 있다). 매칭은 "POI 줄 하나를 뺄지"만 정하므로, 빗나가도 손해가 중복 한
/// 줄로 끝난다. 대신 이름이 우리 것("스타벅스 리저브")이라 어느 건물인지 안
/// 보이는데, 그건 부제에 건물 이름을 함께 적어 푼다.
class MergedOutdoorResults {
  const MergedOutdoorResults(this.outdoorRows, this.indoorStores);

  /// "주변 장소" 섹션에 그릴 줄. 우리가 아는 가게를 가리키는 POI는 빠져 있다.
  final List<OutdoorSearchRow> outdoorRows;

  /// 위쪽 실내 섹션에 그릴 매장. **전부 그대로 남는다.**
  final List<PoiSearchResult> indoorStores;
}

/// POI 이름이 우리 건물을 **직접 부르고 있는지**. "스타벅스 **더현대서울**(B2)R점"
///
/// 좌표 판정의 짝이다. TMAP POI 좌표는 도로 접근점이라 큰 건물에서는 외곽선에서
/// 꽤 떨어져 찍히는데, 어느 정도 떨어지는지는 건물마다 다르다. 허용 거리를
/// 넓히면 길 건너 가게를 삼키고, 좁히면 정작 입점 매장을 놓친다 — 거리 하나로는
/// 어느 쪽으로도 안전한 값이 없다.
///
/// 이름은 그 애매함이 없다. TMAP 지점명은 대개 건물 이름을 그대로 달고 있고,
/// 달고 있다면 그건 우연이 아니다.
bool mentionsBuilding(String poiName, List<String> buildingNames) {
  final name = collapseName(poiName);
  return buildingNames.any((building) {
    final needle = collapseName(building);
    return needle.length >= 2 && name.contains(needle);
  });
}

/// [isAtBuilding]은 POI 좌표가 우리 도면이 있는 건물에 딸린 자리인지 판정한다.
/// [buildingNames]는 우리가 도면을 가진 건물 이름이며, POI 이름이 그중 하나를
/// 달고 있으면 좌표와 무관하게 그 건물 것으로 본다.
///
/// **두 신호를 OR로 묶는 것이 핵심이다.** 좌표만 보면 도로 접근점 때문에 입점
/// 매장을 놓치고, 이름만 보면 건물 이름을 안 단 입점 매장을 놓친다. 둘 중
/// 하나라도 걸리면 "이 건물 것"으로 보고, 실제로 합칠지는 그다음 브랜드·층
/// 판정([matchIndoorStore])이 정한다 — 넓게 후보로 올리고 좁게 확정한다.
///
/// 어느 신호에도 안 걸린 POI는 이름이 비슷해도 연결하지 않는다 — 길 건너
/// 스타벅스는 우리 건물 안 스타벅스와 **다른 가게**다.
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
