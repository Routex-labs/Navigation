import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/route/directions_candidate.dart';

/// 길찾기에서 실제로 쓴 출발지·목적지를 최신순으로 보관·영속화한다. 길찾기 두 칸의
/// 빈 화면을 채우는 저장소다.
///
/// **최근 검색어([RecentSearchesController])와 나눠 둔다** — "무엇을 찾았나"와
/// "어디서 어디로 갔나"는 다시 쓸 때의 의미가 다르다. 검색어는 글자라 다시 검색해야
/// 하지만, 이쪽은 노드·층까지 든 지점이라 누르면 바로 경로가 선다.
///
/// **개인정보: 서버로 보내지 않는다.** 어디를 오갔는지는 검색어보다 더 직접적으로
/// 사용자를 드러내는 값이다. 기기 로컬에만 남기고 어떤 요청에도 싣지 않는다.
///
/// **실패해도 조용히 degrade한다** — 부가 기능이라 빈 목록으로 동작한다.
class RecentRoutePointsController extends ChangeNotifier {
  // ignore: prefer_initializing_formals -- _prefs는 lazy-init으로 채워야 해서 mutable이어야 함.
  RecentRoutePointsController({SharedPreferences? prefs}) : _prefs = prefs {
    _loadFuture = _load();
  }

  /// 저장 포맷이 바뀌면 키에 붙은 버전을 올려 예전 값과 섞이지 않게 한다.
  static const _storageKey = 'recent_route_points_v1';

  /// 보관하는 최대 개수. 최근 검색어와 같은 10건이다 — 두 목록이 같은 자리를
  /// 두고 번갈아 뜨므로 길이가 다르면 화면 높이가 들쭉날쭉해진다.
  static const maxEntries = 10;

  SharedPreferences? _prefs;
  late final Future<void> _loadFuture;
  List<DirectionsCandidate> _points = const [];
  bool _loaded = false;
  bool _disposed = false;

  /// 최신순 목록. 첫 실행이거나 저장소가 실패하면 빈 목록이며, 이는 정상
  /// 상태다 — 호출부는 비어 있음을 오류로 다루지 않는다.
  List<DirectionsCandidate> get points => List.unmodifiable(_points);

  /// 최초 로드가 끝났는지. 로드 전의 빈 목록을 "저장된 게 없음"으로 오해하지
  /// 않으려면 이 값을 함께 본다.
  bool get isLoaded => _loaded;

  /// 최초 로드 완료를 기다리는 future. 테스트가 로드 시점을 고정할 때 쓴다.
  Future<void> get ready => _loadFuture;

  Future<void> _load() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        // 깨진 항목은 목록 전체를 버리지 말고 그것만 건너뛴다. 상한·중복 규칙도
        // 읽는 시점에 다시 맞춘다(수동 편집·구버전 잔재).
        _points = _capped(
          _dedupe(
            list
                .whereType<Map<String, dynamic>>()
                .map(DirectionsCandidate.fromJson)
                .whereType<DirectionsCandidate>(),
          ),
        );
      }
    } on Object {
      // 저장 포맷이 손상됐거나 플랫폼 저장소가 없는 환경(테스트 등)에서는
      // 조용히 빈 목록으로 시작한다. 길찾기 자체는 그대로 동작한다.
      _points = const [];
    } finally {
      _loaded = true;
      _notify();
    }
  }

  Future<void> _persist() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(
        _storageKey,
        jsonEncode([for (final p in _points) p.toJson()]),
      );
    } on Object {
      // 쓰기 실패가 길찾기를 막아서는 안 된다. 이번 세션의 목록은 메모리에
      // 유지하고, 다음 실행에서 저장된 값으로 돌아가도록 둔다.
    }
  }

  static List<DirectionsCandidate> _dedupe(
    Iterable<DirectionsCandidate> points,
  ) {
    final seen = <String>{};
    final result = <DirectionsCandidate>[];
    for (final point in points) {
      if (point.title.trim().isEmpty) continue;
      if (!seen.add(point.dedupeKey)) continue;
      result.add(point);
    }
    return result;
  }

  static List<DirectionsCandidate> _capped(List<DirectionsCandidate> points) =>
      points.length <= maxEntries ? points : points.sublist(0, maxEntries);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 지점 하나를 목록 맨 앞에 올린다.
  ///
  /// - 이름이 빈 후보는 저장하지 않는다(목록에 눌러도 뜻을 알 수 없는 줄이 된다).
  /// - 같은 지점을 다시 쓰면 중복으로 쌓지 않고 **맨 앞으로 옮긴다**.
  /// - [maxEntries]를 넘으면 가장 오래된 것부터 버린다.
  ///
  /// **로드가 끝났으면 기다리지 않는다.** 기다리는 이유는 뒤늦게 끝난 `_load`가
  /// 방금 넣은 항목을 덮어쓰는 것을 막기 위해서인데, 이미 끝났으면 막을 것이
  /// 없다. 완료된 future라도 `await`는 나머지를 microtask로 미루므로, 그대로
  /// 두면 부른 직후에 [points]를 읽는 호출부가 아직 없는 목록을 본다.
  Future<void> add(DirectionsCandidate point) async {
    if (!_loaded) await _loadFuture;
    if (point.title.trim().isEmpty) return;

    final key = point.dedupeKey;
    _points = _capped([
      point,
      ..._points.where((p) => p.dedupeKey != key),
    ]);
    _notify();
    await _persist();
  }

  /// 목록에서 한 건을 지운다.
  Future<void> remove(DirectionsCandidate point) async {
    if (!_loaded) await _loadFuture;
    final key = point.dedupeKey;
    final next = _points.where((p) => p.dedupeKey != key).toList();
    if (next.length == _points.length) return;
    _points = next;
    _notify();
    await _persist();
  }

  /// "전체 삭제". 이미 비어 있으면 아무것도 하지 않는다.
  Future<void> clear() async {
    if (!_loaded) await _loadFuture;
    if (_points.isEmpty) return;
    _points = const [];
    _notify();
    await _persist();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
