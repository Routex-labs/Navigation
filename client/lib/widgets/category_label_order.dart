/// 사용자에게 표시하는 카테고리 label의 정렬 규칙.
///
/// Dart의 [String.compareTo]는 유니코드 코드포인트 순으로 비교하며, 완성형
/// 한글 음절도 `가`부터 `힣`까지 가나다 순서로 배치되어 있어 현재 카테고리
/// label 정렬에 그대로 사용할 수 있다. 영문 label은 앞뒤 공백과 대소문자만
/// 보조 정규화하고, 화면에 표시하는 원문은 바꾸지 않는다.
int categoryLabelCompare(String a, String b) {
  final normalizedA = a.trim().toLowerCase();
  final normalizedB = b.trim().toLowerCase();
  final normalizedOrder = normalizedA.compareTo(normalizedB);
  return normalizedOrder != 0 ? normalizedOrder : a.compareTo(b);
}

/// 중복 label을 제거하고 사용자 표시 기준으로 정렬한다.
///
/// [leadingLabels]에 포함된 값이 실제 목록에 있으면 지정 순서대로 맨 앞에
/// 유지한다. 기본값인 `전체`가 원본에 없으면 새로 만들지는 않는다.
List<String> sortedCategoryLabels(
  Iterable<String?> labels, {
  List<String> leadingLabels = const ['전체'],
}) {
  final unique = <String>{};
  for (final label in labels) {
    if (label == null || label.trim().isEmpty) continue;
    unique.add(label);
  }

  final leading = <String>[];
  for (final label in leadingLabels) {
    if (unique.remove(label)) leading.add(label);
  }
  final sorted = unique.toList()..sort(categoryLabelCompare);
  return [...leading, ...sorted];
}
