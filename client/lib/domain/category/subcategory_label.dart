/// 소분류 원본값을 사용자에게 보여 줄 문구로 바꾼다.
///
/// 아이콘 표(`map/category_icon.dart`)가 아니라 domain에 둔다 — 표시 문구를 고르는
/// 것은 분류 규칙이고, 지도 쪽에 두면 domain이 지도를 import하게 된다.
library;

/// **이제 안전망이다.** 지금은 시드가 한글로 적재하지만, 배포 시차나 옛 타일로
/// 영어값이 들어오면 매핑 없이는 화면에 영어가 그대로 샌다. 없는 값은 이미 한글로
/// 보고 그대로 돌려준다.
const _subcategoryLabels = <String, String>{
  'restroom': '화장실',
  'elevator': '엘리베이터',
  'escalator': '에스컬레이터',
  // 새 시드는 `생활편의`다. 대분류(편의시설)와 같은 이름을 쓰면 "편의시설 >
  // 편의시설"이 되어 읽히지 않는다.
  'facility': '생활편의',
  'cafe': '카페·베이커리',
  'restaurant': '레스토랑',
};

String? subcategoryLabelFor(String? subcategory) {
  if (subcategory == null || subcategory.isEmpty) return null;
  return _subcategoryLabels[subcategory.toLowerCase()] ?? subcategory;
}
