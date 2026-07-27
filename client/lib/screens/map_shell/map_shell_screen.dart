import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../models/building.dart';
import '../../models/favorite_place.dart';
import '../../models/floor_plan.dart';
import '../../models/poi_search_result.dart';
import '../../theme/app_theme.dart';
import '../../widgets/building_switcher_sheet.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/category_stores_sheet.dart';
import '../../widgets/directions_sheet.dart';
import '../../widgets/favorites_sheet.dart';
import '../../widgets/map_bottom_bar.dart';
import '../../widgets/map_top_bar.dart';
import '../../widgets/search_panel.dart';
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

  /// 실내 지도에서 "위치 지정" 흐름이 켜져 있는지. IndoorMapBody가 콜백으로
  /// 알려주며, 하단 바 "위치 지정" 버튼을 눌린 상태로 표시하는 데 쓴다.
  bool _indoorPlacingLocation = false;

  /// 야외 지도의 실내 진입 오버레이에서 "위치 지정" 흐름이 켜져 있는지.
  /// OutdoorMapBody가 콜백으로 알려주며, 실내와 동일하게 하단 바 버튼을 눌린
  /// 상태로 표시하는 데 쓴다.
  bool _outdoorPlacingLocation = false;

  /// 야외 지도의 실내 진입 오버레이가 지금 켜져 있는지. OutdoorMapBody가
  /// 건물 탭·줌 임계값 초과·GPS 근접 감지로 오버레이를 켤 때 이 값이 true가
  /// 되고, 하단 바의 "위치 지정" 버튼을 그때만 노출한다.
  bool _outdoorIndoorEntered = false;

  /// 사용자가 명시적으로 고른 출발지(매장 정보 시트 "출발지로 설정" 또는
  /// 길찾기 시트 안에서 특정 매장을 골랐을 때). 이 값이 채워져 있으면 이후
  /// 매장에서 "도착"을 누를 때 길찾기 시트를 다시 열지 않고 바로 이 출발지
  /// 기준으로 경로를 그린다. null이면 "현재 위치"(=PDR)을 기본 출발지로 쓴다.
  DirectionsCandidate? _selectedOrigin;

  final _outdoorKey = GlobalKey<OutdoorMapBodyState>();
  final _indoorKey = GlobalKey<IndoorMapBodyState>();

  // 지도 위에 얹은 공용 오버레이(검색창·저장한 장소 pill·하단 홈/실내 바)의
  // 영역을 IndoorMapBody가 map click 처리에서 제외할 수 있게 넘겨줄 key들.
  // MapLibre PlatformView가 gesture arena를 우회해서 오버레이 탭이 뒤의 매장
  // 까지 새어들어가는 문제를 여기서 함께 막는다.
  final _topBarKey = GlobalKey();
  final _favoritesPillKey = GlobalKey();
  final _categoryRowKey = GlobalKey();
  final _bottomBarKey = GlobalKey();
  final _searchPanelKey = GlobalKey();

  // 상단 검색창은 이제 여기(상위)가 소유한다. 결과 패널이 검색창 바로 아래에
  // 붙어야 하므로, 입력 상태를 검색창과 패널이 함께 볼 수 있는 이 자리에 둔다.
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  /// 검색이 활성인지 — 포커스가 들어왔거나 글자가 남아 있는 상태. true인
  /// 동안에만 결과 패널이 뜨고 지도 제스처가 잠긴다.
  bool _searchActive = false;
  String _searchQuery = '';

  /// 엔터로 확정할 때마다 1씩 오른다. 같은 글자로 다시 엔터를 눌러도 의미
  /// 검색이 다시 돌아야 하므로 bool이 아니라 카운터다.
  int _searchSubmitTick = 0;

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
    _searchFocus.addListener(_onSearchFocusChanged);
    _requestStartupPermissions();
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
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
    // 하단 바는 검색 막(barrier) 위에 있어 검색 중에도 눌린다. 화면이 바뀌는데
    // 결과 패널만 남아 있으면 안 되므로 여기서 함께 닫는다.
    _closeSearch();
    setState(() {
      _mode = mode;
      _placeInfo = null;
    });
  }

  /// 지금 화면이 "건물 안"을 보고 있는지. 실내 탭이거나, 야외 탭이어도 실내
  /// 진입 오버레이가 켜져 있으면 사용자에게는 똑같이 건물 내부를 보고 있는
  /// 상태다. 길찾기·카테고리 시트는 이 값으로 분기해야 한다 — 모드(_mode)만
  /// 보고 분기하면, 야외 지도 위에서 실내 도면을 훑는 동안 길찾기 후보가
  /// 매장이 아닌 건물 이름만 뒤져 "아무것도 안 나오는" 상태가 된다.
  bool get _indoorContextActive =>
      _mode == MapMode.indoor || _outdoorIndoorEntered;

  /// 지금 보고 있는 층. 실내 탭이면 실내 화면의 층, 야외 탭에서 실내 진입
  /// 오버레이를 보고 있으면 그 오버레이의 층. 어느 쪽도 아니면 null이라
  /// 호출부가 "층 개념 없음"으로 처리한다.
  String? get _activeIndoorFloor {
    if (_mode == MapMode.indoor) return _indoorKey.currentState?.currentFloor;
    if (_outdoorIndoorEntered) return _outdoorKey.currentState?.currentFloor;
    return null;
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

  /// 검색창에 포커스가 들어오면 그 자리에서 검색을 시작한다. 예전에는 탭이
  /// 아래에서 시트를 올렸고, 그 시트 안에 입력창이 하나 더 있었다 — 사용자가
  /// 방금 누른 창과 실제로 치는 창이 달라 검색창이 두 개인 것처럼 보였다.
  void _onSearchFocusChanged() {
    if (_searchFocus.hasFocus) _activateSearch();
  }

  void _activateSearch() {
    if (_searchActive) return;
    setState(() => _searchActive = true);
    // 결과 패널이 지도 위에 떠 있는 동안 지도 제스처를 잠근다. 실내는 웹에서
    // 실제 DOM 캔버스(MapLibre)라 패널 위 휠 이벤트가 지도로 새어나간다.
    _outdoorKey.currentState?.setInteractive(false);
    _indoorKey.currentState?.setInteractive(false);
  }

  /// 검색을 끝낸다. 결과를 골라 시트로 넘어갈 때도, 사용자가 뒤로/바깥을
  /// 눌러 그냥 닫을 때도 같은 경로를 탄다 — 어느 쪽이든 패널이 시트 뒤에
  /// 남아 겹치면 안 된다.
  void _closeSearch() {
    _searchFocus.unfocus();
    _searchController.clear();
    if (!_searchActive && _searchQuery.isEmpty) return;
    setState(() {
      _searchActive = false;
      _searchQuery = '';
    });
    _outdoorKey.currentState?.setInteractive(true);
    _indoorKey.currentState?.setInteractive(true);
  }

  void _onSearchChanged(String value) {
    _activateSearch();
    if (_searchQuery == value) return;
    setState(() => _searchQuery = value);
  }

  /// 엔터로 확정. 패널이 이 시점에만 의미 검색(`/query/ai`)까지 이어 붙인다.
  void _onSearchSubmitted(String value) {
    _activateSearch();
    setState(() {
      _searchQuery = value;
      _searchSubmitTick++;
    });
  }

  Future<void> _onSearchStorePicked(PoiSearchResult store) async {
    _closeSearch();
    await _runSheetChain(() => _showStoreInfo(store));
  }

  void _onSearchBuildingPicked(Building building) {
    _closeSearch();
    setState(() {
      _placeInfo = (
        title: building.name,
        subtitle: '${building.floors.length}개 층',
      );
    });
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
    // 야외의 실내 진입 오버레이에서 열린 시트도 있으므로 두 지도 모두에 알린다.
    _indoorKey.currentState?.clearHighlight();
    _outdoorKey.currentState?.clearHighlight();
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
      // 출발지를 지정하면 다음 "도착" 탭이 시트를 다시 열지 않고 바로 이
      // 매장을 출발지로 쓸 수 있도록 상위 상태에도 기억해둔다. 시트는
      // 도착지를 골라야 실제 경로를 그릴 수 있으므로 그대로 연다.
      setState(() => _selectedOrigin = candidate);
      await _openDirections(presetOrigin: candidate);
    } else if (action == StoreInfoAction.setDestination) {
      // 도착 버튼은 언제나 시트를 거치지 않고 바로 경로를 그린다.
      // - 명시적으로 고른 출발지가 있으면 그 매장에서 → 새 도착지
      // - 없으면 origin=null 로 넘겨 showRouteTo가 PDR 현재 위치(또는 위치
      //   지정으로 잡아둔 앵커) 기준으로 가장 가까운 통로 노드를 골라 라우팅
      // 어느 쪽도 준비되지 않은 경우(출발지·PDR 둘 다 없음)는 showRouteTo가
      // "출발 위치를 먼저 지정해주세요" 안내를 띄우므로, 여기서는 조용히
      // 시트를 다시 여는 이전 동작을 재현하지 않는다 — 사용자가 시트로
      // 되돌아가지 않고 바로 결과(경로 또는 안내)를 보게 하는 게 요청사항.
      await _startRoute(origin: _selectedOrigin, destination: candidate);
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
      final currentFloor = _activeIndoorFloor;
      final picked = await _withMapsLocked(
        () => CategoryStoresSheet.show(
          context,
          buildingId: _buildingId,
          category: category,
          onCloseAll: _requestCloseSheetChain,
          currentFloor: currentFloor,
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
    // 건물 밖을 보고 있을 때만 건물 입구가 후보다. 실내 진입 오버레이가 켜져
    // 있으면 야외 탭이어도 아래 매장 검색으로 흘려보낸다 — 그러지 않으면 실내
    // 도면을 보면서 길찾기를 열었는데 후보가 건물 이름뿐인 상태가 된다.
    if (!_indoorContextActive) {
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
    final currentFloor = _activeIndoorFloor;
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
    // 건물 안을 보고 있을 때만 현재 층 라벨을 시트에 넘겨 "B2에서 검색" 표시와
    // "전체 층에서 찾기" 토글이 뜨게 한다. 순수 야외 상태는 층 개념 자체가
    // 없으므로 null을 넘겨 토글을 숨긴다.
    final currentFloorLabel = _activeIndoorFloor;
    // 상위가 기억해둔 출발지가 있으면 시트에도 미리 채워, 사용자가 매번 다시
    // 입력하지 않아도 되게 한다. presetOrigin(이번 진입점에서 명시적으로 넘긴
    // 값)이 있으면 그 값이 우선한다.
    final initialOrigin = presetOrigin ?? _selectedOrigin;
    final result = await _withMapsLocked(
      () => DirectionsSheet.show(
        context,
        originLabel: '현재 위치',
        initialOrigin: initialOrigin,
        initialDestination: presetDestination,
        search: _searchDirectionsCandidates,
        currentFloorLabel: currentFloorLabel,
      ),
    );
    if (result == null || !mounted) return;

    // 시트 안에서 고른 출발지는 다음 "도착" 탭이 그대로 재사용할 수 있도록
    // 상위 상태에도 반영한다. "현재 위치"(=null)를 골랐다면 명시적 출발지가
    // 없다는 뜻이므로 저장된 값도 지워, 다음번엔 시트가 다시 열리게 한다.
    setState(() => _selectedOrigin = result.origin);
    await _startRoute(origin: result.origin, destination: result.destination);
  }

  /// 실제 경로 표시. 길찾기 시트를 거치는 경로와, 이미 기억해둔 출발지로 바로
  /// 라우팅하는 경로가 함께 쓸 수 있게 뽑아뒀다. [origin]이 null이면 "현재
  /// 위치"(=PDR)로 라우팅한다.
  Future<void> _startRoute({
    DirectionsCandidate? origin,
    required DirectionsCandidate destination,
  }) async {
    // 야외 지도에서 실내 진입 오버레이를 보는 중 실내 매장(nodeId+floor)까지
    // 길찾기를 시작하면, 화면(탭)을 바꾸지 않고 야외 화면 그대로에 실내 경로를
    // 그린다 — 방금 지정한 위치·매장·경로를 한 시야에서 확인하도록.
    // 출발지는 두 가지다:
    //   - origin이 없으면 "위치 지정"으로 잡아둔 PDR 앵커
    //   - origin이 매장이면(길찾기 시트에서 출발지로 고름) 그 매장의 노드
    // 후자를 걷기 경로(TMAP)로 보내면 건물 안 두 지점 사이에 직선이 그려져
    // 명백히 틀린 결과가 나오므로, 실내 노드 정보가 있으면 실내 라우팅으로 보낸다.
    if (_mode == MapMode.outdoor &&
        destination.floor != null &&
        destination.nodeId != null &&
        // origin이 있다면 그것도 실내 노드여야 실내 그래프로 이을 수 있다.
        // 건물 입구 같은 야외 후보라면 아래 걷기 경로로 흘려보낸다.
        (origin == null || (origin.floor != null && origin.nodeId != null))) {
      await _outdoorKey.currentState?.showIndoorRouteTo(
        PoiSearchResult(
          name: destination.title,
          floor: destination.floor!,
          point: destination.point,
          nodeId: destination.nodeId,
        ),
        origin: origin == null
            ? null
            : PoiSearchResult(
                name: origin.title,
                floor: origin.floor!,
                point: origin.point,
                nodeId: origin.nodeId,
              ),
      );
      return;
    }

    if (_mode == MapMode.outdoor) {
      await _outdoorKey.currentState?.showRouteTo(
        destination.point,
        label: destination.title,
        origin: origin?.point,
      );
      return;
    }
    // 실내는 IndoorMapBody.showRouteTo가 층이 다르면 건물 전체 그래프로
    // 층 간 경로(엘리베이터·에스컬레이터 포함)를 계산한다. 여기서는 origin/
    // destination을 다듬지 않고 그대로 넘긴다 — 층이 다르면 다층 경로,
    // 같으면 단일 층 경로로 자동 분기된다.
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

  /// "장소" 칩을 누르면 사용자가 저장해둔 매장 목록 시트를 연다. 항목을
  /// 탭하면 지도에서 매장을 직접 눌렀을 때와 동일한 매장 정보 시트가 뜬다.
  ///
  /// 매장 정보 시트에서 출발/도착을 고르지 않고 뒤로 닫으면 다시 저장된 장소
  /// 시트로 돌아온다 — 사용자가 여러 저장 항목을 훑어보다 잘못 눌렀거나
  /// 다른 항목을 다시 고르려는 경우를 위한 흐름이다.
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

  /// "위치 지정" 버튼(하단 바). 야외 지도에서 실내 진입 오버레이가 켜져 있으면
  /// 그 위에서 앵커 배치를 시작하고, 실내 지도 모드면 IndoorMapBody가 처리한다.
  /// 두 화면 모두 같은 PDR 세션을 사용하므로 어느 쪽에서 지정해도 이후 다른
  /// 쪽에서도 그대로 이어져 보인다.
  void _onPlaceLocation() {
    // 이제부터 지도를 탭해야 하므로 검색 막을 먼저 걷는다.
    _closeSearch();
    if (_mode == MapMode.indoor) {
      _indoorKey.currentState?.startLocationPlacement();
    } else {
      _outdoorKey.currentState?.startLocationPlacement();
    }
  }

  /// 결과 패널이 쓸 수 있는 최대 높이. 상단 바가 차지한 78 + 안전영역과,
  /// 올라온 소프트키보드 높이를 뺀 나머지다. 아주 좁은 화면에서 0 이하가
  /// 되지 않도록 하한을 둔다 — 0이면 패널이 아예 안 보여 검색이 죽은 것처럼
  /// 보인다.
  double _searchPanelMaxHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final available =
        media.size.height - media.padding.top - 78 - media.viewInsets.bottom - 16;
    return available < 180 ? 180 : available;
  }

  @override
  Widget build(BuildContext context) {
    final placeInfo = _placeInfo;
    final routeVisible = _mode == MapMode.outdoor ? _outdoorRouteVisible : _indoorRouteVisible;
    // 시트였을 때는 뒤로가기가 시트만 닫았다. 패널로 바뀌었다고 뒤로가기가
    // 앱을 종료해 버리면 안 되므로, 검색 중에는 pop을 가로채 검색만 닫는다.
    return PopScope(
      canPop: !_searchActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: _buildShell(context, placeInfo, routeVisible),
    );
  }

  Widget _buildShell(
    BuildContext context,
    ({String title, String subtitle})? placeInfo,
    bool routeVisible,
  ) {
    return Scaffold(
      // 상단 검색창(MapTopBar)에 포커스가 들어가 소프트키보드가 올라올 때
      // Scaffold body가 리사이즈되면 그 안의 MapLibre PlatformView(지도)도
      // 함께 줄어들며 리레이아웃이 발생해 모바일에서 화면이 눌리듯 버벅인다.
      // 키보드는 지도 위에 그대로 덮이도록 두어 지도 자체는 리사이즈되지 않게 한다.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          IndexedStack(
            index: _mode == MapMode.outdoor ? 0 : 1,
            children: [
              OutdoorMapBody(
                key: _outdoorKey,
                // IndexedStack은 안 보이는 쪽도 살려 두므로, 실내 탭으로
                // 넘어갔다는 사실을 야외 지도에 직접 알려야 한다 — 그래야
                // 실내에 있는 동안 야외 지도가 GPS를 구독하지 않는다.
                active: _mode == MapMode.outdoor,
                onRouteVisibleChanged: (visible) =>
                    setState(() => _outdoorRouteVisible = visible),
                onPlacingLocationChanged: (placing) {
                  if (_outdoorPlacingLocation == placing) return;
                  setState(() => _outdoorPlacingLocation = placing);
                },
                onIndoorEnteredChanged: (entered) {
                  if (_outdoorIndoorEntered == entered) return;
                  setState(() => _outdoorIndoorEntered = entered);
                },
                onStoreTap: (match) {
                  _runSheetChain(() => _showStoreInfo(match));
                },
              ),
              IndoorMapBody(
                key: _indoorKey,
                buildingId: _buildingId,
                onRouteVisibleChanged: (visible) =>
                    setState(() => _indoorRouteVisible = visible),
                onStoreTap: (match) {
                  _runSheetChain(() => _showStoreInfo(match));
                },
                onPlacingLocationChanged: (placing) {
                  if (_indoorPlacingLocation == placing) return;
                  setState(() => _indoorPlacingLocation = placing);
                },
                outerOverlayKeys: [
                  _topBarKey,
                  _favoritesPillKey,
                  _categoryRowKey,
                  _searchPanelKey,
                  _bottomBarKey,
                ],
              ),
            ],
          ),

          // 검색 중에는 지도 전체를 덮는 얇은 막을 깔아, 바깥을 누르면 검색이
          // 닫히게 한다. 예전 바텀시트의 barrier가 하던 역할이다 — 이게 없으면
          // 결과 패널이 뜬 채로 지도를 조작하게 되어 상태가 어긋난다.
          if (_searchActive)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeSearch,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.12),
                ),
              ),
            ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: MapTopBar(
              key: _topBarKey,
              showHamburger: _mode == MapMode.indoor,
              onHamburgerTap: _onHamburgerTap,
              controller: _searchController,
              focusNode: _searchFocus,
              onChanged: _onSearchChanged,
              onSubmitted: _onSearchSubmitted,
              searchActive: _searchActive,
              onCancelSearch: _closeSearch,
              onDirectionsTap: _openDirections,
            ),
          ),

          // 결과 패널과 카테고리 열은 같은 자리를 쓴다. 검색 중에는 카테고리
          // 열을 접어 두 오버레이가 겹치지 않게 한다.
          if (_searchActive)
            Positioned(
              top: 78,
              left: 12,
              right: 12,
              child: SafeArea(
                bottom: false,
                child: ConstrainedBox(
                  // 키보드가 올라와도 Scaffold를 리사이즈하지 않으므로
                  // (resizeToAvoidBottomInset: false), 패널이 키보드 밑으로
                  // 들어가지 않도록 여기서 직접 높이를 깎는다.
                  constraints: BoxConstraints(
                    maxHeight: _searchPanelMaxHeight(context),
                  ),
                  child: SearchPanel(
                    key: _searchPanelKey,
                    buildingId: _buildingId,
                    query: _searchQuery,
                    submitTick: _searchSubmitTick,
                    onStorePicked: _onSearchStorePicked,
                    onBuildingPicked: _onSearchBuildingPicked,
                  ),
                ),
              ),
            )
          else
            Positioned(
              top: 78,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _FavoritesPill(
                        key: _favoritesPillKey,
                        onTap: _openFavorites,
                      ),
                      const SizedBox(width: 8),
                      // 야외·실내 모드 모두에서 노출한다. _buildingId가 항상
                      // 현재 대상 건물(기본값 demoBuildingId)이라, 야외에서 chip을
                      // 눌러도 그 건물의 카테고리 매장 시트가 정상적으로 뜬다.
                      _CategoryChipsRow(
                        key: _categoryRowKey,
                        buildingId: _buildingId,
                        onSelectCategory: (category) {
                          _runSheetChain(() => _openCategoryStores(category));
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (placeInfo != null && !_searchActive)
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
              onPlaceLocation: _onPlaceLocation,
              placingLocation: _mode == MapMode.indoor
                  ? _indoorPlacingLocation
                  : _outdoorPlacingLocation,
              // 야외에서는 실내 진입 오버레이가 켜져 있을 때만 위치 지정 버튼을
              // 노출한다. 오버레이가 꺼진 순수 야외 상태에서는 지정할 층 정보가
              // 없어 눌러도 의미가 없다.
              showPlaceLocation: _mode == MapMode.indoor || _outdoorIndoorEntered,
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

/// 검색창 바로 아래 저장한 장소 pill 옆에 붙는 카테고리 chip 열.
/// 건물에 실제 존재하는 대분류만 골라 각각 하나의 chip으로 노출한다.
/// chip 탭 → 해당 카테고리 매장 목록 시트가 바로 열린다 (예전에는 카테고리
/// pill → 카테고리 목록 시트 → 매장 목록 시트로 두 단계였음).
///
/// 카테고리 enumeration은 건물 전 층의 `stores[].category`를 unique하게 뽑아
/// 매장 수 많은 순으로 정렬한다. HttpBuildingRepository가 층별 응답을
/// 캐시하므로 첫 로드 이후엔 즉시.
class _CategoryChipsRow extends StatefulWidget {
  const _CategoryChipsRow({
    super.key,
    required this.buildingId,
    required this.onSelectCategory,
  });

  final String buildingId;
  final ValueChanged<String> onSelectCategory;

  @override
  State<_CategoryChipsRow> createState() => _CategoryChipsRowState();
}

class _CategoryChipsRowState extends State<_CategoryChipsRow> {
  late Future<List<String>> _categoriesFuture = _load();

  @override
  void didUpdateWidget(covariant _CategoryChipsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.buildingId != widget.buildingId) {
      _categoriesFuture = _load();
    }
  }

  Future<List<String>> _load() async {
    final building = await buildingRepository.getBuilding(widget.buildingId);
    if (building == null) return const [];
    final counts = <String, int>{};
    for (final floor in building.floors) {
      final json = await buildingRepository.getFloorGeoJson(
        widget.buildingId,
        floor,
      );
      if (json == null) continue;
      final plan = FloorPlan.fromJson(json);
      for (final store in plan.stores) {
        final c = store.category;
        if (c == null || c.isEmpty) continue;
        counts[c] = (counts[c] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return entries.map((e) => e.key).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: _categoriesFuture,
      builder: (context, snapshot) {
        final categories = snapshot.data ?? const <String>[];
        if (categories.isEmpty) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < categories.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _CategoryChip(
                name: categories[i],
                onTap: () => widget.onSelectCategory(categories[i]),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = categoryIconFor(name);
    final color = categoryColorFor(name);
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                name,
                style: const TextStyle(
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
