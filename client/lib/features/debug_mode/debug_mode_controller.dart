import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 내비게이션 앱의 진단 기능을 한곳에서 관리하는 설정 컨트롤러.
///
/// 제품 UI는 [enabled]만 확인하면 PDR 진입점을 완전히 숨길 수 있고, 지도
/// 렌더러는 나머지 플래그만 받아서 각 진단 레이어를 독립적으로 켜고 끈다.
/// 설정은 앱 재실행 뒤에도 같은 테스트 구성을 이어갈 수 있도록 로컬에 저장한다.
class DebugModeController extends ChangeNotifier {
  factory DebugModeController({SharedPreferences? preferences}) =>
      DebugModeController._(preferences);

  DebugModeController._(this._preferences) {
    _loadFuture = _load();
  }

  static const _enabledKey = 'debug_mode.enabled';
  static const _showGraphNodesKey = 'debug_mode.show_graph_nodes';
  static const _showGraphNodeLabelsKey = 'debug_mode.show_graph_node_labels';
  static const _showGraphEdgesKey = 'debug_mode.show_graph_edges';
  static const _showGraphEdgeLabelsKey = 'debug_mode.show_graph_edge_labels';
  static const _showRawPdrPathKey = 'debug_mode.show_raw_pdr_path';
  static const _showConfirmedPdrPathKey = 'debug_mode.show_confirmed_pdr_path';
  static const _showMapMatchedPdrPathKey =
      'debug_mode.show_map_matched_pdr_path';

  SharedPreferences? _preferences;
  late final Future<void> _loadFuture;
  bool _disposed = false;
  bool _isLoaded = false;
  bool _enabled = false;
  bool _showGraphNodes = true;
  bool _showGraphNodeLabels = false;
  bool _showGraphEdges = true;
  bool _showGraphEdgeLabels = false;
  bool _showRawPdrPath = true;
  bool _showConfirmedPdrPath = true;
  bool _showMapMatchedPdrPath = true;

  bool get isLoaded => _isLoaded;
  Future<void> get ready => _loadFuture;
  bool get enabled => _enabled;
  bool get showGraphNodes => _showGraphNodes;
  bool get showGraphNodeLabels => _showGraphNodeLabels;
  bool get showGraphEdges => _showGraphEdges;
  bool get showGraphEdgeLabels => _showGraphEdgeLabels;
  bool get showRawPdrPath => _showRawPdrPath;
  bool get showConfirmedPdrPath => _showConfirmedPdrPath;
  bool get showMapMatchedPdrPath => _showMapMatchedPdrPath;

  Future<void> _load() async {
    try {
      _preferences ??= await SharedPreferences.getInstance();
      final preferences = _preferences!;
      _enabled = preferences.getBool(_enabledKey) ?? false;
      _showGraphNodes = preferences.getBool(_showGraphNodesKey) ?? true;
      _showGraphNodeLabels =
          preferences.getBool(_showGraphNodeLabelsKey) ?? false;
      _showGraphEdges = preferences.getBool(_showGraphEdgesKey) ?? true;
      _showGraphEdgeLabels =
          preferences.getBool(_showGraphEdgeLabelsKey) ?? false;
      _showRawPdrPath = preferences.getBool(_showRawPdrPathKey) ?? true;
      _showConfirmedPdrPath =
          preferences.getBool(_showConfirmedPdrPathKey) ?? true;
      _showMapMatchedPdrPath =
          preferences.getBool(_showMapMatchedPdrPathKey) ?? true;
    } on Object {
      // 플랫폼 저장소가 없는 테스트/개발 환경에서는 기본값으로 동작한다.
    } finally {
      _isLoaded = true;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> setEnabled(bool value) =>
      _setBool(_enabledKey, value, () => _enabled, (next) => _enabled = next);

  Future<void> setShowGraphNodes(bool value) => _setBool(
    _showGraphNodesKey,
    value,
    () => _showGraphNodes,
    (next) => _showGraphNodes = next,
  );

  Future<void> setShowGraphEdges(bool value) => _setBool(
    _showGraphEdgesKey,
    value,
    () => _showGraphEdges,
    (next) => _showGraphEdges = next,
  );

  Future<void> setShowGraphNodeLabels(bool value) => _setBool(
    _showGraphNodeLabelsKey,
    value,
    () => _showGraphNodeLabels,
    (next) => _showGraphNodeLabels = next,
  );

  Future<void> setShowGraphEdgeLabels(bool value) => _setBool(
    _showGraphEdgeLabelsKey,
    value,
    () => _showGraphEdgeLabels,
    (next) => _showGraphEdgeLabels = next,
  );

  Future<void> setShowRawPdrPath(bool value) => _setBool(
    _showRawPdrPathKey,
    value,
    () => _showRawPdrPath,
    (next) => _showRawPdrPath = next,
  );

  Future<void> setShowConfirmedPdrPath(bool value) => _setBool(
    _showConfirmedPdrPathKey,
    value,
    () => _showConfirmedPdrPath,
    (next) => _showConfirmedPdrPath = next,
  );

  Future<void> setShowMapMatchedPdrPath(bool value) => _setBool(
    _showMapMatchedPdrPathKey,
    value,
    () => _showMapMatchedPdrPath,
    (next) => _showMapMatchedPdrPath = next,
  );

  Future<void> _setBool(
    String key,
    bool value,
    bool Function() read,
    ValueChanged<bool> write,
  ) async {
    if (read() == value) return;
    write(value);
    if (!_disposed) notifyListeners();
    try {
      _preferences ??= await SharedPreferences.getInstance();
      await _preferences!.setBool(key, value);
    } on Object {
      // 영속화 실패가 지도/PDR 테스트 자체를 막아서는 안 된다. 현재 세션의
      // 설정은 유지하고 다음 실행에서 기본값으로 돌아가도록 둔다.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
