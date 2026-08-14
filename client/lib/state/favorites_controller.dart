import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/place/favorite_place.dart';

/// 사용자가 "장소" 탭에 저장해둔 매장 목록을 보관·영속화한다.
///
/// SharedPreferences에 JSON 배열 문자열로 저장한다. 크기가 작고(수십 개
/// 규모) 자주 읽기만 하므로 별도 DB를 붙일 필요는 없다. ChangeNotifier로
/// 노출해서 사이드시트·정보 시트가 상태를 즉시 반영하게 한다.
class FavoritesController extends ChangeNotifier {
  // ignore: prefer_initializing_formals -- _prefs는 lazy-init으로 채워야 해서 mutable이어야 함.
  FavoritesController({SharedPreferences? prefs}) : _prefs = prefs {
    _load();
  }

  static const _storageKey = 'favorite_places_v1';

  SharedPreferences? _prefs;
  List<FavoritePlace> _places = const [];
  bool _loaded = false;

  List<FavoritePlace> get places => List.unmodifiable(_places);
  bool get isLoaded => _loaded;

  bool contains(String key) => _places.any((p) => p.key == key);

  Future<void> _load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _places = list
            .map((item) => FavoritePlace.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (_) {
        // 저장 포맷이 손상됐거나 이전 버전이면 조용히 초기화한다.
        _places = const [];
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = jsonEncode(_places.map((p) => p.toJson()).toList());
    await _prefs!.setString(_storageKey, raw);
  }

  /// 이미 저장돼 있으면 무시한다.
  Future<void> add(FavoritePlace place) async {
    if (contains(place.key)) return;
    _places = [..._places, place];
    notifyListeners();
    await _persist();
  }

  Future<void> removeByKey(String key) async {
    final next = _places.where((p) => p.key != key).toList();
    if (next.length == _places.length) return;
    _places = next;
    notifyListeners();
    await _persist();
  }

  /// UI에서 +/체크 아이콘을 누를 때 쓰는 편의 메서드. 저장 안 됐으면 저장,
  /// 이미 있으면 지운다. 결과가 "저장됨"이면 true를 반환한다.
  Future<bool> toggle(FavoritePlace place) async {
    if (contains(place.key)) {
      await removeByKey(place.key);
      return false;
    }
    await add(place);
    return true;
  }

  /// ReorderableListView에서 드래그로 순서를 바꿀 때 호출한다.
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _places.length) return;
    // ReorderableListView의 newIndex 규약: 뒤로 이동할 때는 원래 위치가 이미
    // 빠졌다고 가정하기 때문에 1을 빼줘야 한다.
    final adjustedNewIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final next = [..._places];
    final moved = next.removeAt(oldIndex);
    next.insert(adjustedNewIndex.clamp(0, next.length), moved);
    _places = next;
    notifyListeners();
    await _persist();
  }
}
