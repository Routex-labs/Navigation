/// 서버가 확정한 매장 **옆에 함께 보여줄 같은 계열 매장**을 고른다.
///
/// ## 왜 필요한가
///
/// 1F에서 `구찌`를 치면 화면에 남는 것은 한 줄(`구찌 · 1F`)이고, `구찌 뷰티`(1F)와
/// `구찌 선글라스`(2F)는 사라진다. 타이핑 중에는 후보로 셋 다 보이다가 서버가
/// 답하는 순간 접힌다 — 방금 본 것이 사라지고, `구찌 뷰티`를 찾던 사람은 여기서
/// 길이 끊긴다.
///
/// 버그가 아니라 **계약**이다. `/query/destination`은 단일 목적지 계약이라 후보를
/// 담을 자리가 없고, 서버의 확정 판정(`_is_confident_light_match`)은 "최상위 tier
/// 그룹에 서로 다른 이름이 하나뿐"이면 확정으로 본다. `구찌`는 tier 0(정확 일치)
/// 단독 1위라 그 조건을 만족한다 — **의도대로 동작한 결과가 형제를 지운다.**
///
/// 서버 계약을 바꾸지 않고, **이미 기기에 있는 인덱스**로 그 자리를 메운다. 추가
/// 통신이 없다.
///
/// 설계 근거와 검증 기준은 `docs/client/search-result-list-ux.md` S절이 단일
/// 출처다.
library;

import 'store_suggestions.dart';

/// [suggestions] 중 [confirmedName]을 뺀 나머지를 돌려준다.
///
/// [confirmedName]은 서버가 확정한 매장 이름이다. **그 이름이 후보 목록에 없으면
/// 빈 목록을 돌려준다** — 아래 「적용하지 않는 경우」 참고.
///
/// **적용하지 않는 경우 셋** — 서버 결과가 후보 목록에 없을 때(서버는 카테고리로도
/// 확정하는데, 그때 후보들은 형제가 아니라 남남이다), 최상위가 교정 후보일 때,
/// 후보가 아예 없을 때.
///
/// 이름은 후보를 묶을 때와 **같은 [storeMatchKey]** 로 정규화해 비교한다 — 표기만
/// 다른 같은 이름을 서로 다른 매장으로 세면 같은 줄이 두 번 그려진다.
///
/// 형제를 탭하면 재검색이 돌지만 **맨 위는 항상 정확 일치 행**이라 막다른 길이
/// 없다. 실데이터에서 형제는 최대 3건이고 형제가 또 형제를 갖는 경우는 0건이다.
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
