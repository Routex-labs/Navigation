/// 카테고리를 선택했을 때 **강조되는 매장**을 대분류 색으로 칠하는 규칙.
///
/// 평소에는 칠하지 않는다 — 항상 칠하면 도면이 색 밭이 되어 무엇이 선택됐는지가
/// 오히려 안 읽힌다. 색은 chip·시트와 **같은 표**를 쓴다.
///
/// 카테고리마다 레이어를 얹지 않고 **강조 레이어 하나**의 색만 바꾼다.
/// 그 밖의 근거는 `docs/client/map-style-rules.md` 4절.
library;

import 'palette.dart';
import 'category_icon.dart';

/// 면에 섞는 대분류 색의 비율. 0이면 흰색, 1이면 대분류 색 원본이다.
///
/// 0.18은 강조 레이어의 옅은 파랑(`#D6E4FC`)과 비슷한 밝기가 나오는 값이다.
/// 이 값을 올리면 색은 선명해지지만 매장명(`#444846`)이 먼저 안 읽히기 시작한다.
/// 임계값은 `tests/unit_test/category_map_fill_test.dart`가 지킨다.
///
/// 아홉 대분류가 전부 뮤트 중간톤(원본 상대 휘도 0.38~0.52)으로 통일되면서,
/// 유독 어두운 대분류(구 서비스 `#3F51B5` 등)가 하한을 끌어내리던 시절보다
/// 여유가 생겼다. 그래도 0.18을 유지한다 — 기준이 "면이 어두운가"가 아니라
/// "예전 파란 강조와 같은 밝기 대역인가"이기 때문이고, 올리는 판단은 실기기에서
/// 매장명 가독을 다시 확인한 뒤에 한다.
const _fillTintRatio = 0.18;

String _hex(int r, int g, int b) {
  final rgb = (r << 16) | (g << 8) | b;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

int _mixOverWhite(double channel) =>
    (channel * 255 * _fillTintRatio + 255 * (1 - _fillTintRatio)).round().clamp(
      0,
      255,
    );

/// 매장 면에 쓰는 옅은 대분류 색(`#RRGGBB`).
String categoryFillTintHex(String category) {
  final color = categoryColorFor(category);
  return _hex(
    _mixOverWhite(color.r),
    _mixOverWhite(color.g),
    _mixOverWhite(color.b),
  );
}

/// 매장 경계선에 쓰는 대분류 색 원본(`#RRGGBB`).
String categoryOutlineHex(String category) {
  final color = categoryColorFor(category);
  return _hex(
    (color.r * 255).round(),
    (color.g * 255).round(),
    (color.b * 255).round(),
  );
}

/// `stores` feature의 `category`로 강조 면 색을 고르는 표현식.
///
/// default는 [mapStoreFill] — 표에 없는 대분류거나 타일에 `category` 키가 아예
/// 없는 매장(`tiling.py`의 `_store_properties`는 null이면 키를 싣지 않는다)은
/// 강조돼도 기본 매장 색 그대로다(= 눈에 띄는 변화가 없을 뿐 깨지지 않는다).
List<Object> storeCategoryHighlightFillColorExpression() => [
  'match',
  ['get', 'category'],
  for (final category in categoryPaletteCategories) ...[
    category,
    categoryFillTintHex(category),
  ],
  mapStoreFill,
];

/// 같은 규칙의 경계선 색. default는 [mapStoreOutline].
List<Object> storeCategoryHighlightOutlineExpression() => [
  'match',
  ['get', 'category'],
  for (final category in categoryPaletteCategories) ...[
    category,
    categoryOutlineHex(category),
  ],
  mapStoreOutline,
];
