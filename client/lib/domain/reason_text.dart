/// 추천 이유에서 **그 매장만의 근거**를 남긴다.
///
/// 서버가 주는 `reason`은 질의 전체의 근거와 그 매장의 근거를 한 문장씩 이어 붙인
/// 것이다(`query_search._reason`). 예를 들어 `신발` 질의의 목록은 이렇게 온다.
///
/// ```text
/// 폴리테루  신발 관련 매장이에요. 캐주얼 스타일 매장이에요.
/// 미우미우  신발 관련 매장이에요. 컨템포러리 스타일 매장이에요.
/// 몽클레르  신발 관련 매장이에요. 명품 스타일 매장이에요.
/// ```
///
/// 앞 문장은 세 행이 똑같다. 그건 목록 머리말(`뜻이 비슷한 매장을 찾았어요`)이 이미
/// 말하고 있으므로 행마다 되풀이하면 정보량이 0이면서 자리만 먹는다. 실제로 그 자리는
/// **층**이 있던 자리라, 행마다 다른 정보를 행마다 같은 문장이 밀어낸 셈이었다.
///
/// **서버 쪽에서 빼지 않는 이유**가 있다. `reason`은 한 건만 떼어 봐도 근거가 서야
/// 한다는 계약이다(`test_추천_이유는_질문축과_질의_intent를_함께_말한다` — 질문 축만
/// 담으면 "신발"을 물은 사용자에게 "명품 스타일 매장이에요"만 남는다). 여러 행을 함께
/// 놓고 볼 때 무엇이 겹치는지는 **화면만 아는 사실**이므로 여기서 처리한다.
library;

/// `reason`을 문장 단위로 쪼갠다. 서버는 `…이에요.` 뒤에 공백을 두고 잇는다.
///
/// **원문의 구두점을 그대로 둔다.** `split('.')` 뒤에 마침표를 일괄로 되붙이면, 마침표
/// 없이 끝난 근거에 없던 마침표가 생긴다. 쪼갠 조각을 다시 이었을 때 원문과 같아야
/// 화면에 나가는 글자가 서버가 준 것과 어긋나지 않는다.
List<String> reasonSentences(String reason) {
  final trimmed = reason.trim();
  if (trimmed.isEmpty) return const [];
  final sentences = <String>[];
  var start = 0;
  for (var index = 0; index < trimmed.length; index++) {
    if (trimmed[index] != '.') continue;
    final part = trimmed.substring(start, index + 1).trim();
    if (part.isNotEmpty) sentences.add(part);
    start = index + 1;
  }
  // 마침표 없이 끝난 꼬리. 있으면 그대로 한 문장으로 센다.
  final tail = trimmed.substring(start).trim();
  if (tail.isNotEmpty) sentences.add(tail);
  return sentences;
}

/// 모든 행에 똑같이 들어 있는 문장. 하나라도 빠진 문장은 공통이 아니다.
///
/// `reason`이 없는 행은 계산에서 **뺀다**. 태그가 아직 없어 근거가 비는 매장이 섞였을
/// 때 그 행 때문에 공통 집합이 비면, 겹치는 문장을 그대로 되풀이하게 된다.
///
/// **행이 하나뿐이면 공통은 없다.** 되풀이가 성립하려면 비교할 상대가 있어야 한다.
/// 이걸 빼먹으면 결과가 한 건인 목록에서 그 한 건의 문장이 전부 "공통"으로 잡혀 근거가
/// 통째로 사라진다.
Set<String> sharedReasonSentences(Iterable<String?> reasons) {
  final present = reasons
      .whereType<String>()
      .where((r) => r.trim().isNotEmpty)
      .toList();
  if (present.length < 2) return const {};
  Set<String>? shared;
  for (final reason in present) {
    final sentences = reasonSentences(reason).toSet();
    shared = shared == null ? sentences : shared.intersection(sentences);
    if (shared.isEmpty) break;
  }
  return shared ?? const {};
}

/// [reason]에서 [shared]를 뺀 나머지. 남는 게 없으면 null이다.
///
/// null은 "이 행에 적을 고유한 근거가 없다"는 뜻이고, 호출부는 그 자리에 층처럼 행마다
/// 다른 정보를 넣으면 된다.
String? distinctiveReason(String? reason, Set<String> shared) {
  if (reason == null || reason.trim().isEmpty) return null;
  final rest = reasonSentences(
    reason,
  ).where((sentence) => !shared.contains(sentence)).toList();
  if (rest.isEmpty) return null;
  return rest.join(' ');
}
