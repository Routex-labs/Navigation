/// 한글 표기를 **자모 단위**로 다루는 최소 유틸. 자동완성과 오타 교정이 같은 분해
/// 규칙 위에서 돌아야 해서 한 곳에 모았다.
///
/// **음절이 아니라 자모인 이유** — `샤낼`↔`샤넬`은 음절로 보면 완전히 다른
/// 코드포인트라 거리가 1음절 전체다. 라틴 문자·숫자는 그대로 통과시킨다.
///
/// 설계 근거와 검증 기준은 `docs/client/search-input-assist.md` K·L절.
library;

/// 완성형 한글 음절(`가`~`힣`)의 첫 코드포인트.
const int hangulSyllableFirst = 0xAC00;

/// 완성형 한글 음절의 마지막 코드포인트.
const int hangulSyllableLast = 0xD7A3;

/// 호환 자모 블록(`ㄱ`~`ㅣ`)의 범위. IME가 조합 중에 내보내는 낱자와, 사용자가
/// 초성 검색으로 직접 치는 낱자가 모두 이 블록이다.
const int _compatibilityJamoFirst = 0x3131;
const int _compatibilityJamoLast = 0x3163;

/// 호환 자모 중 **자음** 구간의 끝(`ㅎ`). 이 뒤부터는 모음(`ㅏ`~`ㅣ`)이다.
const int _compatibilityConsonantLast = 0x314E;

/// 초성 19자. 인덱스가 곧 음절 계산식의 초성 번호다.
const String _leadJamo = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';

/// 중성 21자.
const String _vowelJamo = 'ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ';

/// 종성 28자. **0번은 "받침 없음"** 이라 자리만 채워 두고 절대 쓰지 않는다.
const String _tailJamo = ' ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ';

/// 중성 개수. 음절 = 0xAC00 + (초성 × 21 + 중성) × 28 + 종성.
const int _vowelCount = 21;

/// 종성 개수(받침 없음 포함).
const int _tailCount = 28;

/// [codeUnit]이 완성형 한글 음절인가.
bool isHangulSyllable(int codeUnit) =>
    codeUnit >= hangulSyllableFirst && codeUnit <= hangulSyllableLast;

/// [codeUnit]이 호환 자모(낱자)인가. 자음·모음을 모두 포함한다.
bool isCompatibilityJamo(int codeUnit) =>
    codeUnit >= _compatibilityJamoFirst && codeUnit <= _compatibilityJamoLast;

/// [codeUnit]이 호환 자모 **자음**(`ㄱ`~`ㅎ`)인가.
///
/// 초성 검색 판정에 쓴다 — 질의가 전부 이것이면 사용자가 초성을 친 것이다.
bool isConsonantJamo(int codeUnit) =>
    codeUnit >= _compatibilityJamoFirst &&
    codeUnit <= _compatibilityConsonantLast;

/// [text]의 한글 음절을 초·중·종성으로 펴서 이어 붙인다.
/// `'샤넬'` → `'ㅅㅑㄴㅔㄹ'`, `'나'` → `'ㄴㅏ'`, `'A.P.C'` → 그대로.
///
/// **겹자모(`ㅘ`·`ㄺ`)는 더 쪼개지 않는다** — `과`↔`고`는 쪼개도 안 쪼개도 거리가
/// 1이라 표를 하나 더 유지할 이유가 없다.
String decomposeJamo(String text) {
  final buffer = StringBuffer();
  for (final unit in text.codeUnits) {
    if (!isHangulSyllable(unit)) {
      buffer.writeCharCode(unit);
      continue;
    }
    final index = unit - hangulSyllableFirst;
    buffer.write(_leadJamo[index ~/ (_vowelCount * _tailCount)]);
    buffer.write(_vowelJamo[(index ~/ _tailCount) % _vowelCount]);
    final tail = index % _tailCount;
    if (tail != 0) buffer.write(_tailJamo[tail]);
  }
  return buffer.toString();
}

/// [text]의 초성만 뽑는다. `'나이키'` → `'ㄴㅇㅋ'`, `'mlb'` → 그대로.
///
/// 한글이 아닌 문자를 **버리지 않는** 이유는 `코닥x디오디` 같은 혼합 상호다 —
/// 빼면 초성열 자리수가 어긋나 `ㅋㄷㅇㄷ`로만 찾히는 설명할 수 없는 동작이 된다.
String initialConsonants(String text) {
  final buffer = StringBuffer();
  for (final unit in text.codeUnits) {
    if (!isHangulSyllable(unit)) {
      buffer.writeCharCode(unit);
      continue;
    }
    final index = unit - hangulSyllableFirst;
    buffer.write(_leadJamo[index ~/ (_vowelCount * _tailCount)]);
  }
  return buffer.toString();
}

/// [a]와 [b]를 자모로 편 뒤 잰 레벤슈타인 편집거리. **통째로 같은지**를 물을 때
/// 쓴다 — 상호가 질의보다 길기만 해도 거리가 폭발하므로(`샤낼`↔`샤넬 뷰티`는 6),
/// 앞부분 비교는 [jamoPrefixEditDistance]를 쓴다.
int jamoEditDistance(String a, String b) => _distance(a, b, freeTail: false);

/// [query]가 [text]의 **앞부분**과 얼마나 다른지. 뒤쪽은 공짜다
/// (`'샤낼'`↔`'샤넬 뷰티'` = 1).
///
/// 시작 지점까지 풀면 3글자 질의가 긴 상호 아무 데나 거리 1로 붙는다. 교정이
/// 다루는 상황은 "처음부터 잘못 쳤다"이지 "가운데 어딘가와 비슷하다"가 아니다.
int jamoPrefixEditDistance(String query, String text) =>
    _distance(query, text, freeTail: true);

/// 자모 단위 편집거리 DP. [freeTail]이면 `b`의 남은 꼬리를 버리는 비용을 받지
/// 않는다(마지막 행의 최솟값 = 모든 접두사에 대한 거리 중 최솟값).
///
/// 행을 두 개만 굴린다. 상호는 길어야 수십 자라 전체 표를 잡을 이유가 없다.
int _distance(String a, String b, {required bool freeTail}) {
  final source = decomposeJamo(a);
  final target = decomposeJamo(b);
  // previous[j] = source의 i-1글자와 target의 j글자 사이 거리.
  // 0행은 "빈 질의를 target의 j글자로 만드는 비용" = j다.
  var previous = List<int>.generate(target.length + 1, (j) => j);
  var current = List<int>.filled(target.length + 1, 0);

  for (var i = 1; i <= source.length; i++) {
    current[0] = i;
    for (var j = 1; j <= target.length; j++) {
      final substitution =
          previous[j - 1] +
          (source.codeUnitAt(i - 1) == target.codeUnitAt(j - 1) ? 0 : 1);
      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      var best = substitution;
      if (deletion < best) best = deletion;
      if (insertion < best) best = insertion;
      current[j] = best;
    }
    final swap = previous;
    previous = current;
    current = swap;
  }

  // source가 비면 위 반복이 한 번도 안 돌아 previous는 0행 그대로다. 그때
  // freeTail이면 0(빈 접두사와 일치), 아니면 target 길이 — 둘 다 옳다.
  if (!freeTail) return previous[target.length];
  var best = previous[0];
  for (final value in previous) {
    if (value < best) best = value;
  }
  return best;
}
