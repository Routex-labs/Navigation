/// 카테고리를 선택했을 때 **강조되는 매장**을 대분류 색으로 칠하는 규칙.
///
/// ## 평소에는 칠하지 않는다
///
/// 매장 폴리곤을 항상 대분류 색으로 칠어 두면 도면 전체가 색 밭이 되어 지금
/// 무엇이 선택됐는지가 오히려 안 읽힌다. 그래서 기본 매장 fill은 예전 회색
/// ([mapStoreFill]·[mapStoreOutline]) 그대로 두고, **카테고리 chip을 누른
/// 순간에만** 강조 레이어가 그 카테고리 색으로 칠한다.
///
/// ## 강조색은 파랑 하나가 아니라 대분류 색이다
///
/// 강조를 파랑 한 가지로 두면 "리빙을 눌렀다"와 "뷰티를 눌렀다"가 화면에서
/// 똑같이 보인다. chip·시트가 이미 대분류마다 다른 색을 쓰고 있으므로, 지도도
/// 같은 색으로 응답해야 "내가 누른 그 색"이 그대로 도면에 나타난다.
///
/// ## 색은 앱이 이미 쓰던 표를 그대로 쓴다
///
/// [categoryColorFor] — chip·시트·라벨 아이콘이 쓰는 것과 **같은 표**다. 지도만
/// 자기 색표를 갖게 두면 둘은 반드시 어긋나고, 사용자는 시트에서 초록으로 본
/// 리빙을 지도에서 다른 색으로 보게 된다.
///
/// ## 면은 옅게, 테두리는 진하게
///
/// 대분류 색을 면에 그대로 칠하면 그 위에 얹히는 매장명(`#444846`)이 읽히지
/// 않는다. 그래서 면은 흰색에 [_fillTintRatio]만큼 섞은 옅은 색으로 두고,
/// 구분은 테두리(대분류 색 원본)가 만든다. 예전 파란 강조가 옅은 면
/// (`#D6E4FC`) + 진한 선(`#4A87F1`)으로 쓰던 방식과 같고, 밝기도 그 언저리다.
///
/// `fillOutlineColor`는 **두께가 1px 고정**이라(근거는 [mapStoreOutline] 주석)
/// 더 굵게 감싸려면 같은 소스에 line 레이어를 따로 얹어야 한다. 지금은 1px로
/// 충분히 읽혀서 그 비용을 내지 않는다.
///
/// ## 강조 레이어 하나의 색만 데이터로 바꾼다
///
/// 카테고리마다 레이어를 따로 얹으면 z-순서·탭 처리·페이드(opacity)를 그 수만큼
/// 다시 맞춰야 하고, 순서가 어긋나면 수직이동 오버레이가 묻힌다. 대신 강조 레이어
/// **하나**를 두고 색만 데이터 기반 표현식으로 만든다. 어떤 매장이 강조될지는
/// 레이어 필터([categoryHighlightFilter])가 정하고, 표현식은 그렇게 남은 매장의
/// 색을 고를 뿐이다 — 표에 없는 대분류는 default로 떨어져 기본 매장 색 그대로라
/// 색표에 없는 카테고리를 눌러도 검정 덩어리가 되지 않는다.
///
/// `match`의 label 자리에 문자열만 넣는 형태는 라벨 아이콘
/// ([storeCategoryIconExpression])이 실기기에서 검증한 경로와 같다. 배열을 label로
/// 쓰는 형태는 MapLibre GL Native에서 조용히 매치 0건이 되는 경로가 있어 이
/// 저장소가 이미 한 번 데였다([category_map_filter.dart] 주석).
library;

import '../core/map_palette.dart';
import 'category_icon.dart';

/// 면에 섞는 대분류 색의 비율. 0이면 흰색, 1이면 대분류 색 원본이다.
///
/// 0.18은 강조 레이어의 옅은 파랑(`#D6E4FC`)과 비슷한 밝기가 나오는 값이다.
/// 이 값을 올리면 색은 선명해지지만 매장명(`#444846`)이 먼저 안 읽히기 시작한다
/// — 올릴 때는 가장 어두운 대분류(뷰티 `#E53935`·서비스 `#3F51B5`)를 기준으로
/// 본다. 임계값은 `tests/unit_test/category_map_fill_test.dart`가 지킨다.
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
