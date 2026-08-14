/// 소분류 원본값을 사용자에게 보여 줄 문구로 바꾼다.
///
/// 아이콘 표(`map/category_icon.dart`)가 아니라 domain에 둔다. 표시 문구를
/// 고르는 것은 분류 규칙이지 지도 표현이 아니고, 실제로 분류 계산
/// ([category_taxonomy.dart])이 이 함수를 쓴다 — 지도 쪽에 두면 domain이
/// 지도를 import하게 되어 계층이 거꾸로 선다.
library;

/// 사용자에게 보여 줄 subcategory 문구.
///
/// **이 매핑은 이제 안전망이다.** 예전에는 Studio 원본의 영어 열거값
/// (`restroom`·`facility` 등)이 그대로 DB에 들어와 화면 직전에 여기서 한글로
/// 바꿔야 했지만, 지금은 시드가 한글로 적재한다. 그래도 지우지 않는 이유는
/// 배포 시차와 캐시다 — 클라이언트가 먼저 올라가거나 옛 타일이 남아 있는 동안
/// 영어값이 들어오면, 매핑이 없으면 화면에 영어가 그대로 샌다.
///
/// 매핑에 없는 값은 이미 한글이므로 그대로 돌려준다.
const _subcategoryLabels = <String, String>{
  'restroom': '화장실',
  'elevator': '엘리베이터',
  'escalator': '에스컬레이터',
  // 새 시드는 `생활편의`로 적재한다. 대분류(편의시설)와 같은 이름을 쓰면
  // "편의시설 > 편의시설"이 되어 읽히지 않기 때문이다. 옛 값만 여기서 받는다.
  'facility': '생활편의',
  'cafe': '카페·베이커리',
  'restaurant': '레스토랑',
};

String? subcategoryLabelFor(String? subcategory) {
  if (subcategory == null || subcategory.isEmpty) return null;
  return _subcategoryLabels[subcategory.toLowerCase()] ?? subcategory;
}
