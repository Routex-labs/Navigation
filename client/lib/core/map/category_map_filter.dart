/// 카테고리 필터가 지도에 걸리는 방식을 한 곳에 모은다.
///
/// 야외 지도의 실내 오버레이(`OutdoorMapBody`)가 서버 MVT 타일의 `stores`
/// 레이어에 거는 필터다. 예전에는 실내 전용 화면도 같은 타일을 보면서 자기
/// 필터를 따로 들고 있었고, 같은 선택인데 강조되는 매장이 화면마다 달랐다.
/// 그 화면은 지웠지만 규칙을 한 파일에 고정해 두는 이유는 그대로다 —
/// 필터는 여러 레이어에 나뉘어 걸리므로 원본이 하나여야 한다.
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
/// 표현식 형태를 `['all', ['==', ['get', ...], ...], ...]`로 고정한다.
/// `['match', ...]`나
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

/// 매장명 라벨의 `text-field`. 카테고리를 고르면 **그 매장만 이름을 단다.**
///
/// ## 왜 이름을 가리는가
///
/// 카테고리를 고르는 순간 사용자가 찾는 것은 그 업종의 매장뿐인데, 도면에는
/// 층 전체의 매장 이름이 같은 무게로 떠 있다. 강조색만으로 찾으려면 파란
/// 폴리곤을 눈으로 훑은 뒤 그 위의 이름을 다시 읽어야 한다. 나머지 이름을
/// 내리면 남는 글자가 곧 답이 된다.
///
/// **아이콘은 남긴다.** 이름까지 통째로 지우면 그 폴리곤이 매장인지 통로인지
/// 알 수 없어 도면이 맥락을 잃는다 — 매장을 아예 숨기지 않고 강조만 하는
/// [categoryHighlightFilter]의 판단과 같은 이유다. 아이콘 하나만 남아도 "여기는
/// 다른 업종의 매장"이라는 정보는 유지된다.
///
/// ## 왜 `case`인가 — 레이어를 나누지 않았다
///
/// "이름 다는 매장"과 "아이콘만 두는 매장"을 심볼 레이어 두 개로 나눌 수도
/// 있었다. 그러면 갱신이 `setFilter`만으로 끝나 이 저장소가 선호하는 경로가
/// 되지만, 라벨 레이어를 하나로 유지한 이유
/// ([category_map_icon.dart]의 "아이콘을 별도 레이어로 두지 않는다")를 절반
/// 되돌리게 된다. 대신 갱신 때 **레이어의 전체 속성을 다시 넘기는** 규칙
/// ([indoor_overlay_layers.dart] 상단)을 지킨다.
///
/// `case`는 이 파일이 경계하는 형태와 다르다. 조용히 0건이 되던 것은
/// `['match', ..., <배열 label>, ...]`이나 `['in', ..., ['literal', [...]]]`처럼
/// **인자 자리에 데이터 배열**이 오는 형태였고, `case`의 인자는 배열이 아니라
/// 불리언 표현식이다. 조건에는 [categoryHighlightFilter]를 그대로 넣어,
/// 강조되는 매장과 이름이 남는 매장이 **정의상 같은 집합**이 되게 한다.
List<Object> categoryLabelTextField(CategorySelection? selection) {
  const nameField = <Object>['get', 'name'];
  // 선택이 없으면 예전 그대로 — 모든 매장이 이름을 단다.
  if (selection == null) return nameField;
  // 빈 문자열이면 MapLibre가 글자 상자를 만들지 않는다. 심볼이 아이콘 폭으로
  // 줄어들어 충돌 예산도 함께 비는데, 그 자리를 남은 이름들이 가져간다.
  return <Object>['case', categoryHighlightFilter(selection), nameField, ''];
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
