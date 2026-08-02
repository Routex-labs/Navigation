import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 카테고리 대분류 이름에 대응하는 아이콘·색상·표시 라벨. chip과 시트 헤더가
/// 같은 시각 정체성을 갖도록 여러 곳에서 공유한다. 예상치 못한 카테고리는
/// 상점 기본 아이콘과 앱 primary 색으로 폴백한다.
/// 대분류 아이콘.
///
/// `식음료`는 **유통업계 용어라 사용자가 쓰는 말이 아니어서** 음식점·카페·식품관
/// 셋으로 나눴다(네이버지도도 음식점과 카페를 따로 둔다). 옛 이름을 지우지 않고
/// 남겨 두는 이유는 배포 시차다 — 클라이언트가 먼저 올라가고 백엔드 시드가
/// 아직 옛 어휘를 주는 동안, 지우면 그 매장들이 회색 storefront로 떨어진다.
const _iconByCategory = <String, IconData>{
  '패션': Icons.checkroom,
  '편의시설': Icons.info_outline,
  '음식점': Icons.restaurant,
  '카페': Icons.local_cafe_outlined,
  '식품관': Icons.local_grocery_store_outlined,
  '식음료': Icons.restaurant, // 구 어휘 — 위 주석 참고
  '리빙': Icons.weekend_outlined,
  '서비스': Icons.support_agent,
  '키즈': Icons.child_care,
  '뷰티': Icons.brush,
};

const _colorByCategory = <String, Color>{
  '패션': Color(0xFF7E57C2),
  '편의시설': Color(0xFF607D8B),
  // 음식점·카페·식품관은 한 갈래에서 나뉜 만큼 서로 붙어 있으면 구분이 안 된다.
  // 주황(음식) → 갈색(커피) → 초록(식재료)으로 연상이 다른 색을 골랐다.
  '음식점': Color(0xFFF57C00),
  '카페': Color(0xFF8D6E63),
  '식품관': Color(0xFF43A047),
  '식음료': Color(0xFFF57C00), // 구 어휘 — 위 주석 참고
  '리빙': Color(0xFF00897B),
  '서비스': Color(0xFF3F51B5),
  '키즈': Color(0xFFEC407A),
  '뷰티': Color(0xFFE53935),
};

IconData categoryIconFor(String category) =>
    _iconByCategory[category] ?? Icons.storefront;

Color categoryColorFor(String category) =>
    _colorByCategory[category] ?? AppColors.primary;

/// 매장 리스트에서 단일 아이템 왼쪽에 붙는 아이콘. 편의시설처럼 이질적인
/// 하위 항목이 섞이는 카테고리에서 어떤 종류인지 한 눈에 알 수 있게 한다.
/// subcategory가 있으면 그것으로 먼저 판정하고, 없으면 매장 이름의 부분
/// 문자열(정수기·ATM·수유실 등)로 판정한다. 어느 규칙에도 걸리지 않는
/// 일반 매장은 상점 아이콘([Icons.storefront])으로 폴백한다.
///
/// subcategory 표기가 두 갈래라 양쪽을 모두 받는다. 층 원본(studio JSON)에서
/// 온 시설물은 `restroom`·`elevator` 같은 영어 소문자이고, 카테고리 오버라이드
/// (store_categories*.json)를 거친 매장은 `레스토랑`·`카페·베이커리` 같은 한글이다.
///
/// [category]를 주면 어느 세부 규칙에도 걸리지 않았을 때 상점 아이콘 대신 대분류
/// 아이콘으로 떨어진다. 매장의 78%가 Studio 원본에서 `매장`이라는 무의미한
/// subcategory를 갖고 있어, 세부 규칙만으로는 대부분이 같은 글리프가 된다.
IconData storeIconFor({String? name, String? subcategory, String? category}) {
  final sub = subcategory?.toLowerCase();
  switch (sub) {
    // 영어 원본값은 이제 시드에서 한글로 들어오지만, 배포 시차 동안 옛 타일·
    // 옛 응답이 영어를 줄 수 있어 양쪽을 모두 받는다.
    case 'restroom':
    case '화장실':
      return Icons.wc;
    case 'elevator':
    case '엘리베이터':
      return Icons.elevator;
    case 'escalator':
    case '에스컬레이터':
      return Icons.escalator;
    case 'cafe':
    case '카페·베이커리':
      return Icons.local_cafe_outlined;
    case 'restaurant':
    case '레스토랑':
      return Icons.restaurant;
    case '식품·그로서리':
      return Icons.local_grocery_store_outlined;
    case '와인·주류':
      return Icons.wine_bar_outlined;
  }
  final n = name ?? '';
  if (n.contains('화장실') || n.contains('세면대')) return Icons.wc;
  if (n.contains('정수기')) return Icons.water_drop_outlined;
  if (n.contains('ATM') || n.contains('은행')) return Icons.local_atm;
  if (n.contains('수유실')) return Icons.child_friendly;
  if (n.contains('흡연')) return Icons.smoking_rooms;
  if (n.contains('취식')) return Icons.dining_outlined;
  if (n.contains('엘리베이터')) return Icons.elevator;
  if (n.contains('에스컬레이터')) return Icons.escalator;
  if (n.contains('물품보관') || n.contains('락커')) return Icons.lock_outline;
  if (category != null && _iconByCategory.containsKey(category)) {
    return _iconByCategory[category]!;
  }
  return Icons.storefront;
}

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
