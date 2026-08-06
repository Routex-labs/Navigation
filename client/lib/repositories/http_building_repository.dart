import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import '../domain/floor_router.dart';
import '../models/building.dart';
import '../models/building_graph.dart';
import '../models/category_count.dart';
import '../models/floor_graph.dart';
import '../models/indoor_route.dart';
import 'building_repository.dart';

/// api/app/routers/buildings.py의 /buildings 엔드포인트를 그대로 호출한다.
///
/// 건물/층 데이터는 자주 안 바뀌므로 한 번 받아온 응답은 메모리에 캐싱해서
/// 같은 건물·같은 층을 다시 요청할 때 네트워크를 다시 타지 않는다.
///
/// ## 값이 아니라 **Future**를 캐시한다
///
/// 값을 캐시하면 `await`가 끝나야 캐시가 채워진다. 그 사이에 들어온 호출은
/// 전부 캐시 미스라 각자 네트워크를 탄다 — 이 앱은 야외 지도·실내 지도·
/// 카테고리 목록이 **같은 프레임에** 같은 건물·같은 층을 부르므로 그 창이
/// 항상 열린다. 실측(로컬 서버 접근 로그 645건)에서 `/floors/{층}`이 130건,
/// `/buildings/{id}`가 21건 나갔고 그중 상당수가 같은 초에 몰린 중복이었다.
///
/// 진행 중인 Future를 캐시에 넣어 두면 뒤따라온 호출이 그 하나를 함께 기다린다.
/// 요청 수가 "동시 호출자 수"가 아니라 "서로 다른 리소스 수"로 떨어진다.
class HttpBuildingRepository implements BuildingRepository {
  HttpBuildingRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<Building>>? _allBuildingsFuture;
  final Map<String, Future<Building?>> _buildingFutures = {};
  final Map<String, Future<Map<String, dynamic>?>> _floorGeoJsonFutures = {};
  final Map<String, Future<BuildingGraph?>> _buildingGraphFutures = {};
  final Map<String, Future<List<CategoryCount>?>> _categoryCountFutures = {};

  // 아래 둘은 네트워크가 아니라 계산 결과라 값 캐시로 충분하다.
  final Map<String, FloorGraph> _floorGraphCache = {};
  final Map<String, IndoorRoute> _routeCache = {};

  /// 진행 중인 요청을 공유한다. 같은 키로 다시 부르면 새 요청을 만들지 않고
  /// 이미 떠 있는 Future를 돌려준다.
  ///
  /// 캐시에 남기지 않는 두 경우가 있다.
  ///
  /// - **실패(예외).** 남기면 네트워크가 잠깐 끊긴 순간이 영구 실패로 굳어,
  ///   사용자가 재시도 버튼을 눌러도 같은 예외만 다시 받는다(야외 지도의 건물
  ///   로드 실패 배지가 정확히 그 재시도 경로다).
  /// - **404(=null).** 없는 건물·층을 영구히 "없음"으로 기억하면 나중에 생긴
  ///   데이터를 영영 못 찾는다. 기존 계약이고 테스트로 고정돼 있다.
  ///
  /// 둘 다 **Future가 끝난 뒤에** 지우므로, 동시에 들어온 호출을 하나로 합치는
  /// 효과는 그대로 남는다 — 이 함수의 목적은 결과를 오래 들고 있는 게 아니라
  /// 같은 순간에 같은 요청이 여러 번 나가는 것을 막는 것이다.
  Future<T> _shared<T>(
    Map<String, Future<T>> cache,
    String key,
    Future<T> Function() fetch,
  ) {
    final inflight = cache[key];
    if (inflight != null) return inflight;

    final future = fetch();
    cache[key] = future;
    // 결과를 삼키는 파생 Future로 감시만 한다. 여기서 다시 throw하면 아무도
    // 기다리지 않는 Future의 미처리 예외가 되므로 던지지 않는다 — 호출자에게는
    // 원본 future가 그대로 값·예외를 전달한다.
    unawaited(
      future.then(
        (value) {
          if (value == null) _evict(cache, key, future);
        },
        onError: (Object error, StackTrace stackTrace) {
          _evict(cache, key, future);
        },
      ),
    );
    return future;
  }

  /// 그 사이 같은 키로 새 요청이 시작됐으면 건드리지 않는다.
  void _evict<T>(Map<String, Future<T>> cache, String key, Future<T> future) {
    if (identical(cache[key], future)) cache.remove(key);
  }

  @override
  Future<List<Building>> getAllBuildings() {
    return _allBuildingsFuture ??= _fetchAllBuildings();
  }

  Future<List<Building>> _fetchAllBuildings() async {
    try {
      final response = await _client.get(Uri.parse('$apiBaseUrl/buildings'));
      final list = jsonDecode(response.body) as List<dynamic>;
      final buildings = list
          .map((item) => Building.fromJson(item as Map<String, dynamic>))
          .toList();

      // **목록 응답으로 개별 조회 캐시를 채우지 않는다.**
      //
      // 예전에는 "이미 받았으니 개별 조회는 네트워크를 타지 말자"고 채워 뒀는데,
      // 목록(`/buildings`)과 단건(`/buildings/{id}`)의 응답이 같지 않다. 목록에는
      // `tile_revision`이 없어서, 채워 두면 그 뒤 [getBuilding]이 **버전 없는**
      // Building을 돌려준다.
      //
      // 그러면 실내 타일 URL에 `?v=`가 안 붙고(`core/tile_url.dart`), 서버는
      // `immutable`(1년) 대신 `max-age=60`을 준다 — 실측으로 두 값을 모두 확인했다.
      // 그 결과 60초만 지나면 층을 바꿀 때마다 타일을 다시 받는다. 게다가 목록은
      // 검색할 때마다 불리므로(`search_panel.dart`), 검색 한 번이 그 뒤의 모든
      // 층 전환을 느리게 만들었다.
      //
      // 아낀 요청 한 번보다 타일 캐시가 훨씬 크다. 개별 조회는 `_shared`가 세션
      // 동안 한 번만 태우므로 실제 비용도 건물당 요청 1회다.
      return buildings;
    } catch (_) {
      _allBuildingsFuture = null; // 재시도 가능하게 (위 _shared와 같은 이유)
      rethrow;
    }
  }

  @override
  Future<Building?> getBuilding(String buildingId) {
    return _shared(_buildingFutures, buildingId, () async {
      final response = await _client.get(
        Uri.parse('$apiBaseUrl/buildings/$buildingId'),
      );
      if (response.statusCode == 404) return null;
      return Building.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    });
  }

  @override
  Future<List<CategoryCount>?> getCategoryCounts(String buildingId) {
    return _shared(_categoryCountFutures, buildingId, () async {
      final response = await _client.get(
        Uri.parse('$apiBaseUrl/buildings/$buildingId/categories'),
      );
      if (response.statusCode == 404) return null;
      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .map((item) => CategoryCount.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  @override
  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  ) {
    final cacheKey = '$buildingId/$floor';
    return _shared(_floorGeoJsonFutures, cacheKey, () async {
      final response = await _client.get(
        Uri.parse('$apiBaseUrl/buildings/$buildingId/floors/$floor'),
      );
      if (response.statusCode == 404) return null;

      final geojson = jsonDecode(response.body) as Map<String, dynamic>;
      final navigationGraph =
          geojson['navigation_graph'] as Map<String, dynamic>?;

      // /floors/{floor}는 매장 폴리곤이 없는(점 정보만 있는) 건물에서는 지도가
      // 텅 비어 보인다. 응답에 함께 내려오는 navigation_graph의 간선 geometry를
      // 복도선으로 얹어서 FloorPlan._fromApiResponse가 그대로 그릴 수 있게 한다.
      final corridors = _corridorsFromNavigationGraph(navigationGraph);
      if (corridors != null) geojson['corridors_local_m'] = corridors;

      // navigation_graph가 이 응답에 이미 포함돼 있으므로, 최단 경로 계산용
      // nodes/edges도 여기서 함께 캐싱해둔다 — getShortestRoute가 별도로
      // /floors/{floor}/graph를 다시 호출하지 않게 하기 위함이다.
      if (navigationGraph != null) {
        _floorGraphCache[cacheKey] = FloorGraph.fromJson(navigationGraph);
      }
      return geojson;
    });
  }

  List<List<dynamic>>? _corridorsFromNavigationGraph(
    Map<String, dynamic>? navigationGraph,
  ) {
    if (navigationGraph == null) return null;

    final edges = (navigationGraph['edges'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return edges
        .map((edge) => edge['geometry_local_m'] as List<dynamic>? ?? const [])
        .where((points) => points.length >= 2)
        .toList();
  }

  @override
  Future<IndoorRoute?> getShortestRoute(
    String buildingId,
    String floor,
    String startNodeId,
    String endNodeId,
  ) async {
    final cacheKey = '$buildingId/$floor/$startNodeId/$endNodeId';
    final cached = _routeCache[cacheKey];
    if (cached != null) return cached;

    // 다익스트라 입력(nodes+edges)은 별도 /graph 엔드포인트가 아니라
    // /floors/{floor} 응답의 navigation_graph에서만 얻는다. 아직 그 응답을
    // 받은 적이 없으면(캐시 미스) getFloorGeoJson이 한 번 받아와 채워준다 —
    // 이미 캐시돼 있으면 getFloorGeoJson 자체가 네트워크를 타지 않는다.
    final graphCacheKey = '$buildingId/$floor';
    var graph = _floorGraphCache[graphCacheKey];
    if (graph == null) {
      await getFloorGeoJson(buildingId, floor);
      graph = _floorGraphCache[graphCacheKey];
    }
    if (graph == null) return null;

    // 다익스트라는 그래프에 없는 노드 ID를 ArgumentError로 거부한다(백엔드가
    // 이 경우를 400으로 응답하던 것과 동일하게 "경로 없음"으로 단순화한다).
    IndoorRoute? route;
    try {
      route = computeShortestRoute(graph, startNodeId, endNodeId);
    } on ArgumentError {
      return null;
    }
    if (route == null) return null;

    _routeCache[cacheKey] = route;
    return route;
  }

  @override
  Future<BuildingGraph?> getBuildingGraph(
    String buildingId, {
    String vertical = 'auto',
  }) {
    return _shared(_buildingGraphFutures, '$buildingId/$vertical', () async {
      final response = await _client.get(
        Uri.parse('$apiBaseUrl/buildings/$buildingId/graph?vertical=$vertical'),
      );
      if (response.statusCode == 404) return null;
      return BuildingGraph.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    });
  }
}
