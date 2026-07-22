import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../models/favorite_place.dart';
import '../../models/floor_plan.dart';
import '../../models/poi_search_result.dart';
import '../../theme/app_theme.dart';
import '../../widgets/building_switcher_sheet.dart';
import '../../widgets/category_list_sheet.dart';
import '../../widgets/category_stores_sheet.dart';
import '../../widgets/directions_sheet.dart';
import '../../widgets/favorites_sheet.dart';
import '../../widgets/map_bottom_bar.dart';
import '../../widgets/map_top_bar.dart';
import '../../widgets/store_info_sheet.dart';
import '../indoor_map/indoor_map_screen.dart';
import '../outdoor_map/outdoor_map_screen.dart';

/// 야외/실내 지도의 공통 뼈대. 홈(야외) ↔ 실내 전환은 Navigator push 없이
/// 이 화면 안에서 모드만 바꿔 탭처럼 즉시 반응하게 한다. 검색·길찾기·건물
/// 전환·위치 보정은 전부 이 화면이 상단/하단 공용 바를 통해 중계한다.
class MapShellScreen extends StatefulWidget {
  const MapShellScreen({super.key, this.initialMode = MapMode.outdoor});

  final MapMode initialMode;

  @override
  State<MapShellScreen> createState() => _MapShellScreenState();
}

/// 경로가 표시되면 ETA 카드가 화면 최하단에 직접 도킹하므로, 하단 공용 바를
/// 그 위로 띄워야 하는 높이. EtaCard 실제 높이(패딩 포함)에 여유를 더한 값.
const _etaBarLiftHeight = 92.0;

class _MapShellScreenState extends State<MapShellScreen> {
  late MapMode _mode = widget.initialMode;
  String _buildingId = demoBuildingId;
  ({String title, String subtitle})? _placeInfo;
  bool _outdoorRouteVisible = false;
  bool _indoorRouteVisible = false;

  final _outdoorKey = GlobalKey<OutdoorMapBodyState>();
  final _indoorKey = GlobalKey<IndoorMapBodyState>();

  // 지도 위에 얹은 공용 오버레이(검색창·저장한 장소 pill·하단 홈/실내 바)의
  // 영역을 IndoorMapBody가 map click 처리에서 제외할 수 있게 넘겨줄 key들.
  // MapLibre PlatformView가 gesture arena를 우회해서 오버레이 탭이 뒤의 매장
  // 까지 새어들어가는 문제를 여기서 함께 막는다.
  final _topBarKey = GlobalKey();
  final _favoritesPillKey = GlobalKey();
  final _categoryPillKey = GlobalKey();
  final _bottomBarKey = GlobalKey();

  /// 시트 X 버튼이 눌리면 true가 된다. 시트 체인의 어떤 시점에서든 이 값이
  /// true면 부모 loop(_openFavorites, _openCategoryStores, _showStoreInfo)는
  /// 이전 시트를 다시 열지 않고 즉시 종료해서 전체 chain이 한 번에 닫힌다.
  /// 최상위 호출자가 값을 consume한 뒤 반드시 false로 되돌린다.
  bool _closeSheetChainRequested = false;

  void _requestCloseSheetChain() {
    _closeSheetChainRequested = true;
  }

  /// 시트 chain을 여는 최상위 진입 지점(장소 pill 탭, 매장 폴리곤 탭,
  /// 검색으로 매장 매치 등)에서 감싸 쓴다. 시작 시 플래그를 초기화하고
  /// 끝나면 다시 리셋한다 — nested loop들이 값을 읽는 동안에는 리셋하지
  /// 않으므로, X 신호가 chain 전체까지 온전히 전파된다.
  Future<T> _runSheetChain<T>(Future<T> Function() body) async {
    _closeSheetChainRequested = false;
    try {
      return await body();
    } finally {
      _closeSheetChainRequested = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _requestStartupPermissions();
  }

  /// 예전에는 스플래시 화면이 이 요청을 진행 중 화면과 함께 보여줬지만,
  /// 이제 앱이 바로 지도 화면으로 시작하므로 화면을 막지 않고 백그라운드로
  /// 요청만 하고, 거부된 게 있으면 지도 위에 짧게 안내만 띄운다.
  Future<void> _requestStartupPermissions() async {
    try {
      final statuses = await requestStartupPermissions();
      final anyDenied = statuses.values.any((status) => !status.isGranted);
      if (!mounted || !anyDenied) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('일부 권한이 거부되어 위치·실내 이동 관련 기능이 제한될 수 있습니다'),
        ),
      );
    } catch (_) {
      // 권한 플러그인을 쓸 수 없는 환경(테스트 등)에서도 앱을 계속 진행한다.
    }
  }

  void _setMode(MapMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _placeInfo = null;
    });
  }

  /// 바텀시트가 떠 있는 동안 지도 제스처를 꺼서, 시트를 마우스 휠로
  /// 스크롤할 때 그 아래 지도까지 같이 스크롤/줌되지 않게 한다. 실내 지도는
  /// 웹에서 실제 DOM 캔버스(MapLibre)라 시트 위에서도 휠 이벤트가 새어나갈
  /// 수 있어서 필요하다.
  Future<T?> _withMapsLocked<T>(Future<T?> Function() showSheet) async {
    _outdoorKey.currentState?.setInteractive(false);
    _indoorKey.currentState?.setInteractive(false);
    try {
      return await showSheet();
    } finally {
      _outdoorKey.currentState?.setInteractive(true);
      _indoorKey.currentState?.setInteractive(true);
    }
  }

  Future<void> _onSearch(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      setState(() => _placeInfo = null);
      return;
    }

    if (_mode == MapMode.outdoor) {
      final buildings = await buildingRepository.getAllBuildings();
      final match = buildings
          .where((b) => b.name.toLowerCase().contains(normalized.toLowerCase()))
          .firstOrNull;
      if (!mounted) return;
      setState(() {
        _placeInfo = match == null
            ? null
            : (title: match.name, subtitle: '${match.floors.length}개 층');
      });
      if (match == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('검색 결과가 없습니다')),
        );
      }
      return;
    }

    // 상단 일반 검색도 실내에서는 지금 보고 있는 층 안에서만 매칭한다 —
    // 화장실/엘리베이터/에스컬레이터처럼 층마다 같은 이름이 여러 개 있는
    // 시설을 다른 층으로 데려가지 않기 위해서. 아직 층이 로드되지 않은
    // 순간에는 현재 층을 알 수 없으므로 예전 전체 건물 검색으로 폴백한다.
    final results = await destinationRepository.searchDestinations(
      _buildingId,
      normalized,
      currentFloorId: _indoorKey.currentState?.currentFloor,
    );
    if (!mounted) return;
    final match = results.firstOrNull;
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('검색 결과가 없습니다')),
      );
      return;
    }

    await _runSheetChain(() => _showStoreInfo(match));
  }

  /// 매장 정보 시트를 띄운다. 검색 결과를 탭했을 때와 지도 위 매장 폴리곤을
  /// 직접 탭했을 때 모두 이 메서드를 거쳐 같은 시트가 뜨고, 출발지/도착지로
  /// 지정하면 그 매장을 채운 채로 길찾기 시트로 넘어간다.
  ///
  /// 반환값은 사용자가 출발/도착 액션을 실제로 골랐는지를 뜻한다. 저장된
  /// 장소 시트에서 넘어온 경우 호출자가 이 값을 보고 "그냥 닫힘"이면 다시
  /// 저장된 장소 시트로 돌려보내는 데 쓴다.
  Future<bool> _showStoreInfo(PoiSearchResult match) async {
    final favorite = FavoritePlace.fromPoiSearchResult(
      match,
      buildingId: _buildingId,
    );
    final action = await _withMapsLocked(
      () => StoreInfoSheet.show(
        context,
        title: match.name,
        subtitle: match.floor,
        favorite: favorite,
        category: match.category,
        subcategory: match.subcategory,
        onCloseAll: _requestCloseSheetChain,
      ),
    );
    if (!mounted) return false;
    // 시트가 어떻게 닫혔든(선택 없이 닫힘 포함) 지도 위 강조 표시도 같이 지운다.
    _indoorKey.currentState?.clearHighlight();
    // X로 chain 전체를 닫으라는 신호가 왔다면, 여기서 곧장 종료해 부모 loop가
    // 다음 시트를 다시 열지 못하게 한다.
    if (_closeSheetChainRequested) return true;
    if (action == null) return false;

    if (action == StoreInfoAction.viewCategory && match.category != null) {
      return _openCategoryStores(match.category!);
    }

    final candidate = DirectionsCandidate(
      title: match.name,
      subtitle: match.floor,
      point: match.point,
      nodeId: match.nodeId,
      floor: match.floor,
    );
    if (action == StoreInfoAction.setOrigin) {
      await _openDirections(presetOrigin: candidate);
    } else if (action == StoreInfoAction.setDestination) {
      await _openDirections(presetDestination: candidate);
    }
    return true;
  }

  /// 카테고리 chip을 눌렀을 때 같은 카테고리의 매장 목록 시트를 연다. 항목을
  /// 탭하면 그 매장의 매장 정보 시트로 넘어가고, 정보 시트에서 뒤로 돌아
  /// 오면(=출발/도착 액션 없이 닫힘) 다시 카테고리 목록으로 돌아온다 —
  /// 사용자가 여러 매장을 훑어보는 흐름을 위해 저장한 장소와 동일한 loop
  /// 패턴을 쓴다.
  Future<bool> _openCategoryStores(String category) async {
    while (mounted) {
      final picked = await _withMapsLocked(
        () => CategoryStoresSheet.show(
          context,
          buildingId: _buildingId,
          category: category,
          onCloseAll: _requestCloseSheetChain,
        ),
      );
      if (_closeSheetChainRequested || picked == null || !mounted) return false;
      final tookAction = await _showStoreInfo(picked);
      if (_closeSheetChainRequested || !mounted) return false;
      if (tookAction) return true;
    }
    return false;
  }

  Future<List<DirectionsCandidate>> _searchDirectionsCandidates(
    String query, {
    required bool includeAllFloors,
  }) async {
    final normalized = query.trim().toLowerCase();
    if (_mode == MapMode.outdoor) {
      final buildings = await buildingRepository.getAllBuildings();
      return buildings
          .where((b) => b.entrance != null)
          .where((b) => normalized.isEmpty || b.name.toLowerCase().contains(normalized))
          .map(
            (b) => DirectionsCandidate(
              title: b.name,
              subtitle: '${b.floors.length}개 층',
              point: b.entrance!,
            ),
          )
          .toList();
    }
    // 실내에서는 기본적으로 현재 층 안에서만 매장/시설을 찾는다 — 시트를
    // 통한 목적지 선택이 사용자 의도와 무관하게 다른 층으로 데려가지 않도록.
    // 사용자가 시트의 "전체 층에서 찾기" 토글을 켜면 그때만 예전처럼 건물
    // 전체를 뒤진다. 현재 층을 아직 알 수 없는 경우(층 미로드)에도 폴백으로
    // 전체 검색을 허용해 검색 자체가 조용히 죽는 상태를 만들지 않는다.
    final currentFloor = _indoorKey.currentState?.currentFloor;
    final results = await destinationRepository.searchDestinations(
      _buildingId,
      query,
      currentFloorId: includeAllFloors ? null : currentFloor,
    );
    return results
        .map(
          (r) => DirectionsCandidate(
            title: r.name,
            subtitle: r.floor,
            point: r.point,
            nodeId: r.nodeId,
            floor: r.floor,
          ),
        )
        .toList();
  }

  /// 길찾기 시트를 연다. [presetOrigin]/[presetDestination]은 매장 정보
  /// 시트의 "출발지로 설정"/"도착지로 설정"에서 넘어올 때 그 매장으로 채워
  /// 둘 값이다 — 상단 바 길찾기 아이콘으로 직접 열 때는 둘 다 비워 기존처럼
  /// 현재 위치 → 검색한 도착지 흐름을 그대로 쓴다. 시트 안에서 출발지를
  /// 직접 고르면(맨 위 "현재 위치" 포함) 그 선택이 [presetOrigin]보다 우선한다.
  Future<void> _openDirections({
    DirectionsCandidate? presetOrigin,
    DirectionsCandidate? presetDestination,
  }) async {
    // 실내 모드일 때만 현재 층 라벨을 시트에 넘겨 "B2에서 검색" 표시와
    // "전체 층에서 찾기" 토글이 뜨게 한다. 야외 모드는 층 개념 자체가
    // 없으므로 null을 넘겨 토글을 숨긴다.
    final currentFloorLabel = _mode == MapMode.indoor
        ? _indoorKey.currentState?.currentFloor
        : null;
    final result = await _withMapsLocked(
      () => DirectionsSheet.show(
        context,
        originLabel: '현재 위치',
        initialOrigin: presetOrigin,
        initialDestination: presetDestination,
        search: _searchDirectionsCandidates,
        currentFloorLabel: currentFloorLabel,
      ),
    );
    if (result == null || !mounted) return;

    final destination = result.destination;
    final origin = result.origin;

    if (_mode == MapMode.outdoor) {
      await _outdoorKey.currentState?.showRouteTo(
        destination.point,
        label: destination.title,
        origin: origin?.point,
      );
    } else {
      await _indoorKey.currentState?.showRouteTo(
        PoiSearchResult(
          name: destination.title,
          floor: destination.floor ?? '',
          point: destination.point,
          nodeId: destination.nodeId,
        ),
        origin: origin == null
            ? null
            : PoiSearchResult(
                name: origin.title,
                floor: origin.floor ?? '',
                point: origin.point,
                nodeId: origin.nodeId,
              ),
      );
    }
  }

  /// "장소" 칩을 누르면 사용자가 저장해둔 매장 목록 시트를 연다. 항목을
  /// 탭하면 지도에서 매장을 직접 눌렀을 때와 동일한 매장 정보 시트가 뜬다.
  ///
  /// 매장 정보 시트에서 출발/도착을 고르지 않고 뒤로 닫으면 다시 저장된 장소
  /// 시트로 돌아온다 — 사용자가 여러 저장 항목을 훑어보다 잘못 눌렀거나
  /// 다른 항목을 다시 고르려는 경우를 위한 흐름이다.
  /// "카테고리" pill을 눌렀을 때 대분류 목록 → 매장 목록 → 매장 정보로
  /// 이어지는 chain을 연다. 저장한 장소 흐름과 동일한 loop 패턴:
  /// - 매장 정보에서 뒤로 돌아오면 다시 매장 목록으로
  /// - 매장 목록에서 뒤로 돌아오면 다시 카테고리 목록으로
  /// - 어느 시트든 X/바깥 탭이면 전체 chain 종료
  Future<void> _openCategoryList() async {
    await _runSheetChain(() async {
      while (mounted) {
        final category = await _withMapsLocked(
          () => CategoryListSheet.show(
            context,
            buildingId: _buildingId,
            onCloseAll: _requestCloseSheetChain,
          ),
        );
        if (_closeSheetChainRequested || category == null || !mounted) return;
        final tookAction = await _openCategoryStores(category);
        if (_closeSheetChainRequested || !mounted) return;
        if (tookAction) return;
      }
    });
  }

  Future<void> _openFavorites() async {
    await _runSheetChain(() async {
      while (mounted) {
        final picked = await _withMapsLocked(
          () => FavoritesSheet.show(
            context,
            onCloseAll: _requestCloseSheetChain,
          ),
        );
        if (_closeSheetChainRequested || picked == null || !mounted) return;
        final enriched = await _favoriteWithCategory(picked);
        if (_closeSheetChainRequested || !mounted) return;
        final tookAction = await _showStoreInfo(enriched.toPoiSearchResult());
        if (_closeSheetChainRequested || !mounted) return;
        if (tookAction) return;
      }
    });
  }

  /// 저장된 항목에 카테고리 필드가 비어 있으면(이 필드가 도입되기 전에 저장
  /// 된 경우), 그 매장을 실시간 매장 데이터에서 찾아 category/subcategory를
  /// 채워 넣는다. 이렇게 해야 저장한 장소를 통해 열린 매장 정보 시트에서도
  /// 지도에서 직접 탭한 것과 똑같이 카테고리 chip이 뜬다.
  Future<FavoritePlace> _favoriteWithCategory(FavoritePlace favorite) async {
    if (favorite.category != null) return favorite;
    try {
      final json = await buildingRepository.getFloorGeoJson(
        favorite.buildingId,
        favorite.floor,
      );
      if (json == null) return favorite;
      final plan = FloorPlan.fromJson(json);
      final match = plan.stores.where((s) {
        if (favorite.nodeId != null) return s.entranceNodeId == favorite.nodeId;
        return s.name == favorite.name;
      }).firstOrNull;
      if (match == null || match.category == null) return favorite;
      return favorite.copyWithCategory(
        category: match.category,
        subcategory: match.subcategory,
      );
    } catch (_) {
      // enrich 실패는 표시 품질만 낮출 뿐 흐름을 막지 않는다.
      return favorite;
    }
  }

  Future<void> _onHamburgerTap() async {
    final selected = await _withMapsLocked(
      () => BuildingSwitcherSheet.show(context, selectedBuildingId: _buildingId),
    );
    if (selected == null || selected == _buildingId || !mounted) return;
    setState(() {
      _buildingId = selected;
      _placeInfo = null;
    });
  }

  void _onCalibrate() {
    if (_mode == MapMode.outdoor) {
      _outdoorKey.currentState?.recalibrate();
    } else {
      _indoorKey.currentState?.recalibrate();
    }
  }

  void _onEnterBuilding() => _setMode(MapMode.indoor);

  @override
  Widget build(BuildContext context) {
    final placeInfo = _placeInfo;
    final routeVisible = _mode == MapMode.outdoor ? _outdoorRouteVisible : _indoorRouteVisible;
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _mode == MapMode.outdoor ? 0 : 1,
            children: [
              OutdoorMapBody(
                key: _outdoorKey,
                onEnterBuilding: _onEnterBuilding,
                onRouteVisibleChanged: (visible) =>
                    setState(() => _outdoorRouteVisible = visible),
              ),
              IndoorMapBody(
                key: _indoorKey,
                buildingId: _buildingId,
                onRouteVisibleChanged: (visible) =>
                    setState(() => _indoorRouteVisible = visible),
                onStoreTap: (match) {
                  _runSheetChain(() => _showStoreInfo(match));
                },
                outerOverlayKeys: [
                  _topBarKey,
                  _favoritesPillKey,
                  _categoryPillKey,
                  _bottomBarKey,
                ],
              ),
            ],
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: MapTopBar(
              key: _topBarKey,
              showHamburger: _mode == MapMode.indoor,
              onHamburgerTap: _onHamburgerTap,
              onSearch: _onSearch,
              onDirectionsTap: _openDirections,
            ),
          ),

          Positioned(
            top: 78,
            left: 16,
            child: SafeArea(
              bottom: false,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FavoritesPill(key: _favoritesPillKey, onTap: _openFavorites),
                  // 카테고리 pill은 실내 지도에서만 노출한다. 야외 모드에서는
                  // "현재 건물"이 정의되지 않아 어떤 카테고리를 보여줄지 기준이
                  // 없으므로 아예 숨긴다.
                  if (_mode == MapMode.indoor) ...[
                    const SizedBox(width: 8),
                    _CategoryPill(
                      key: _categoryPillKey,
                      onTap: _openCategoryList,
                    ),
                  ],
                ],
              ),
            ),
          ),

          if (placeInfo != null)
            Positioned(
              top: 128,
              left: 12,
              right: 12,
              child: _PlaceInfoCard(
                title: placeInfo.title,
                subtitle: placeInfo.subtitle,
                onClose: () => setState(() => _placeInfo = null),
              ),
            ),

          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            bottom: routeVisible ? _etaBarLiftHeight : 0,
            child: MapBottomBar(
              key: _bottomBarKey,
              mode: _mode,
              onModeChanged: _setMode,
              onCalibrate: _onCalibrate,
            ),
          ),
        ],
      ),
    );
  }
}

/// 검색창 바로 아래에 뜨는 작은 "장소" 칩. 저장해둔 매장 리스트로 가는
/// 지름길이다. 검색과 시각적으로 분리되도록 흰 카드 톤을 유지한다.
class _FavoritesPill extends StatelessWidget {
  const _FavoritesPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmark_outline, size: 16, color: AppColors.primary),
              SizedBox(width: 6),
              Text(
                '장소',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 검색창 바로 아래에 뜨는 작은 "카테고리" 칩. 저장한 장소 pill과 시각적
/// 형제로 나란히 놓여, 매장 대분류(패션·뷰티 등)를 훑어 매장 목록으로 갈
/// 수 있는 지름길이다.
class _CategoryPill extends StatelessWidget {
  const _CategoryPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.category_outlined, size: 16, color: AppColors.primary),
              SizedBox(width: 6),
              Text(
                '카테고리',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceInfoCard extends StatelessWidget {
  const _PlaceInfoCard({required this.title, required this.subtitle, required this.onClose});

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
