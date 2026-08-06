/// 카테고리 필터가 지도에 걸리는 방식을 한 곳에 모은다.
///
/// 실내 화면(`FloorPlanView`)과 야외 지도의 실내 오버레이(`OutdoorMapBody`)는
/// **같은 서버 MVT 타일**의 `stores` 레이어를 본다. 두 화면이 서로 다른 필터
/// 규칙을 갖게 되면 같은 선택인데 강조되는 매장이 달라지므로, 표현식을 만드는
/// 규칙은 이 파일 하나로 고정한다.
library;

/// 지도에서 강조할 카테고리 선택.
///
/// [subcategory]가 null이면 대분류 전체를 강조한다("식음료" 전체). 값이 있으면
/// 그 소분류까지 좁힌다("식음료 > 카페·베이커리").
///
/// **[subcategory]는 화면에 보이는 label이 아니라 타일 property 원본값이다.**
/// 편의시설 소분류 일부는 원본이 영어(`restroom`·`elevator` 등)이고 화면에는
/// 한글로 표시되므로, 이 둘을 섞으면 필터가 조용히 0건이 된다.
class CategorySelection {
  const CategorySelection({required this.category, this.subcategory});

  /// 대분류 원본값 (예: `식음료`).
  final String category;

  /// 소분류 원본값 (예: `카페·베이커리`, `restroom`). null이면 대분류 전체.
  final String? subcategory;

  @override
  bool operator ==(Object other) =>
      other is CategorySelection &&
      other.category == category &&
      other.subcategory == subcategory;

  @override
  int get hashCode => Object.hash(category, subcategory);

  @override
  String toString() =>
      'CategorySelection($category${subcategory == null ? '' : ' > $subcategory'})';
}

/// 선택을 MapLibre 필터 표현식으로 바꾼다.
///
/// 표현식 형태를 `['all', ['==', ['get', ...], ...], ...]`로 고정하는 이유는
/// `floor_plan_view.dart`의 수직이동 레이어 주석과 같다 — `['match', ...]`나
/// `['in', ..., ['literal', [...]]]`처럼 인자 자리에 배열이 들어가는 형태는
/// MapLibre GL Native(Android/iOS)에서 항상 안정적으로 파싱되지 않아, 예외도
/// 로그도 없이 **매치 0건**이 되는 경우가 있었다. `==` 비교만 쓰는 이 형태는
/// 이 저장소에서 이미 실기기로 검증된 경로다.
///
/// 웹(maplibre_gl_web)은 파싱 경로가 달라 잘못된 형태도 잘 동작하므로,
/// Chrome에서만 확인하면 이 함정을 절대 못 잡는다.
List<Object> categoryHighlightFilter(CategorySelection selection) {
  final subcategory = selection.subcategory;
  return [
    'all',
    [
      '==',
      ['get', 'category'],
      selection.category,
    ],
    if (subcategory != null)
      [
        '==',
        ['get', 'subcategory'],
        subcategory,
      ],
  ];
}

/// 강조 레이어가 꺼져 있을 때 걸어 두는, 아무것도 맞지 않는 필터.
///
/// 레이어를 지웠다 다시 만들지 않고 필터만 갈아 끼우는 편이 안전하다 —
/// `addFillLayer`/`removeLayer`를 반복하면 네이티브가 이전 레이어 정리를
/// 스케줄만 한 채 리턴해 다음 추가가 조용히 실패하는 경로를 밟게 된다
/// (`outdoor_map_screen.dart`의 addSource 주석과 같은 종류의 문제).
const List<Object> kCategoryHighlightNoneFilter = [
  '==',
  ['get', 'kind'],
  '__카테고리_선택_없음__',
];

/// 강조된 매장 폴리곤의 **색**은 여기 있지 않다. 선택한 대분류마다 달라지므로
/// [category_map_fill.dart]의 표현식이 정한다 — 이 파일은 "어떤 매장이
/// 강조되는가"(필터)만 담당한다.
