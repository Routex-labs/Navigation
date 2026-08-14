import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 검색창에 입력했던 검색어를 최신순으로 보관·영속화한다. 검색 패널의 idle 화면을
/// 채우는 저장소이고, 근거는 `docs/client/naver-map-ui-ux-analysis.md` J절.
///
/// **개인정보: 서버로 보내지 않는다.** 검색어는 무엇을 찾는지 그대로 드러내는
/// 값이고, `conversational-discovery.md`의 비목표가 계정 단위 영구 저장을 금한다 —
/// 기기 로컬에만 남기고 어떤 요청에도 싣지 않는다. 올려야 할 이유가 생기면 이
/// 주석이 아니라 그 문서의 비목표를 먼저 고친다.
///
/// **실패해도 조용히 degrade한다** — 부가 기능이라 빈 목록으로 동작하고, 첫 실행의
/// 빈 값도 정상 상태다.
class RecentSearchesController extends ChangeNotifier {
  // ignore: prefer_initializing_formals -- _prefs는 lazy-init으로 채워야 해서 mutable이어야 함.
  RecentSearchesController({SharedPreferences? prefs}) : _prefs = prefs {
    _loadFuture = _load();
  }

  /// 저장 포맷이 바뀌면 키에 붙은 버전을 올려 예전 값과 섞이지 않게 한다.
  static const _storageKey = 'recent_searches_v1';

  /// 보관하는 최근 검색어 최대 개수.
  ///
  /// 10개인 이유: (1) idle 패널은 검색 결과가 들어설 자리라 스크롤 없이 보여줄
  /// 수 있는 분량이 이 정도이고, (2) 검색어는 오래될수록 다시 쓸 확률이 급격히
  /// 떨어져 그 이상 쌓아 봐야 목록만 길어진다. 상한을 넘으면 가장 오래된
  /// 것부터 버린다 — 지울 대상을 사용자에게 묻는 편이 더 성가시다.
  static const maxEntries = 10;

  /// 검색어 한 건의 길이 상한(자).
  ///
  /// 검색창에 붙여넣기 사고 등으로 비정상적으로 긴 문자열이 들어오면 저장소가
  /// 부풀고 목록 렌더링도 깨진다. 자연어 질의("3층에 있는 카페 알려줘")도 이
  /// 길이를 넘지 않으므로, 넘는 입력은 빈 문자열과 같이 **저장하지 않는다**
  /// (잘라서 저장하면 탭했을 때 원래와 다른 검색이 실행된다).
  static const maxQueryLength = 100;

  SharedPreferences? _prefs;
  late final Future<void> _loadFuture;
  List<String> _queries = const [];
  bool _loaded = false;
  bool _disposed = false;

  /// 최신순 목록. 첫 실행이거나 저장소가 실패하면 빈 목록이며, 이는 정상
  /// 상태다 — 호출부는 비어 있음을 오류로 다루지 않는다.
  List<String> get queries => List.unmodifiable(_queries);

  /// 최초 로드가 끝났는지. 로드 전의 빈 목록을 "저장된 게 없음"으로 오해하지
  /// 않으려면 이 값을 함께 본다.
  bool get isLoaded => _loaded;

  /// 최초 로드 완료를 기다리는 future. 테스트가 로드 시점을 고정할 때 쓴다.
  Future<void> get ready => _loadFuture;

  /// 중복 판정용 정규화. 앞뒤 공백을 버리고, 사이 공백을 하나로 접고,
  /// 대소문자를 무시한다. "ZARA"와 "zara ", "스타 벅스"와 "스타  벅스"를 같은
  /// 검색어로 보기 위한 것이며, **저장되는 값은 정규화 전 원문**이다(사용자가
  /// 입력한 그대로 다시 검색되어야 한다).
  static String _normalize(String query) =>
      query.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  Future<void> _load() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        // 문자열이 아닌 항목(손상·구버전)은 목록 전체를 버리지 말고 그것만
        // 건너뛴다. 저장된 값이 상한·중복 규칙을 어기고 있어도(수동 편집,
        // 구버전 잔재) 읽는 시점에 같은 규칙으로 다시 맞춘다.
        _queries = _capped(
          _dedupe(list.whereType<String>().map((q) => q.trim())),
        );
      }
    } on Object {
      // 저장 포맷이 손상됐거나 플랫폼 저장소가 없는 환경(테스트 등)에서는
      // 조용히 빈 목록으로 시작한다. 검색 기능 자체는 그대로 동작한다.
      _queries = const [];
    } finally {
      _loaded = true;
      _notify();
    }
  }

  Future<void> _persist() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_storageKey, jsonEncode(_queries));
    } on Object {
      // 쓰기 실패가 검색을 막아서는 안 된다. 이번 세션의 목록은 메모리에
      // 유지하고, 다음 실행에서 저장된 값으로 돌아가도록 둔다.
    }
  }

  static bool _isStorable(String query) {
    final trimmed = query.trim();
    return trimmed.isNotEmpty && trimmed.length <= maxQueryLength;
  }

  /// 저장 불가능한 값을 걸러내고 정규화 기준 중복을 앞선 것만 남긴다.
  static List<String> _dedupe(Iterable<String> queries) {
    final seen = <String>{};
    final result = <String>[];
    for (final query in queries) {
      if (!_isStorable(query)) continue;
      if (!seen.add(_normalize(query))) continue;
      result.add(query);
    }
    return result;
  }

  /// 상한을 넘으면 오래된 뒤쪽부터 버린다.
  static List<String> _capped(List<String> queries) =>
      queries.length <= maxEntries ? queries : queries.sublist(0, maxEntries);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 검색어를 목록 맨 앞에 올린다.
  ///
  /// - 공백뿐이거나 빈 문자열, [maxQueryLength]를 넘는 입력은 저장하지 않는다.
  /// - 이미 있던 검색어를 다시 검색하면 중복으로 쌓지 않고 **맨 앞으로 옮긴다**.
  /// - [maxEntries]를 넘으면 가장 오래된 것부터 버린다.
  Future<void> add(String query) async {
    // 로드가 끝나기 전에 추가하면 뒤늦게 끝난 _load가 방금 넣은 항목을 덮어쓴다.
    await _loadFuture;
    final trimmed = query.trim();
    if (!_isStorable(trimmed)) return;

    final key = _normalize(trimmed);
    final next = [trimmed, ..._queries.where((q) => _normalize(q) != key)];
    _queries = _capped(next);
    _notify();
    await _persist();
  }

  /// 목록에서 검색어 한 건을 지운다. 대소문자·공백 차이는 무시하고 찾는다.
  Future<void> remove(String query) async {
    await _loadFuture;
    final key = _normalize(query);
    final next = _queries.where((q) => _normalize(q) != key).toList();
    if (next.length == _queries.length) return;
    _queries = next;
    _notify();
    await _persist();
  }

  /// "전체 삭제". 이미 비어 있으면 아무것도 하지 않는다.
  Future<void> clear() async {
    await _loadFuture;
    if (_queries.isEmpty) return;
    _queries = const [];
    _notify();
    await _persist();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
