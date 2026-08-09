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
/// ## 적용하지 않는 경우 (실패 조건을 먼저 정한 것)
///
/// - **서버 결과가 후보 목록에 없을 때.** 서버는 이름뿐 아니라 **카테고리**로도
///   확정한다(tier 1). `커피`가 업종으로 걸려 어떤 매장 1건이 확정된 경우, 후보
///   목록에 든 것들은 그 매장의 "형제"가 아니라 이름에 `커피`가 든 남남이다.
///   그걸 `관련 매장`이라고 묶으면 거짓말이 된다. 그래서 **서버 결과가
///   후보 안에 있을 때만** — 즉 이름으로 걸린 것이 확실할 때만 — 형제를 만든다.
/// - **교정 후보.** `SuggestionKind.correction`은 "표기가 비슷한 이름이 있다"는
///   추측이다. 서버가 이미 정답을 확정한 화면에 추측을 형제라며 얹지 않는다.
/// - **후보가 없을 때.** 인덱스를 못 받았거나(로드 실패) 야외라 만들지 않은
///   경우다. 빈 목록이 곧 "지금까지의 동작 그대로"다.
///
/// ## 이름은 정규화해서 비교한다
///
/// 표기만 다른 같은 이름(`물품 보관함`·`물품보관함`)을 서로 다른 매장으로 세면
/// 같은 줄이 두 번 그려진다. [storeMatchKey]로 맞춘다 — 후보를 묶을 때 쓴 것과
/// **같은 함수**다.
///
/// ## 무한 루프가 없는 이유
///
/// 형제를 탭하면 그 이름으로 검색을 다시 돌린다(`SearchPanel.onQueryPicked`).
/// 그 이름이 또 다른 이름의 접두이면 형제 목록이 한 번 더 뜰 수 있는데, 그때도
/// **맨 위는 정확 일치 행**이고 그 행은 재검색이 아니라 매장으로 곧장 간다. 즉
/// 어느 단계에서도 막다른 길이 아니다.
///
/// 실데이터(더현대 서울, 서로 다른 이름 655건)에서는 형제가 최대 3건이고 **형제가
/// 또 형제를 갖는 경우는 0건**이라, 실제로는 한 단계에서 끝난다.
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
