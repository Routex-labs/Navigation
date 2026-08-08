/// 입력 중인 검색어로 **온디바이스 매장 후보**를 만든다 — 자동완성(K)과 오타
/// 교정(L)이 한 함수다.
///
/// **왜 서버가 아니라 여기인가.** 실내 매장 집합은 고정이고 작다(더현대 서울
/// 기준 1640건). 타이핑마다 왕복하면 지연은 그대로 체감되는데 얻는 건 없다.
/// 네이버가 서버를 쓰는 건 전국 POI가 수천만 건이라서고, 우리 조건이 다르다.
///
/// **왜 교정이 자동완성과 한 함수인가.** 교정은 "정상 후보가 하나도 없을 때만"
/// 도는 규칙이라, 정상 후보를 아는 쪽에서만 판정할 수 있다. 두 함수로 쪼개면
/// 호출부가 그 순서를 다시 쓰게 되고, 거기서 뒤집히면 아무것도 안 깨진 채
/// 조용히 틀린다.
///
/// 설계 근거와 검증 기준은 `docs/client/search-input-assist.md` K·L절이 단일
/// 출처다.
library;

import '../models/store_index_entry.dart';
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
/// 3이다. `query.md`의 `"이"` → 이솝 케이스를 다시 깨뜨리지 않기 위한 하한이다
/// (Wave 4에서 이미 한 번 다친 곳).
///
/// **알려진 긴장 — 설계 문서의 대표 예시가 이 하한에 걸린다.**
/// `search-input-assist.md` L절이 드는 예시 `샤낼`은 2글자라, 이 값 아래에서는
/// 교정되지 않는다. 실측해 보면 2글자를 허용해도 교정 후보는 1~3건이라 문서가
/// 걱정한 "수십 건"은 나오지 않는데(전체 659개 상호 기준), 그건 아래 매칭이
/// **앞부분 정렬**([jamoPrefixEditDistance])이라 후보가 좁아서다. 그럼에도 3을
/// 유지하는 이유는 하한의 목적이 후보 수가 아니라 **`이`·`ㄱ` 같은 짧은 질의의
/// 정상 동작 보호**이기 때문이다. 뒤집으려면 이 값 하나만 바꾸면 되고, 회귀는
/// `store_suggestions_test.dart`의 짧은 질의 테스트가 잡는다.
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

/// 후보 한 건.
///
/// [stores]는 **같은 이름으로 묶인 매장 전부**다(화장실 19건 → 19개). 입력으로 받은
/// 원본 객체 그대로이고 인덱스 순서를 유지하며, 비어 있지 않다. 화면은 여기서
/// `name`·`floorName`·업종만 읽는다. 후보를 골랐을 때 좌표를 들고 바로 이동하지 않고
/// 그 이름으로 검색을 다시 돌리는 이유는 [StoreIndexEntry] 주석에 있다.
///
/// **대표 하나가 아니라 목록 전체를 넘긴다.** 예전에는 처음 나온 매장 하나와 개수
/// (`duplicateCount`)만 줬는데, 그러면 화면이 `화장실 · 6F 등 19곳`처럼 **인덱스
/// 순서상 첫 번째**의 층을 적게 된다. 인덱스는 `Floor.level DESC`라 그게 늘 꼭대기
/// 층이었다 — 사용자가 B2에 있어도 6F라고 적혔다. 어느 매장을 대표로 세울지는 거리를
/// 아는 쪽(화면)만 정할 수 있으므로, 여기서는 고르지 않고 그대로 넘긴다
/// ([nearestByWalkingDistance](nearest_store.dart), 설계:
/// `docs/client/search-result-list-ux.md` O절).
///
/// 묶인 개수는 `stores.length`다. 별도 필드로 두지 않는 이유는 두 값이 같은 사실을
/// 가리키기 때문이다 — 한쪽만 걸러지면 조용히 어긋난다.
typedef StoreSuggestion = ({List<StoreIndexEntry> stores, SuggestionKind kind});

/// [stores]에서 [query]에 맞는 후보를 우선순위 순으로 최대 [limit]건 고른다.
///
/// 순수 함수다. 입력 목록도, 그 안의 객체도 건드리지 않는다.
///
/// ## 우선순위
///
/// [SuggestionKind] 선언 순서 → (부분 일치면) 일치 시작 위치가 앞선 것 →
/// 이름이 짧은 것 → 입력 순서. 이름 길이를 넣는 이유는 `타임`을 쳤을 때
/// `타임`이 `타임파리`보다 위에 와야 하기 때문이다. 마지막 입력 순서 기준은
/// 장식이 아니다 — **Dart의 `List.sort`는 안정 정렬이 아니라서**, 동점을 명시적
/// 으로 깨 두지 않으면 같은 입력에 대해 호출할 때마다 순서가 달라질 수 있다.
///
/// ## 정규화 — 질의와 이름의 "매칭용 사본"에만 적용한다
///
/// 소문자로 낮추고 공백·구두점(`.`·`/`·괄호 등)을 **양쪽에서** 지운 사본으로만
/// 비교한다. 그래서 `A.P.C.`는 `apc`·`a.p.c` 어느 쪽으로 쳐도 걸리고,
/// `마리떼프랑소와저버/ LMC`도 `/`를 지운 채 찾힌다. **원본 이름은 그대로 두므로**
/// 화면에는 `A.P.C.`가 찍힌다 — `query.md` 4절과 같은 원칙이다.
///
/// 문서 K절은 "질의 쪽만 정규화"라고 적었는데, 그것만으로는 `apc`가 `A.P.C.`를
/// 못 찾는다. 지워지는 건 **표시에 쓰지 않는 매칭 키**뿐이라 원칙은 지켜진다.
///
/// ## 중복 이름
///
/// 화장실·엘리베이터는 층마다 있어 같은 이름이 12건씩 나온다. 정규화한 이름을
/// 키로 묶어 **한 줄로** 내보내되, 묶인 매장은 하나도 버리지 않고 `stores`에 전부
/// 담는다. 표기만 다른 같은 이름(`물품 보관함`·`물품보관함`)도 같이 묶인다.
///
/// **여기서 대표를 고르지 않는다.** 어느 매장의 층을 화면에 적을지는 거리를 아는
/// 쪽만 정할 수 있다([StoreSuggestion] 주석).
///
/// ## IME 조합 중
///
/// 갱신을 막지 않는다. 막으면 초성 검색이 아예 동작하지 않는다.
/// - 질의가 **전부 자음 낱자**면(`ㅅ`·`ㄴㅇㅋ`) 초성 매칭만 한다.
/// - 그 밖에는 자모열 접두사로 비교한다. 조합 중간 상태(`나이`+`ㅋ` → `나잌`)는
///   자모로 펴면 `ㄴㅏㅇㅣㅋ`이 되어 `나이키`(`ㄴㅏㅇㅣㅋㅣ`)의 접두사가 된다.
///   음절 단위로 비교했다면 `나잌`은 아무것도 못 찾는다.
///
/// **왜 자음 낱자 질의에서 자모 접두사 비교를 아예 끄나.** `ㄱ`의 자모열은
/// `ㄱ` 한 자라 `가니`(`ㄱㅏㄴㅣ`)의 접두사이기도 하다. 두 경로를 다 열면 같은
/// 결과가 `prefix`로도 `initials`로도 분류돼 "왜 후보인가"가 흔들리고, 게다가
/// 이름 가운데 아무 `ㄱ` 음절에나 붙어 부분 일치가 폭발한다.
///
/// ## 초성은 이름 앞에서부터만 맞춘다
///
/// `ㄹㅇㅈ`로 `나이키 라이즈`를 찾는 단어 경계 매칭은 넣지 않았다. 1글자 초성이
/// 단어마다 걸리면 상한 8건이 즉시 무의미해진다. 뒷단어는 `라이즈`처럼 글자로
/// 치면 부분 일치로 잡힌다.
List<StoreSuggestion> suggestStores({
  required Iterable<StoreIndexEntry> stores,
  required String query,
  int limit = maxStoreSuggestions,
}) {
  if (limit <= 0) return const [];
  final normalizedQuery = _matchKey(query);
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

/// 매칭에만 쓰는 사본. 소문자로 낮추고 글자·숫자·한글이 아닌 것을 전부 버린다.
///
/// 버리는 대상에 **공백이 포함된다.** `나이키 라이즈`를 `나이키라`로도 찾을 수
/// 있어야 해서다. 띄어쓰기는 사용자가 가장 자주 틀리는 지점인데, 그걸 오타
/// 교정에 떠넘기면 3글자 하한에 걸려 아예 못 잡는다.
String _matchKey(String text) {
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
    final key = _matchKey(store.name);
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
