/// 대분류(식음료) → 소분류(레스토랑·카페·베이커리) 2단계 카테고리 필터가 쓰는
/// 데이터 가공 규칙. 위젯을 만들지 않고 순수 함수만 두는 이유는 이 규칙이
/// 지도 필터·목록 시트 등 여러 화면에서 같아야 하고, 위젯 없이 테스트로
/// 고정할 수 있어야 하기 때문이다.
///
/// 이 파일에서 가장 중요한 전제는 **표시 label과 필터 value가 다르다**는 것이다.
/// 층 원본(studio JSON)에서 온 시설물의 subcategory는 `restroom`·`elevator`
/// 같은 영어 열거값이라 화면에 그대로 나가면 안 되지만, 지도 타일 property는
/// 그 영어 원본값을 그대로 들고 있어서 필터는 원본값으로 걸어야 한다.
/// 한글 표시 문구는 [subcategoryLabelFor]가 이미 담당하므로 여기서 다시
/// 매핑을 만들지 않고 재사용한다.
library;

import '../core/map/category_icon.dart';
import './category_label_order.dart';

/// pill 하나가 나타내는 소분류. 화면 표시용 label과 지도 필터에 넣을 원본
/// value를 분리해서 들고 있다.
///
/// 둘을 한 필드로 합치면 `restroom`을 '화장실'로 보여주는 순간 지도 타일과
/// 대조할 값을 잃어버린다. 반대로 원본값만 들고 있으면 화면에 영어가 샌다.
class SubcategoryOption {
  const SubcategoryOption({required this.value, required this.label});

  /// 지도 타일 property와 대조할 원본값 (예: `restroom`).
  final String value;

  /// 화면 표시 (예: `화장실`).
  final String label;

  /// 테스트와 디버깅에서 목록 비교를 쉽게 하려고 값 동등성을 준다.
  /// pill 목록은 매 프레임 새로 만들어지므로 참조 동등성으로는 비교가 안 된다.
  @override
  bool operator ==(Object other) =>
      other is SubcategoryOption &&
      other.value == value &&
      other.label == label;

  @override
  int get hashCode => Object.hash(value, label);

  @override
  String toString() => 'SubcategoryOption($value, $label)';
}

/// 필터 pill 목록에서 감추는 소분류 원본값.
/// 경로 안내에는 쓰이지만 '둘러보기' 대상은 아닌 것들이다.
///
/// 판단 기준은 "사용자가 이 pill을 눌러서 목록을 훑어볼 이유가 있는가"다.
/// - `주차`(787건): 매장이 아니라 주차 구획이다. 편의시설 1,095건 중 72%를
///   혼자 차지해서, 노출하면 다른 pill이 전부 이것에 묻힌다.
/// - `escalator`(152건)·`elevator`(68건): 개별 도착지로 고를 대상이 아니다.
///   층 이동이 필요하면 다익스트라가 알아서 이 노드들을 경유지로 쓴다.
/// - `교통`(7건): 지하철 등 건물 외부 시설이라 실내 매장 탐색과 무관하다.
///
/// 반대로 `facility`(52건)·`restroom`(27건)·`락커`(6건)는 감추지 않는다.
/// 화장실·물품보관함은 사용자가 "어디 있지?" 하고 직접 찾는 대상이라
/// 둘러보기 가치가 분명하다.
///
/// 실제 층 데이터의 subcategory는 영어 소문자이므로 그 표기를 우선으로 넣고,
/// 다른 seed 경로(store_categories*.json 오버라이드)에서 한글로 들어올
/// 가능성에 대비해 대응되는 한글 표기도 함께 둔다. 이 목록은
/// `category_stores_sheet.dart`가 목록 시트에서 쓰는 제외 기준과 같은
/// 판단을 따른다 — 같은 항목이 시트에선 빠지고 pill에선 나오면 안 된다.
const Set<String> kHiddenSubcategoryValues = {
  '주차',
  '교통',
  'escalator',
  '에스컬레이터',
  'elevator',
  '엘리베이터',
};

/// 주어진 대분류에 속한 매장들에서 pill로 노출할 소분류를 뽑는다.
///
/// - [kHiddenSubcategoryValues] 제외 (대소문자 무시 — 원본이 `Elevator`처럼
///   들어와도 걸러지게)
/// - null·빈 문자열(공백만 있는 값 포함) 제외
/// - 원본값 기준 중복 제거. label이 아니라 value로 묶는 이유는, 필터가 결국
///   원본값으로 걸리기 때문이다. label로 묶어 버리면 서로 다른 두 원본값이
///   한 pill로 합쳐져 한쪽 매장이 필터에서 통째로 사라진다.
/// - 표시 label 기준 정렬. 사용자가 보는 순서는 사용자가 읽는 글자 기준이어야
///   해서 원본값이 아닌 label로 정렬한다 (`restroom`을 r 자리가 아니라
///   '화장실' 자리에 놓는다).
/// - `전체` 옵션은 넣지 않는다. 이 함수는 데이터에 실제로 있는 것만 돌려주고,
///   가상 옵션을 붙이는 건 UI 책임이다.
List<SubcategoryOption> subcategoryOptionsFor(
  String category,
  Iterable<(String? category, String? subcategory)> stores,
) {
  // value → option. 먼저 만난 것을 유지하지만 label은 같은 value면 같으므로
  // 순서에 따른 결과 차이는 없다.
  final byValue = <String, SubcategoryOption>{};

  // 레코드의 위치 필드에 붙은 이름(category·subcategory)은 Dart에서 문서용일
  // 뿐이라 실제 접근은 $1·$2로 한다. 읽는 쪽이 헷갈리지 않게 바로 이름을 준다.
  for (final (storeCategory, raw) in stores) {
    if (storeCategory != category) continue;

    if (raw == null || raw.trim().isEmpty) continue;
    if (kHiddenSubcategoryValues.contains(raw) ||
        kHiddenSubcategoryValues.contains(raw.toLowerCase())) {
      continue;
    }

    // subcategoryLabelFor는 매핑에 없으면 원본을 그대로 돌려주므로, 이미 한글
    // 오버라이드를 거친 값은 그대로 통과한다. null은 위에서 이미 걸렀으니
    // 여기서는 나올 수 없지만 방어적으로 원본으로 폴백한다.
    final label = subcategoryLabelFor(raw) ?? raw;
    byValue[raw] = SubcategoryOption(value: raw, label: label);
  }

  final options = byValue.values.toList();
  options.sort((a, b) {
    final byLabel = categoryLabelCompare(a.label, b.label);
    // label이 같은 서로 다른 원본값(예: `cafe`와 `카페·베이커리`가 함께
    // 들어온 경우)이 있으면 순서가 입력 순서에 따라 흔들리지 않도록
    // 원본값으로 마지막 tie-break를 건다.
    return byLabel != 0 ? byLabel : a.value.compareTo(b.value);
  });
  return options;
}

/// 소분류 pill 줄을 띄울 가치가 있는지. 노출 대상이 2개 미만이면 false —
/// 뷰티(소분류가 `화장품·향수` 하나뿐)처럼 선택지가 하나인 대분류에서
/// 눌러도 결과가 안 바뀌는 탭이 한 번 더 끼는 걸 막는다.
///
/// UI가 붙이는 `전체`까지 세면 2개가 되지만, `전체`와 유일한 소분류는 같은
/// 집합을 가리키므로 실질 선택지는 하나다. 그래서 `전체`를 붙이기 전 목록으로
/// 판정한다.
bool hasMeaningfulSubcategories(List<SubcategoryOption> options) =>
    options.length >= 2;
