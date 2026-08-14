/// 한 건물의 (층·대분류·소분류)별 매장 수 한 줄.
///
/// 지도 위 카테고리 필터가 pill 목록과 "이 층 N곳" 안내를 이걸로 만든다.
/// 예전에는 같은 정보를 얻으려고 층 지도(`/floors/{floor}`)를 **층마다** 받아
/// 매장을 세었다. 실측 접근 로그에서 그 요청이 130건이었고, 정작 쓰는 건 세
/// 문자열과 개수뿐인데 매장 폴리곤·좌표·navigation_graph가 전부 따라왔다.
class CategoryCount {
  const CategoryCount({
    required this.floor,
    required this.category,
    required this.subcategory,
    required this.count,
  });

  /// 층 라벨(예: `B2`). 층 지도 응답의 표기와 같다.
  final String floor;

  /// 대분류(예: `카페`).
  final String category;

  /// 소분류(예: `카페·베이커리`). 없는 매장이 있어 null을 허용한다.
  ///
  /// **표시 문구가 아니라 원본값이다.** 지도 필터가 타일 property와 이 값을
  /// 그대로 대조하므로 한글로 바꿔 담으면 안 된다.
  final String? subcategory;

  /// 그 조합의 매장 수.
  final int count;

  factory CategoryCount.fromJson(Map<String, dynamic> json) {
    return CategoryCount(
      floor: json['floor'] as String,
      category: json['category'] as String,
      subcategory: json['subcategory'] as String?,
      // 서버는 정수를 주지만, 숫자 타입이 흔들려도 목록 전체가 죽지 않게 한다.
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}
