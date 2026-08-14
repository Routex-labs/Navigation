/// 서버가 확정한 매장 **옆에 함께 보여줄 같은 계열 매장**을 고른다.
///
/// `구찌`를 치면 `구찌 뷰티`·`구찌 선글라스`가 사라진다. 버그가 아니라 **계약**이다 —
/// `/query/destination`은 단일 목적지 계약이고 서버는 tier 0 단독 1위를 확정으로
/// 본다. 의도대로 동작한 결과가 형제를 지운다.
///
/// 서버 계약을 바꾸지 않고 **기기에 있는 인덱스**로 메운다(추가 통신 없음).
/// 근거와 검증 기준은 `docs/client/search-result-list-ux.md` S절.
library;

import 'store_suggestions.dart';

/// [suggestions] 중 [confirmedName]을 뺀 나머지를 돌려준다.
///
/// **적용하지 않는 경우 셋** — 서버 결과가 후보 목록에 없을 때(카테고리로 확정한
/// 경우라 후보들은 형제가 아니라 남남이다), 최상위가 교정 후보일 때, 후보가 없을 때.
///
/// 이름은 후보를 묶을 때와 **같은 [storeMatchKey]** 로 비교한다. 실데이터에서
/// 형제는 최대 3건이고 형제가 또 형제를 갖는 경우는 0건이다.
List<StoreSuggestion> nameSiblings({
  required List<StoreSuggestion> suggestions,
  required String confirmedName,
}) {
  final confirmedKey = storeMatchKey(confirmedName);
  if (confirmedKey.isEmpty) return const [];

  var found = false;
  final siblings = <StoreSuggestion>[];
  for (final suggestion in suggestions) {
    if (suggestion.kind.isCorrection) continue;
    if (storeMatchKey(suggestion.stores.first.name) == confirmedKey) {
      found = true;
      continue;
    }
    siblings.add(suggestion);
  }
  // 서버가 확정한 매장이 후보 안에 없으면 이름으로 걸린 것이 아니다.
  if (!found) return const [];
  return siblings;
}
