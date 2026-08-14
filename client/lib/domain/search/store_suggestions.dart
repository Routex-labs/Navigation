/// 입력 중인 검색어로 **온디바이스 매장 후보**를 만든다 — 자동완성(K)과 오타
/// 교정(L)이 한 함수다. 교정은 "정상 후보가 없을 때만" 도는 규칙이라 정상 후보를
/// 아는 쪽에서만 판정할 수 있고, 쪼개면 호출부가 그 순서를 다시 쓰게 된다.
///
/// 설계 근거와 검증 기준은 `docs/client/search-input-assist.md` K·L절.
library;

import '../../models/store_index_entry.dart';
import 'hangul.dart';

/// 후보 개수 상한.
///
/// `ㄱ` 한 글자면 수백 건이 걸린다. 상한이 없으면 패널이 폭발한다. 8은
/// `search-input-assist.md`「미결정 — 기본 제안」의 값으로, 접힌 시트에서 스크롤
/// 없이 훑을 수 있는 줄 수다.
const int maxStoreSuggestions = 8;

/// 후보를 만들기 시작하는 최소 입력 길이(정규화 후 글자 수).
///
/// 1이다 — 초성 한 글자(`ㄱ`)부터 받아야 초성 검색이 의미가 있다. 상한
/// [maxStoreSuggestions]가 폭발을 막으므로 하한을 올릴 이유가 없다.
const int minSuggestionQueryLength = 1;

/// 오타 교정으로 인정하는 자모 편집거리 상한.
///
/// 1이다. 2까지 열면 `크록스`↔`크록시`처럼 **둘 다 실재할 수 있는** 이름이
/// 서로를 부르기 시작한다. 넓히려면 측정 결과를 근거로 올린다.
const int maxCorrectionJamoDistance = 1;

/// 오타 교정을 시도하는 최소 질의 길이(정규화 후 글자 수).
///
/// 목적은 후보 수가 아니라 **`이`·`ㄱ` 같은 짧은 질의의 정상 동작 보호**다
/// (`query.md`의 `이` → 이솝). 그래서 L절 예시 `샤낼`(2글자)은 교정되지 않는다 —
/// 알고 둔 긴장이며, 뒤집으려면 이 값 하나만 바꾼다.
const int minCorrectionQueryLength = 3;

/// 이 후보가 **왜** 후보인가. 선언 순서가 곧 표시 우선순위다.
///
/// 화면이 이 값을 읽어야 하는 이유는 [correction] 때문이다 — 사용자가
/// "내가 오타를 냈구나"를 알 수 있어야 한다는 게 L절의 검증 기준이라, 교정
/// 후보를 정상 후보와 같은 모양으로 그리면 안 된다.
enum SuggestionKind {
  /// 이름이 질의로 시작한다. `나이` → 나이키 라이즈.
  prefix,

  /// 초성이 질의로 시작한다. `ㄴㅇㅋ` → 나이키 라이즈.
  initials,

  /// 이름 가운데에 질의가 들어 있다. `라이즈` → 나이키 라이즈.
  partial,

  /// 오타 교정 후보. 위 셋이 **하나도 없을 때만** 만들어진다.
  correction;

  /// 화면이 "혹시 이걸 찾으셨나요" 꼴로 따로 표시해야 하는 후보인가.
  bool get isCorrection => this == SuggestionKind.correction;
}

/// 후보 한 건. [stores]는 **같은 이름으로 묶인 매장 전부**다(화장실 19건 → 19개).
/// 원본 객체 그대로이고 인덱스 순서를 유지하며, 비어 있지 않다.
///
/// **대표 하나가 아니라 목록 전체를 넘긴다** — 어느 매장을 세울지는 거리를 아는
/// 쪽(화면)만 정할 수 있다([nearestByWalkingDistance], search-result-list-ux.md O절).
/// 묶인 개수는 `stores.length`다(별도 필드를 두면 한쪽만 걸러져 어긋난다).
typedef StoreSuggestion = ({List<StoreIndexEntry> stores, SuggestionKind kind});

/// [stores]에서 [query]에 맞는 후보를 우선순위 순으로 최대 [limit]건 고른다.
/// 순수 함수이고, 정규화는 **매칭용 사본에만** 적용해 원본 이름은 그대로 남는다.
///
/// 우선순위·정규화 범위·IME 조합 처리의 근거는 search-input-assist.md K절.
List<StoreSuggestion> suggestStores({
  required Iterable<StoreIndexEntry> stores,
  required String query,
  int limit = maxStoreSuggestions,
}) {
  if (limit <= 0) return const [];
  final normalizedQuery = storeMatchKey(query);
  if (normalizedQuery.length < minSuggestionQueryLength) return const [];

  final entries = _indexByName(stores);
  if (entries.isEmpty) return const [];

  final queryJamo = decomposeJamo(normalizedQuery);
  // 전부 자음 낱자면 사용자가 초성을 친 것이다. 빈 문자열은 위에서 걸러졌다.
  final isInitialsQuery = normalizedQuery.codeUnits.every(isConsonantJamo);

  final ranked = <_Ranked>[];
  for (final entry in entries) {
    if (isInitialsQuery) {
      if (entry.initials.startsWith(normalizedQuery)) {
        ranked.add(_Ranked(entry, SuggestionKind.initials, 0));
      }
      continue;
    }
    final offset = entry.jamoPrefixOffset(queryJamo);
    if (offset == 0) {
      ranked.add(_Ranked(entry, SuggestionKind.prefix, 0));
    } else if (offset > 0) {
      ranked.add(_Ranked(entry, SuggestionKind.partial, offset));
    }
  }

  // 정상 후보가 하나라도 있으면 교정은 시도조차 하지 않는다. 지금 잘 되던
  // 검색이 교정 때문에 다른 매장으로 바뀌면 순손실이다(L절 「정상 질의 회귀」).
  // 이 자리라서 순서를 뒤집을 여지도 없다 — 교정 후보는 애초에 만들어지지
  // 않거나, 만들어지면 목록 전체가 교정 후보다.
  if (ranked.isEmpty &&
      !isInitialsQuery &&
      normalizedQuery.length >= minCorrectionQueryLength) {
    for (final entry in entries) {
      // 상호가 질의보다 임계 이상 짧으면 지우는 비용만으로 이미 초과다.
      if (entry.jamo.length + maxCorrectionJamoDistance < queryJamo.length) {
        continue;
      }
      final distance = jamoPrefixEditDistance(normalizedQuery, entry.key);
      if (distance <= maxCorrectionJamoDistance) {
        ranked.add(_Ranked(entry, SuggestionKind.correction, distance));
      }
    }
  }

  ranked.sort(_compare);
  return [
    for (final item in ranked.take(limit))
      (stores: item.entry.stores, kind: item.kind),
  ];
}

int _compare(_Ranked a, _Ranked b) {
  final byKind = a.kind.index.compareTo(b.kind.index);
  if (byKind != 0) return byKind;
  final byTiebreak = a.tiebreak.compareTo(b.tiebreak);
  if (byTiebreak != 0) return byTiebreak;
  final byLength = a.entry.key.length.compareTo(b.entry.key.length);
  if (byLength != 0) return byLength;
  return a.entry.order.compareTo(b.entry.order);
}

/// 매칭에만 쓰는 사본. 소문자로 낮추고 글자·숫자·한글이 아닌 것을 버린다.
///
/// **공백도 버린다** — `나이키 라이즈`를 `나이키라`로도 찾아야 하고, 띄어쓰기를
/// 오타 교정에 떠넘기면 3글자 하한에 걸려 못 잡는다.
/// 공개한 이유는 [nameSiblings]가 같은 잣대를 써야 해서다(규칙은 여기 하나만).
String storeMatchKey(String text) {
  final buffer = StringBuffer();
  for (final unit in text.toLowerCase().codeUnits) {
    final isDigit = unit >= 0x30 && unit <= 0x39;
    final isLatin = unit >= 0x61 && unit <= 0x7A;
    if (isDigit ||
        isLatin ||
        isCompatibilityJamo(unit) ||
        isHangulSyllable(unit)) {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

/// 이름으로 묶은 색인을 입력 순서대로 만든다.
///
/// 매 호출마다 다시 만든다. 1640건 × 짧은 문자열 몇 개라 키 입력 주기에 견디고,
/// 대신 함수가 상태를 갖지 않아 테스트가 쉽다. 프로파일링으로 문제가 확인되면
/// 그때 호출부가 색인을 들고 있도록 바꾼다 — 측정 없이 먼저 캐시하지 않는다.
List<_NameEntry> _indexByName(Iterable<StoreIndexEntry> stores) {
  final byKey = <String, _NameEntry>{};
  for (final store in stores) {
    final key = storeMatchKey(store.name);
    // 정규화하면 아무것도 안 남는 이름(구두점뿐)은 어떤 질의로도 못 찾는다.
    // 남겨 두면 빈 키 하나로 서로 다른 매장이 뭉친다.
    if (key.isEmpty) continue;
    final existing = byKey[key];
    if (existing != null) {
      // 개수만 세지 않고 매장 자체를 모아 둔다. 화면이 그중 가장 가까운 곳을
      // 대표로 세워야 하기 때문이다([StoreSuggestion] 주석).
      existing.stores.add(store);
      continue;
    }
    byKey[key] = _NameEntry(store, key, byKey.length);
  }
  // Dart의 Map은 삽입 순서를 유지한다 — order 필드와 같은 순서다.
  return byKey.values.toList(growable: false);
}

/// 이름 하나에 대한 매칭용 파생값 묶음.
class _NameEntry {
  _NameEntry(StoreIndexEntry first, this.key, this.order)
    : stores = [first],
      jamo = decomposeJamo(key),
      initials = initialConsonants(key),
      _jamoStarts = _jamoStartsOf(key);

  /// 이 이름으로 묶인 매장 전부. 인덱스 순서이고 비어 있지 않다.
  final List<StoreIndexEntry> stores;

  /// 정규화한 이름. 표시에는 쓰지 않는다.
  final String key;

  /// 입력 순서. 동점 정렬을 결정적으로 만드는 데만 쓴다.
  final int order;

  final String jamo;
  final String initials;

  /// `key`의 각 글자가 `jamo`의 몇 번째에서 시작하는지.
  final List<int> _jamoStarts;

  /// [queryJamo]가 이름의 몇 번째 **글자**에서부터 일치하는지. 없으면 -1.
  ///
  /// 자모열 안 아무 데서나 찾지 않고 **글자 경계에서만** 시작을 허용한다.
  /// 그러지 않으면 `ㅣㅋ`가 `나이키` 가운데에 걸리는 식으로, 사용자가 칠 수
  /// 없는 조각이 일치로 잡힌다.
  int jamoPrefixOffset(String queryJamo) {
    for (var index = 0; index < _jamoStarts.length; index++) {
      if (jamo.startsWith(queryJamo, _jamoStarts[index])) return index;
    }
    return -1;
  }

  static List<int> _jamoStartsOf(String key) {
    final starts = <int>[];
    var offset = 0;
    for (final unit in key.codeUnits) {
      starts.add(offset);
      offset += decomposeJamo(String.fromCharCode(unit)).length;
    }
    return starts;
  }
}

/// 정렬 전 후보. [tiebreak]는 종류마다 뜻이 다르다 — 부분 일치면 일치 시작
/// 위치, 교정이면 편집거리다. 종류가 같을 때만 비교하므로 섞이지 않는다.
class _Ranked {
  _Ranked(this.entry, this.kind, this.tiebreak);

  final _NameEntry entry;
  final SuggestionKind kind;
  final int tiebreak;
}
