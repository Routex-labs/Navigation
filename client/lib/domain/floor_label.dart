/// 층 라벨을 위아래로 비교할 수 있게 읽는다.
///
/// **나열 순서에 기대지 않는다.** `Building.floors`의 순서는 서버 응답 순서일 뿐
/// 위아래를 약속하지 않는다. 라벨 자체가 위아래를 말한다.
library;

/// "1F" → 1, "B1" → -1. 숫자를 못 읽는 라벨(옥상 등 비표준)은 0 — 방향을
/// 단정하지 않는다는 뜻이다. 호출부는 0을 "모른다"로 다뤄야 한다.
int floorLabelRank(String label) {
  final m = RegExp(r'^(B?)(\d+)').firstMatch(label.toUpperCase());
  if (m == null) return 0;
  final n = int.parse(m.group(2)!);
  return m.group(1)!.isEmpty ? n : -n;
}
