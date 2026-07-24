import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 카테고리 대분류 이름에 대응하는 아이콘·색상. chip과 시트 헤더가 같은
/// 시각 정체성을 갖도록 두 곳에서 공유한다. 예상치 못한 카테고리는
/// 상점 기본 아이콘과 앱 primary 색으로 폴백한다.
const _iconByCategory = <String, IconData>{
  '패션': Icons.checkroom,
  '편의시설': Icons.info_outline,
  '식음료': Icons.restaurant,
  '리빙': Icons.weekend_outlined,
  '서비스': Icons.support_agent,
  '키즈': Icons.child_care,
  '뷰티': Icons.brush,
};

const _colorByCategory = <String, Color>{
  '패션': Color(0xFF7E57C2),
  '편의시설': Color(0xFF607D8B),
  '식음료': Color(0xFFF57C00),
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
IconData storeIconFor({String? name, String? subcategory}) {
  final sub = subcategory?.toLowerCase();
  switch (sub) {
    case 'restroom':
      return Icons.wc;
    case 'elevator':
      return Icons.elevator;
    case 'escalator':
      return Icons.escalator;
    case 'cafe':
      return Icons.local_cafe_outlined;
    case 'restaurant':
      return Icons.restaurant;
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
  return Icons.storefront;
}
