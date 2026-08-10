import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../domain/dijkstra.dart';
import '../../domain/nearby_stores.dart';
import '../../features/debug_mode/debug_mode.dart';
import '../../features/indoor_navigation/contract/floor_transition_ui_state.dart';
import '../../models/building.dart';
import '../../models/category_count.dart';
import '../../models/favorite_place.dart';
import '../../models/floor_plan.dart';
import '../../models/poi_search_result.dart';
import '../../models/store_index_entry.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_menu_sheet.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/category_label_order.dart';
import '../../widgets/category_map_filter.dart';
import '../../widgets/category_stores_sheet.dart';
import '../../widgets/directions_sheet.dart';
import '../../widgets/favorites_sheet.dart';
import '../../widgets/floor_transition_overlay.dart';
import '../../widgets/map_bottom_bar.dart';
import '../../widgets/map_top_bar.dart';
import '../../widgets/place_detail_sheet.dart';
import '../../widgets/search_panel.dart';
import '../outdoor_map/outdoor_map_screen.dart';

/// 야외/실내 지도의 공통 뼈대. 홈(야외) ↔ 실내 전환은 Navigator push 없이
/// 이 화면 안에서 모드만 바꿔 탭처럼 즉시 반응하게 한다. 검색·길찾기·앱
/// 메뉴·위치 보정은 전부 이 화면이 상단/하단 공용 바를 통해 중계한다.
class MapShellScreen extends StatefulWidget {
  const MapShellScreen({super.key});

  @override
  State<MapShellScreen> createState() => _MapShellScreenState();
}

/// 경로가 표시되면 ETA 카드가 화면 최하단에 직접 도킹하므로, 하단 공용 바를
/// 그 위로 띄워야 하는 높이. EtaCard 실제 높이(패딩 포함)에 여유를 더한 값.
const _etaBarLiftHeight = 92.0;

/// 카테고리 필터 pill이 쓰는 (층·대분류·소분류)별 매장 수.
///
/// pill은 대분류·소분류만 읽는다. 층·개수는 지도 위 "이 층 N곳" 안내가 쓰던
/// 값인데, 그 안내를 걷어내고 목록 시트가 층별 묶음으로 대신 답하도록 바꿨다
/// (`category_stores_sheet.dart`). 응답 스키마라 필드는 그대로 두되, 이 화면은
/// 더 이상 읽지 않는다.
typedef _CategoryEntry = CategoryCount;

class _MapShellScreenState extends State<MapShellScreen> {
  /// 상단 오버레이 사이 간격. 예전 top: 78 / top: 128 같은 고정 offset을
  /// 대신하는 유일한 값이다. 상단 바 높이가 상태에 따라 달라져도 이 간격은
  /// 그대로라 어느 모드에서든 같은 여백으로 보인다.
  static const _overlayGap = 8.0;

  // 스크림 페이드 시간은 계약(floorTransitionScrimFadeIn/Out)이 정한다.
  // [IndoorMapBody]가 "덮인 뒤에 도면을 교체"하려고 같은 값을 기다리므로,
  // 여기서 따로 잡으면 두 값이 어긋나 교체 장면이 그대로 보인다.


  /// 이 앱이 다루는 건물. 한동안 햄버거 버튼이 "건물 선택 (테스트)" 시트를 열어
  /// 백엔드에 적재된 건물 목록에서 바꿀 수 있었지만, 데모용 전환 수단이었고
  /// 실제 사용 흐름에는 없는 조작이라 걷어냈다. 여러 건물을 실제로 다루게 되면
  /// 그때는 시트가 아니라 지도에서 건물을 골라 들어오는 흐름이어야 한다.
  static const _buildingId = demoBuildingId;

  /// 지도 위 카테고리 필터에서 지금 고른 것. null이면 강조 없음(기본 상태).
  /// 실내·야외 지도에 같은 값을 내려 두 화면의 강조가 어긋나지 않게 한다.
  CategorySelection? _categorySelection;

  /// 지금 보고 있는 층 라벨. 실내 지도가 onFloorChanged로 알려준다.
  /// [_activeIndoorFloor] getter와 값은 같지만, 이쪽은 **바뀔 때 rebuild가
  /// 도는** 상태다 — getter만 읽으면 층을 바꿔도 "이 층 N곳"이 옛 층에 머문다.
  ///
  /// 야외 지도도 실내 진입 오버레이가 켜지면 같은 콜백으로 알려준다. 그쪽에서도
  /// 카테고리 필터를 쓰므로, 안 받으면 "이 층 N곳"이 실내 탭에 들렀을 때의 옛
  /// 층에 머문다. 오버레이가 꺼진 순수 야외에서는 null이 올라온다.
  String? _activeFloorLabel;

  /// 건물의 (층·대분류·소분류)별 매장 수. pill 목록과 개수 안내가 같은 데이터를
  /// 봐야 하므로 화면 하나가 소유하고 아래로 내려 준다.
  ///
  /// **요청 하나다.** 예전에는 같은 정보를 얻으려고 층 지도를 층마다 받아
  /// (더현대 서울 기준 12건) 매장을 직접 셌다. 매장 폴리곤·좌표·그래프까지
  /// 따라오는 응답이라, 세 문자열과 개수를 얻는 값으로는 너무 비쌌다.
  late Future<List<_CategoryEntry>> _categoryEntriesFuture =
      _loadCategoryEntries();

  Future<List<_CategoryEntry>> _loadCategoryEntries() async {
    return await buildingRepository.getCategoryCounts(_buildingId) ?? const [];
  }

  /// 카테고리 목록을 다시 읽는다.
  ///
  /// **이 화면이 Future를 한 번만 만들기 때문에 필요하다.** 리포지토리는 실패한
  /// 요청을 캐시에 남기지 않지만([HttpBuildingRepository] `_shared` 주석), 이
  /// 화면이 들고 있는 Future 자체는 실패한 그대로 남는다. 앱을 켠 직후 네트워크가
  /// 아직 안 붙었거나 서버가 콜드 스타트 중이면 그 한 번의 실패가 세션 내내
  /// "칩이 아예 없는 화면"으로 굳는다 — 새 Future를 만들어야 다시 시도된다.
  void _reloadCategoryEntries() {
    setState(() => _categoryEntriesFuture = _loadCategoryEntries());
  }

  void _onActiveFloorChanged(String? floor) {
    if (_activeFloorLabel == floor || !mounted) return;
    setState(() => _activeFloorLabel = floor);
  }

  /// 실내 지도가 알려 온 층 전환 상태를 받는다.
  ///
  /// 탑승이 감지되면 검색을 닫는다. 검색 패널은 상단 Column 전체를 차지해
  /// 배너가 들어갈 자리가 없고, 그 순간 사용자에게 더 급한 정보는 길안내다.
  void _onFloorTransitionChanged(
    FloorTransitionUiState? banner,
    double scrimOpacity,
  ) {
    if (!mounted) return;
    if (_floorTransition == banner && _floorScrimOpacity == scrimOpacity) return;
    if (banner != null && _searchActive) {
      _closeSearch();
    }
    setState(() {
      _floorTransition = banner;
      _floorScrimOpacity = scrimOpacity;
    });
  }

  /// 카테고리 선택을 바꾼다. 지도 강조는 상태를 내려받은 두 지도가 알아서
  /// 갱신하므로 여기서는 상태만 바꾼다.
  void _onCategorySelectionChanged(CategorySelection? selection) {
    if (_categorySelection == selection) return;
    setState(() => _categorySelection = selection);
  }

  /// 지도 위 대분류 chip을 눌렀을 때. 강조를 걸고 **곧바로** 매장 목록 시트를
  /// 연다.
  ///
  /// 예전에는 chip → 소분류 pill 줄 → "목록" 버튼까지 세 번을 눌러야 이름을
  /// 볼 수 있었다. 강조만으로는 "저 파란 칸이 뭔지"에 답하지 못하는데, 정작
  /// 답이 있는 목록이 가장 멀리 있었다. 지금은 chip 한 번이면 목록이고,
  /// 소분류는 그 시트 안에서 고른다.
  ///
  /// 이미 고른 chip을 다시 누르면(=[selection]이 null) 해제만 하고 시트는 열지
  /// 않는다. 해제 수단이 사라지면 필터를 걸어 놓고 되돌릴 방법이 없어진다.
  void _onCategoryChipTapped(CategorySelection? selection) {
    _onCategorySelectionChanged(selection);
    final category = selection?.category;
    if (category == null) return;
    _runSheetChain(() => _openCategoryStores(category));
  }

  /// 검색이 빈손일 때 패널이 제안한 카테고리를 골랐다(설계:
  /// `docs/client/search-result-list-ux.md` R절).
  ///
  /// **검색을 먼저 닫는다.** 검색 패널은 상단 Column 전체를 차지하므로, 열어 둔
  /// 채 시트를 띄우면 목록이 패널 뒤로 들어간다. 닫은 뒤에는 지도 위 chip을 누른
  /// 것과 완전히 같은 경로를 탄다 — 같은 결과에 이르는 길이 둘로 갈리면 한쪽만
  /// 고쳐지는 날이 온다.
  void _onSearchCategoryPicked(String category) {
    _closeSearch();
    _onCategoryChipTapped(CategorySelection(category: category));
  }

  ({String title, String subtitle})? _placeInfo;
  bool _outdoorRouteVisible = false;

  /// 실내 지도에서 "위치 지정" 흐름이 켜져 있는지. IndoorMapBody가 콜백으로
  /// 알려주며, 하단 바 "위치 지정" 버튼을 눌린 상태로 표시하는 데 쓴다.

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

  /// 길찾기 시트의 "지도에서 선택"을 눌러 지금 지도에서 고르는 중인 칸.
  /// null이 아닌 동안에는 매장을 눌러도 매장 정보 시트가 뜨지 않고 그 매장이
  /// 곧바로 그 칸(출발지 또는 도착지)의 값이 된다.
  ///
  /// **어느 칸인지까지 들고 있어야 한다.** bool이던 때는 도착지 전용이라
  /// 충분했지만, 출발지도 같은 방식으로 고를 수 있게 되면서 지도 탭을 어느
  /// 칸으로 흘려보낼지 이 값으로 갈린다.
  ///
  /// 이 상태를 화면에 안내로 띄우는 것이 중요하다. 시트가 닫히기만 하면
  /// 사용자는 "지도에서 선택"을 눌렀는데 아무 일도 안 일어난 것으로 본다.
  DirectionsMapPickTarget? _mapPickTarget;

  /// 도착지를 먼저 고른 길찾기 초안. 이전에는 `도착`을 누르는 즉시 경로
  /// 계산을 시도해서, 출발 위치가 준비되지 않은 경우 이 후보가 화면과 함께
  /// 사라졌다. 이 값은 검색 취소·시트 닫힘과 분리된 MapShell 상태로 두고,
  /// 명시적 초기화 또는 다른 도착지 선택 때만 바꾼다.
  DirectionsCandidate? _routeDraftDestination;

  final _outdoorKey = GlobalKey<OutdoorMapBodyState>();

  /// 층 전환 배너·스크림 상태. 판정과 상태 전이는 [IndoorMapBody]가 소유하고
  /// 여기서는 그리기만 한다.
  ///
  /// 셸이 그려야 하는 이유: 검색창·카테고리 줄·하단 바가 이 Stack의 형제라,
  /// 지도 안에서 그린 배너는 그 뒤에 깔린다.
  FloorTransitionUiState? _floorTransition;
  double _floorScrimOpacity = 0;

  // 지도 위에 얹은 공용 오버레이(검색창·저장한 장소 pill·하단 홈/실내 바)의
  // 영역을 IndoorMapBody가 map click 처리에서 제외할 수 있게 넘겨줄 key들.
  // MapLibre PlatformView가 gesture arena를 우회해서 오버레이 탭이 뒤의 매장
  // 까지 새어들어가는 문제를 여기서 함께 막는다.
  final _topBarKey = GlobalKey();
  final _favoritesPillKey = GlobalKey();
  final _categoryRowKey = GlobalKey();
  final _bottomBarKey = GlobalKey();
  final _searchPanelKey = GlobalKey();

  /// "지도에서 도착지를 골라주세요" 안내. 이 카드의 X를 누른 탭이 지도까지
  /// 새어들어가면, 취소를 누른 손가락이 그 아래 매장을 도착지로 지정해 버린다.
  final _mapPickHintKey = GlobalKey();

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

  /// 현재 위치에서 각 그래프 노드까지의 거리·비용. 검색 결과가 매장마다
  /// "몇 m · 도보 몇 분"을 붙이는 데 쓴다. 위치가 없거나 건물 안이 아니면 null.
  ///
  /// **검색어마다 다시 계산하지 않는다.** 이 값은 검색어와 무관하게 "지금 내
  /// 위치"에만 딸려 있어서, 글자를 칠 때마다 갱신하면 건물 그래프 요청과
  /// 다익스트라를 타이핑 속도로 태우게 된다. 검색을 시작할 때와 위치를 새로
  /// 잡았을 때만 갱신한다.
  Map<String, NodeReach>? _reachByNodeId;

  /// 검색 결과 거리 표시용 도달 정보를 다시 계산한다.
  ///
  /// 건물 밖(순수 야외)에서는 실내 그래프 거리가 의미가 없으므로 비운다 —
  /// 남겨 두면 야외로 나온 뒤에도 예전 실내 위치 기준 거리가 목록에 남는다.
  Future<void> _refreshReach() async {
    if (!_indoorContextActive) {
      if (_reachByNodeId != null && mounted) {
        setState(() => _reachByNodeId = null);
      }
      return;
    }
    final reach = await _outdoorKey.currentState?.reachFromCurrentPosition();
    if (!mounted) return;
    setState(() => _reachByNodeId = reach);
  }

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
  ///
  /// 권한 요청은 한 번에 하나씩 순서대로 뜬다([requestStartupPermissions]).
  Future<void> _requestStartupPermissions() async {
    try {
      final statuses = await requestStartupPermissions();
      final anyDenied = statuses.values.any((status) => !status.isGranted);
      if (!mounted || !anyDenied) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('일부 권한이 거부되어 위치·실내 이동 관련 기능이 제한될 수 있습니다')),
      );
    } catch (_) {
      // 권한 플러그인을 쓸 수 없는 환경(테스트 등)에서도 앱을 계속 진행한다.
    }
  }

  /// 야외 컨텍스트로 나왔을 때, 실내 지점(층+노드)으로 잡아둔 출발지를 버린다.
  ///
  /// 실내에서 "출발지로 설정"한 매장은 야외 지도에서 쓸 수 없다. 그대로 두면
  /// 길찾기 시트의 출발지 칸에는 건물 안 매장이 적혀 있는데 실제 경로는 GPS에서
  /// 시작해, 화면에 적힌 출발지와 그려지는 경로가 어긋난다. 비우면 다시 "현재
  /// 위치"(=야외에서는 GPS)가 기본 출발지가 된다.
  void _dropIndoorOriginIfOutdoors() {
    if (_indoorContextActive) return;
    final origin = _selectedOrigin;
    if (origin == null) return;
    if (origin.floor == null && origin.nodeId == null) return;
    setState(() => _selectedOrigin = null);
  }

  /// 지금 화면이 "건물 안"을 보고 있는지. 실내 탭이거나, 야외 탭이어도 실내
  /// 진입 오버레이가 켜져 있으면 사용자에게는 똑같이 건물 내부를 보고 있는
  /// 상태다. 길찾기·카테고리 시트는 이 값으로 분기해야 한다 — 진입 여부만
  /// 보고 분기하면, 야외 지도 위에서 실내 도면을 훑는 동안 길찾기 후보가
  /// 매장이 아닌 건물 이름만 뒤져 "아무것도 안 나오는" 상태가 된다.
  bool get _indoorContextActive => _outdoorIndoorEntered;

  /// 지금 "현재 위치에서 출발"로 경로를 그릴 수 있는지.
  ///
  /// [_selectedOrigin]이 null인 것은 **두 가지를 겹쳐서** 뜻한다 — "현재 위치에서
  /// 출발"(위치 지정·PDR로 위치가 이미 잡혀 있음)과 "출발지가 아직 없음". 앞쪽은
  /// 도착지를 고르는 순간 바로 경로를 그려야 하고, 뒤쪽은 계산해도 실패 안내만
  /// 나오므로 상단 초안 바를 남겨 사용자가 출발지를 고르게 해야 한다. 둘을 null
  /// 하나로 뭉개면 "위치 지정으로 현재 위치를 찍은 뒤 매장에서 도착을 눌렀는데
  /// 아무 일도 안 일어나는" 상태가 된다.
  ///
  /// 건물 안을 보고 있으면 기준은 PDR 앵커다. 앵커가 없으면 실내 라우팅이 시작할
  /// 노드를 고르지 못한다([IndoorMapBodyState.showRouteTo]가 "출발 위치를 먼저
  /// 지정해주세요"로 되돌린다). 야외는 GPS가 출발점이고, 위치가 아직 없을 때의
  /// 안내는 야외 화면이 맡는다.
  bool get _canRouteFromCurrentLocation => _indoorContextActive
      ? indoorNavigationDriver.currentCalibration.canRenderPosition
      : true;

  /// 지금 보고 있는 층. 실내 탭이면 실내 화면의 층, 야외 탭에서 실내 진입
  /// 오버레이를 보고 있으면 그 오버레이의 층. 어느 쪽도 아니면 null이라
  /// 호출부가 "층 개념 없음"으로 처리한다.
  String? get _activeIndoorFloor {
    if (_outdoorIndoorEntered) return _outdoorKey.currentState?.currentFloor;
    return null;
  }

  /// 지금 지도 제스처를 잠그고 있는 이유들. 잠금 요청이 겹칠 수 있어서 bool이
  /// 아니라 집합이다 — 예전처럼 각자 `setInteractive(true)`로 풀면, 카테고리 열
  /// 위에 마우스를 올린 채 시트를 닫는 순간 아직 필요한 잠금까지 함께 풀린다.
  final _mapLockReasons = <String>{};

  /// 바텀시트·검색 패널이 지도 위에 떠 있는 동안.
  static const _mapLockSheet = 'sheet';
  static const _mapLockSearch = 'search';

  /// 지도 위 오버레이(장소 pill·카테고리 chip 열) 위에 포인터가 올라와 있는 동안.
  /// 마우스(hover)와 터치(pointer down)는 끝나는 시점이 달라 따로 센다.
  static const _mapLockOverlayHover = 'overlay-hover';
  static const _mapLockOverlayTouch = 'overlay-touch';

  void _lockMaps(String reason) {
    if (!_mapLockReasons.add(reason)) return;
    if (_mapLockReasons.length == 1) _applyMapInteractive();
  }

  void _unlockMaps(String reason) {
    if (!_mapLockReasons.remove(reason)) return;
    if (_mapLockReasons.isEmpty) _applyMapInteractive();
  }

  void _applyMapInteractive() {
    final interactive = _mapLockReasons.isEmpty;
    _outdoorKey.currentState?.setInteractive(interactive);
  }

  /// 바텀시트가 떠 있는 동안 지도 제스처를 꺼서, 시트를 마우스 휠로
  /// 스크롤할 때 그 아래 지도까지 같이 스크롤/줌되지 않게 한다.
  ///
  /// **웹에서만 잠근다.** 이 잠금이 막으려는 것은 웹 전용 증상이다 — 웹의
  /// MapLibre는 Flutter가 그리는 캔버스가 아니라 DOM에 실제로 존재하는
  /// `canvas.maplibregl-canvas`라, 그 위에 시트를 그려도 브라우저는 시트가 없는
  /// 것처럼 휠 이벤트를 지도에 그대로 전달한다([map_overlay_guard.dart] 상단에
  /// 같은 내용이 적혀 있다). iOS·Android는 지도가 네이티브 뷰이고 제스처가
  /// Flutter 아레나를 거치므로 애초에 새지 않는다.
  ///
  /// 그런데 잠금은 플랫폼을 가리지 않고 걸려 있었다. 그래서 실기기에서는 얻는
  /// 것 없이 **시트가 떠 있는 동안 지도가 통째로 얼었다** — 매장 상세 시트를 열면
  /// 위쪽에 그 매장이 보이는데 끌 수도 확대할 수도 없었다. 매장 상세 시트는
  /// barrier까지 없애 포인터를 지도로 흘리므로([_MapPassThroughSheetRoute]),
  /// 이 잠금이 남아 있으면 그 작업이 통째로 무효가 된다.
  ///
  /// 다른 시트(메뉴·길찾기)는 여전히 자기 `ModalBarrier`가 포인터를 막으므로,
  /// 네이티브에서 잠금을 풀어도 그쪽 동작은 달라지지 않는다.
  Future<T?> _withMapsLocked<T>(Future<T?> Function() showSheet) async {
    if (!kIsWeb) return showSheet();
    _lockMaps(_mapLockSheet);
    try {
      return await showSheet();
    } finally {
      _unlockMaps(_mapLockSheet);
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
    // 검색을 시작했다는 것은 지도에서 고르는 걸 그만뒀다는 뜻이다. 안내만 남으면
    // 검색 결과를 고른 뒤에도 다음 매장 탭이 출발지/도착지로 먹혀 버린다.
    _stopPickingOnMap();
    setState(() => _searchActive = true);
    // 결과에 붙일 거리는 여기서 한 번만 준비한다. 결과가 나오기 전에 시작하므로
    // 그래프 요청이 늦어도 목록은 먼저 뜨고, 거리 줄만 뒤늦게 채워진다.
    unawaited(_refreshReach());
    // 결과 패널이 지도 위에 떠 있는 동안 지도 제스처를 잠근다. 실내는 웹에서
    // 실제 DOM 캔버스(MapLibre)라 패널 위 휠 이벤트가 지도로 새어나간다.
    _lockMaps(_mapLockSearch);
  }

  /// 검색을 끝낸다. 결과를 골라 시트로 넘어갈 때도, 사용자가 뒤로/바깥을
  /// 눌러 그냥 닫을 때도 같은 경로를 탄다 — 어느 쪽이든 패널이 시트 뒤에
  /// 남아 겹치면 안 된다.
  void _closeSearch() {
    _searchFocus.unfocus();
    _searchController.clear();
    // 잠금 해제는 조기 반환보다 먼저 한다. 잡고 있지 않은 이유를 푸는 것은
    // no-op이므로, 상태가 어긋나도 잠금이 남아 지도가 굳는 일이 없다.
    _unlockMaps(_mapLockSearch);
    if (!_searchActive && _searchQuery.isEmpty) return;
    setState(() {
      _searchActive = false;
      _searchQuery = '';
    });
  }

  void _resumeSearchFromRouteDraft() {
    _activateSearch();
    _searchFocus.requestFocus();
  }

  void _clearRouteDraft() {
    _closeSearch();
    setState(() {
      _selectedOrigin = null;
      _routeDraftDestination = null;
    });
  }

  void _onSearchChanged(String value) {
    _activateSearch();
    if (_searchQuery == value) return;
    setState(() => _searchQuery = value);
  }

  /// 엔터로 확정. 패널이 이 시점에만 의미 검색(`/query/ai`)까지 이어 붙인다.
  void _onSearchSubmitted(String value) {
    _activateSearch();
    // 엔터는 "이 말로 찾겠다"는 분명한 신호라 여기서 최근 검색어에 남긴다.
    // 결과가 있었는지는 보지 않는다 — 못 찾은 말도 다시 시도하거나 고쳐 치는
    // 대상이라, 목록에 남는 편이 사용자에게 쓸모 있다.
    recentSearchesController.add(value);
    setState(() {
      _searchQuery = value;
      _searchSubmitTick++;
    });
  }

  /// 검색 패널의 최근 검색어를 골랐을 때. 패널은 입력창을 갖고 있지 않으므로
  /// 검색창 글자까지 여기서 맞춰 줘야 화면과 질의가 갈라지지 않는다.
  void _onSearchQueryPicked(String query) {
    _searchController.text = query;
    _onSearchSubmitted(query);
  }

  Future<void> _onSearchStorePicked(PoiSearchResult store) async {
    // 엔터 없이 디바운스 검색 결과를 바로 고르는 흐름이 더 흔하다. 그 경우도
    // "이 검색은 쓸모가 있었다"는 신호라 함께 남긴다. 같은 말이면 컨트롤러가
    // 중복 없이 맨 앞으로 올린다.
    recentSearchesController.add(_searchQuery);
    _closeSearch();
    await _runSheetChain(() => _showStoreInfo(store, focusOnMap: true));
  }

  /// 자동완성 후보 한 곳을 골랐을 때. 좌표를 붙여 검색 결과를 고른 것과 **같은
  /// 자리로 합류시킨다** — 후보에서 왔든 결과 목록에서 왔든 사용자에게는 같은
  /// 동작이어야 한다.
  ///
  /// 좌표는 층 도면에서 찾는다(`OutdoorMapBodyState.resolveIndexEntry`). 추가
  /// 요청은 없다 — 그 층은 어차피 열어야 하고, 도면이 매장마다 중심점을 들고 있다.
  ///
  /// 못 찾으면 예전처럼 그 이름으로 검색을 다시 돌린다. 후보와 층 도면이
  /// 어긋나는 경우(시드 갱신 직후, 아직 야외라 층을 옮길 수 없는 경우 등)에
  /// 아무 일도 일어나지 않는 것보다, 한 번 더 누르더라도 도달하는 편이 낫다.
  Future<void> _onSearchSuggestionPicked(StoreIndexEntry entry) async {
    recentSearchesController.add(_searchQuery);
    final resolved = await _outdoorKey.currentState?.resolveIndexEntry(entry);
    if (!mounted) return;
    if (resolved == null) {
      _onSearchQueryPicked(entry.name);
      return;
    }
    _closeSearch();
    await _runSheetChain(() => _showStoreInfo(resolved, focusOnMap: true));
  }

  /// 상세 시트가 부르는 "근처 매장" 계산.
  ///
  /// **여기서 하는 이유**: 그래프와 매장 색인은 이 화면이 이미 받아 두고 검색·경로에
  /// 쓰는 것이다(둘 다 저장소가 future를 공유해 캐시한다). 시트가 직접 받아 오면 같은
  /// 데이터가 두 벌이 되고, 시트를 테스트하려면 그래프부터 만들어야 한다.
  ///
  /// 서버에 새 엔드포인트를 만들지 않는 이유도 같다 — 필요한 것이 전부 이미 기기에
  /// 있고, 거리는 어차피 온디바이스 다익스트라가 정답이다(AGENTS.md의 경로 계산 규칙).
  Future<List<NearbyStore>> _loadNearbyStores(String entranceNodeId) async {
    final graph = await buildingRepository.getBuildingGraph(_buildingId);
    final index = await buildingRepository.getStoreIndex(_buildingId);
    if (graph == null || index == null || graph.nodes.isEmpty) return const [];

    final Map<String, NodeReach> reach;
    try {
      reach = reachableFrom(
        nodes: graph.nodes,
        edges: graph.edges,
        startNodeId: entranceNodeId,
      );
    } on ArgumentError {
      // 이 매장의 입구 노드가 그래프에 없다. 시드와 그래프가 어긋난 경우라
      // 목록만 빠지고 상세는 그대로 뜬다.
      return const [];
    }

    return nearbyStores(
      stores: index,
      reachByNodeId: reach,
      excludePlaceId: _nearbyOriginPlaceId ?? '',
    );
  }

  /// 근처 매장 목록에서 자기 자신을 빼려면 지금 열려 있는 매장 id가 필요하다.
  /// 시트가 인자로 넘기지 않는 이유는, 이 화면이 어차피 시트를 띄우면서 그 id를
  /// 이미 알고 있기 때문이다.
  String? _nearbyOriginPlaceId;

  /// 근처 매장 줄을 눌렀다. **검색 후보를 고른 것과 같은 경로**를 탄다 —
  /// 같은 결과에 이르는 길이 둘로 갈리면 한쪽만 고쳐지는 날이 온다.
  Future<void> _onNearbyStorePicked(StoreIndexEntry entry) async {
    // 지금 시트를 먼저 닫는다. 닫지 않고 새 시트를 올리면 상세가 상세 위에 쌓여
    // 뒤로 가기가 몇 번인지 사용자가 알 수 없게 된다.
    Navigator.of(context).pop();

    // `_onSearchSuggestionPicked`를 그대로 부르지 않는 이유는 그쪽이 **최근 검색어를
    // 남기기** 때문이다. 근처 매장을 누른 것은 검색이 아니라서, 부르면 방금 친 적도
    // 없는 말이 최근 목록에 쌓인다. 좌표를 찾고 시트를 여는 부분은 같은 함수를 쓴다.
    final resolved = await _outdoorKey.currentState?.resolveIndexEntry(entry);
    if (!mounted || resolved == null) return;
    await _runSheetChain(() => _showStoreInfo(resolved, focusOnMap: true));
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
  ///
  /// [keepZoom]이면 카메라를 옮기되 **배율은 그대로 둔다.** 지도에서 매장을
  /// 직접 눌렀을 때 쓴다 — 그 매장은 이미 화면에 있으므로 확대까지 하면 방금
  /// 보던 층 배치가 사라진다. 목록·검색 결과에서 온 매장은 지금 화면 어디에
  /// 있는지 알 수 없으니 확대해서 보여 주는 편이 맞다.
  Future<bool> _showStoreInfo(
    PoiSearchResult match, {
    bool focusOnMap = false,
    bool keepZoom = false,
  }) async {
    // 시트를 띄우기 전에 지도를 그 매장으로 옮겨, 시트를 닫으면 바로 그 자리가
    // 보이게 한다.
    if (focusOnMap) {
      // 곧 올라올 시트 높이를 함께 넘겨, 매장이 시트 뒤가 아니라 그 위 영역
      // 한가운데에 놓이게 한다. 시트 높이를 바꾸면 카메라도 자동으로 따라온다.
      await _outdoorKey.currentState?.focusStore(
        match,
        bottomSheetFraction: kPlaceDetailSheetInitialSize,
        keepZoom: keepZoom,
      );
      if (!mounted) return false;
    }
    final favorite = FavoritePlace.fromPoiSearchResult(
      match,
      buildingId: _buildingId,
    );
    if (!mounted) return false;
    // 근처 매장 목록에서 자기 자신을 빼는 데 쓴다.
    _nearbyOriginPlaceId = match.placeId;
    final showing = _withMapsLocked(
      () => PlaceDetailSheet.show(
        context,
        title: match.name,
        subtitle: match.floor,
        buildingId: _buildingId,
        placeId: match.placeId,
        favorite: favorite,
        // 대분류는 화면에 글자로 나오지 않고 헤더 아이콘의 폴백·강조색으로만 쓴다.
        category: match.category,
        // 대분류 칩을 없앴으므로 업종은 한 줄로만 보여 준다. 소분류가 없는
        // 장소에서 업종이 통째로 사라지지 않도록 대분류로 떨어뜨린다.
        subcategory: match.subcategory ?? match.category,
        // 검색 결과 목록이 쓰는 것과 **같은 계산 결과**를 넘긴다. 두 화면이
        // 같은 매장에 다른 거리를 적으면 어느 쪽도 못 믿게 된다.
        reach: match.nodeId == null ? null : _reachByNodeId?[match.nodeId],
        // "이 매장에서" 잰 근처 매장. 위 reach와 기준이 다르다 — 사용자 기준
        // 거리는 이미 헤더에 있고, 같은 기준으로 두 번 적으면 두 번째 줄이
        // 알려 주는 게 없다.
        nearbyStoresLoader: _loadNearbyStores,
        onSelectNearbyStore: _onNearbyStorePicked,
        onCloseAll: _requestCloseSheetChain,
      ),
    );
    // 떠 있는 동안만 값이 있다. 지도에서 다른 매장을 눌렀을 때 이 시트를 먼저
    // 닫고 기다리는 데 쓴다([_openStoreFromMap]).
    _placeDetailClosing = showing;
    final action = await showing;
    if (identical(_placeDetailClosing, showing)) _placeDetailClosing = null;
    if (!mounted) return false;
    // 시트가 어떻게 닫혔든(선택 없이 닫힘 포함) 지도 위 강조 표시도 같이 지운다.
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
      // 매장을 출발지로 쓸 수 있도록 상위 상태에도 기억해둔다. 이미 도착
      // 초안이 있으면 이 선택으로만 경로 조건이 완성되므로 즉시 계산한다.
      setState(() => _selectedOrigin = candidate);
      final destination = _routeDraftDestination;
      if (destination != null) {
        await _startRoute(origin: candidate, destination: destination);
      } else {
        await _openDirections(presetOrigin: candidate);
      }
    } else if (action == StoreInfoAction.setDestination) {
      // 출발지가 준비돼 있으면 바로 경로를 그린다. 명시적으로 고른 매장이거나,
      // 위치 지정·PDR로 현재 위치가 잡혀 있으면([_canRouteFromCurrentLocation])
      // 둘 다 출발지로 완전하다 — 후자를 빼면 위치를 찍어둔 사용자가 "도착"을
      // 눌러도 아무 일도 안 일어난다.
      //
      // 어느 쪽도 없을 때만 계산을 미루고 상단 초안 바를 남긴다. 그 상태에서
      // 계산하면 실패 안내만 나오고, 초안 바가 있으면 사용자가 출발 행을 눌러
      // DirectionsSheet 검색 흐름으로 이어갈 수 있다.
      setState(() => _routeDraftDestination = candidate);
      final origin = _selectedOrigin;
      if (origin != null || _canRouteFromCurrentLocation) {
        await _startRoute(origin: origin, destination: candidate);
      }
    }
    return true;
  }

  /// 카테고리 chip을 눌렀을 때 같은 카테고리의 매장 목록 시트를 연다. 항목을
  /// 탭하면 목록이 닫히고 그 매장의 상세 시트가 뜬다.
  ///
  /// **상세를 닫아도 목록으로 돌아가지 않는다.** 예전에는 여기가 loop여서 상세를
  /// 닫으면 카테고리 목록이 다시 올라왔다 — 여러 매장을 훑는 흐름을 노린 것이었다.
  /// 그런데 사용자에게는 매장을 하나 눌렀을 뿐인데 시트가 겹겹이 쌓인 것으로
  /// 읽혔다. 상세는 **그 매장 하나를 보는 자리**이고, 닫으면 지도로 끝나는 편이
  /// 예측 가능하다. 목록을 다시 보고 싶으면 chip을 다시 누르면 된다.
  Future<bool> _openCategoryStores(String category) async {
    final currentFloor = _activeIndoorFloor;
    final picked = await _withMapsLocked(
      () => CategoryStoresSheet.show(
        context,
        buildingId: _buildingId,
        category: category,
        onCloseAll: _requestCloseSheetChain,
        currentFloor: currentFloor,
        // 지도 강조와 시트 목록이 같은 소분류를 가리키게 한다. 다른 대분류가
        // 걸려 있었다면(매장 정보 시트에서 카테고리를 타고 들어온 경우) 그
        // 소분류는 이 대분류에 없는 값이므로 넘기지 않는다.
        subcategory: _categorySelection?.category == category
            ? _categorySelection?.subcategory
            : null,
        onFirstStoreChanged: _focusCategoryFirstStore,
        onSubcategoryChanged: (value) => _onCategorySelectionChanged(
          CategorySelection(category: category, subcategory: value),
        ),
      ),
    );
    if (_closeSheetChainRequested || picked == null || !mounted) return false;
    return _showStoreInfo(picked, focusOnMap: true);
  }

  /// 카테고리 목록 맨 위 매장으로 지도를 옮긴다. **배율은 건드리지 않는다.**
  ///
  /// 카테고리를 고르는 것은 "저 업종이 어디 있나"를 훑는 행동이라, 화면이 확
  /// 당겨지면 방금 보던 층 전체의 배치를 잃는다. 매장을 콕 집었을 때(검색 결과·
  /// 목록 항목)만 확대하고, 여기서는 중앙만 맞춘다(`focusKeepZoom`).
  ///
  /// 시트가 화면 아래를, 카테고리 chip 줄이 위를 가리므로 **그 사이에 남는 띠
  /// 한가운데**가 목표 지점이다. 정중앙에 놓으면 시트 뒤에 숨고, 시트 높이만
  /// 감안하면 이번엔 chip 줄 뒤로 올라간다.
  ///
  /// 시트는 현재 층 매장만 올려 준다(`onFirstStoreChanged` 주석). 다른 층으로
  /// 카메라를 보내면 지도가 층을 갈아타야 하는데, 그러면 시트 머리글이 말하는
  /// 층과 지도가 어긋난다.
  void _focusCategoryFirstStore(PoiSearchResult? store) {
    if (store == null || !mounted) return;
    final topInsetPx = _categoryRowBottomPx();
    if (_outdoorIndoorEntered) {
      _outdoorKey.currentState?.focusStore(
        store,
        bottomSheetFraction: kCategoryStoresSheetInitialSize,
        topInsetPx: topInsetPx,
        keepZoom: true,
      );
    }
  }

  /// 지도 위 카테고리 chip 줄의 아래 끝(화면 좌표·논리 픽셀). 상수로 박지 않고
  /// 실제로 재는 이유는, 이 줄이 길찾기 초안 바 때문에 아래로 밀리거나 검색 중
  /// 접히기 때문이다. 트리에 없으면 0 — 가릴 것이 없다는 뜻이다.
  double _categoryRowBottomPx() {
    final box =
        _categoryRowKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return 0;
    return box.localToGlobal(Offset.zero).dy + box.size.height;
  }

  Future<List<DirectionsCandidate>> _searchDirectionsCandidates(
    String query, {
    String? floorId,
  }) async {
    final normalized = query.trim().toLowerCase();
    // 건물 밖을 보고 있을 때만 건물 입구가 후보다. 실내 진입 오버레이가 켜져
    // 있으면 야외 탭이어도 아래 매장 검색으로 흘려보낸다 — 그러지 않으면 실내
    // 도면을 보면서 길찾기를 열었는데 후보가 건물 이름뿐인 상태가 된다.
    if (!_indoorContextActive) {
      final buildings = await buildingRepository.getAllBuildings();
      return buildings
          .where((b) => b.entrance != null)
          .where(
            (b) =>
                normalized.isEmpty || b.name.toLowerCase().contains(normalized),
          )
          .map(
            (b) => DirectionsCandidate(
              title: b.name,
              subtitle: '${b.floors.length}개 층',
              point: b.entrance!,
            ),
          )
          .toList();
    }
    // 길찾기는 **항상 건물 전체**에서 찾는다(currentFloorId를 넘기지 않는다).
    //
    // 예전에는 현재 층으로 좁히고 "전체 층에서 찾기" 토글로 넓히게 했다. 그런데
    // 길찾기를 여는 이유 자체가 대개 "지금 층에 없는 곳으로 가려고"라, 기본값이
    // 사용자 의도의 반대였다 — 찾는 매장이 결과에 아예 없어서 매번 토글을 켜야
    // 했다. 다른 층 결과에는 층 라벨이 부제로 붙으므로(아래 subtitle), 어느 층
    // 매장인지는 목록에서 그대로 읽힌다.
    // [floorId]는 **목록에서 고른 후보의 층**일 때만 값이 있다. 사용자가 직접 친
    // 질의에는 null이라 위 「항상 건물 전체」 규칙이 그대로 유지된다. 후보를 콕
    // 집은 행동에만 그 층으로 좁혀, 같은 이름이 층마다 있는 시설에서 화면에 적힌
    // 층과 실제로 가는 층이 어긋나지 않게 한다(search-result-list-ux.md T절).
    final results = await destinationRepository.searchDestinations(
      _buildingId,
      query,
      currentFloorId: floorId,
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

  /// 길찾기 시트의 2단계(의미 검색). 경량이 빈손일 때만 시트가 부른다.
  ///
  /// 상단 검색과 같은 `/query/ai` 계약을 그대로 태운다 — "밥 먹을 곳"처럼 이름이
  /// 아닌 말이 상단에서는 되고 길찾기에서는 안 되는 상태를 없애기 위해서다.
  /// 경량과 마찬가지로 층은 넘기지 않는다: 길찾기는 원래 다른 층으로 가려고 여는
  /// 기능이고, 백엔드의 의미 단계는 current_floor_id를 받아도 건물 전체를 본다
  /// (query_search.match_ai_destination).
  Future<DirectionsDiscovery> _semanticDirectionsCandidates(
    String query, {
    Map<String, List<String>>? selectedFacets,
    required bool showAll,
  }) async {
    final discovery = await destinationRepository.searchDestinationsAi(
      _buildingId,
      query,
      selectedFacets: selectedFacets,
      showAll: showAll,
    );
    return DirectionsDiscovery(
      mode: discovery.mode,
      source: discovery.source,
      question: discovery.question,
      options: discovery.options,
      candidates: discovery.matches
          .map(
            (m) => DirectionsCandidate(
              title: m.name,
              subtitle: m.floorName,
              point: m.point,
              nodeId: m.entranceNodeId,
              floor: m.floorName,
              reason: m.reason,
            ),
          )
          .toList(),
    );
  }

  /// 길찾기 시트를 연다. [presetOrigin]/[presetDestination]은 매장 정보
  /// 시트의 "출발지로 설정"/"도착지로 설정"에서 넘어올 때 그 매장으로 채워
  /// 둘 값이다. 저장된 도착 초안이 있으면 [presetDestination]이 없어도 그
  /// 값을 채워, 상단 출발 행에서 끊긴 흐름을 그대로 이어 간다. 시트 안에서
  /// 출발지를 직접 고르면(맨 위 "현재 위치" 포함) 그 선택이 [presetOrigin]보다
  /// 우선한다.
  /// [focusOrigin]은 출발지 칸을 활성으로 열지다. 상단 초안 바의 **출발 행**을
  /// 눌러 들어올 때만 켠다 — 출발지를 바꾸려고 누른 것이므로 커서가 그 칸에 있어야
  /// 한다. 매장 정보 시트에서 출발지를 이미 정하고 넘어오는 경우는 다음에 고를 것이
  /// 도착지라 기본값(도착지 활성)이 맞다.
  Future<void> _openDirections({
    DirectionsCandidate? presetOrigin,
    DirectionsCandidate? presetDestination,
    bool focusOrigin = false,
  }) async {
    // 상위가 기억해둔 출발지가 있으면 시트에도 미리 채워, 사용자가 매번 다시
    // 입력하지 않아도 되게 한다. presetOrigin(이번 진입점에서 명시적으로 넘긴
    // 값)이 있으면 그 값이 우선한다.
    final initialOrigin = presetOrigin ?? _selectedOrigin;
    final initialDestination = presetDestination ?? _routeDraftDestination;
    final result = await _withMapsLocked(
      () => DirectionsSheet.show(
        context,
        originLabel: '현재 위치',
        initialOrigin: initialOrigin,
        initialDestination: initialDestination,
        search: _searchDirectionsCandidates,
        // 야외(건물 입구를 고르는) 모드에서는 넘기지 않는다. `/query/ai`는 건물
        // 안의 매장을 찾는 계약이라, 건물을 고르는 자리에서 매장을 추천하면
        // 후보를 눌러도 갈 수 없는 목록이 된다. 시트가 떠 있는 동안에는 지도가
        // 잠겨(_withMapsLocked) 실내/야외가 바뀌지 않으므로 여는 시점의 판정을
        // 그대로 써도 된다.
        semanticSearch: _indoorContextActive
            ? _semanticDirectionsCandidates
            : null,
        // 상단 검색 결과와 같은 판단 재료를 준다. 이미 계산해 둔 맵을 넘길 뿐이라
        // 추가 계산이 없다(설계: map-ui-redesign-plan.md 「7+E 합동 설계」 2단계).
        reachByNodeId: _reachByNodeId,
        // 묶인 시설의 대표 층을 상단 검색과 같게 고르게 한다. 검색 범위는
        // 여전히 건물 전체다(위 「항상 건물 전체」).
        currentFloorId: _activeIndoorFloor,
        // 상단 검색과 같은 온디바이스 후보(초성·구두점·오타)를 길찾기에도 준다.
        // 리포지토리가 같은 Future를 공유하므로 두 번 받지 않는다.
        storeIndex: _indoorContextActive
            ? buildingRepository.getStoreIndex(_buildingId)
            : null,
        focusOrigin: focusOrigin,
      ),
    );
    if (result == null || !mounted) return;

    if (result.pickOnMap == DirectionsMapPickTarget.origin) {
      // 출발지를 지도에서 고르겠다는 뜻. **기존 출발지는 지우지 않는다** —
      // 지우면 사용자가 마음을 바꿔 취소했을 때 방금까지 잡혀 있던 출발지가
      // 함께 날아간다. 지도 탭이 확정하는 순간 [_onMapStoreTap]이 덮어쓴다.
      //
      // 시트에서 이미 고른 도착지는 초안으로 받아 둔다. 안 받으면 출발지를
      // 찍고 나서 도착지를 처음부터 다시 입력하게 된다.
      setState(() {
        _routeDraftDestination = result.destination ?? _routeDraftDestination;
        _mapPickTarget = DirectionsMapPickTarget.origin;
        // 안내 카드와 자리가 겹치므로 장소 카드는 접는다.
        _placeInfo = null;
      });
      return;
    }

    // 시트 안에서 고른 출발지는 다음 "도착" 탭이 그대로 재사용할 수 있도록
    // 상위 상태에도 반영한다. "현재 위치"(=null)를 골랐다면 명시적 출발지가
    // 없다는 뜻이므로 저장된 값도 지워, 다음번엔 시트가 다시 열리게 한다.
    setState(() => _selectedOrigin = result.origin);

    if (result.pickOnMap == DirectionsMapPickTarget.destination) {
      // 시트는 닫혔고, 이제 지도에서 매장을 누르는 것이 도착지 선택이다.
      // 도착 초안은 지우지 않는다 — 아직 새 도착지가 정해지지 않았고, 지도 탭이
      // 확정하는 순간 [_onMapStoreTap]이 덮어쓴다.
      setState(() {
        _mapPickTarget = DirectionsMapPickTarget.destination;
        _placeInfo = null;
      });
      return;
    }

    // 시트 안에서 확정한 도착지는 상단 초안에도 반영한다. 출발 위치가 아직
    // 준비되지 않아 경로가 끊겨도 이 후보가 화면과 함께 사라지지 않게 한다.
    final destination = result.destination!;
    setState(() => _routeDraftDestination = destination);
    await _startRoute(origin: result.origin, destination: destination);
  }

  /// 지도 화면이 "사용자 위치를 새로 잡았다"고 알려올 때. 기억해둔 출발지
  /// 매장을 버려서, 다음 길찾기가 **방금 잡은 위치**에서 출발하게 한다.
  ///
  /// 이게 없으면 이런 상태가 된다: 매장 A를 출발지로 지정해 길을 찾은 뒤,
  /// "위치 지정"으로 지금 서 있는 곳을 다시 찍고 다른 매장까지 길을 찾으면
  /// 경로가 여전히 A에서 출발한다. 화면에는 새로 찍은 위치 아이콘이 있는데
  /// 경로만 엉뚱한 데서 시작하니, 사용자는 위치 지정이 무시됐다고 본다.
  ///
  /// 출발지를 "매장 선택"으로 갱신하는 경로는 [_showStoreInfo]·[_openDirections]가
  /// 이미 [_selectedOrigin]을 새 값으로 덮어쓴다. 그래서 두 경로 모두 "마지막에
  /// 갱신한 위치"가 출발지가 된다.
  ///
  /// 버릴 매장 출발지가 없어도 **다시 그린다.** 상단 출발 행의 라벨은
  /// [_canRouteFromCurrentLocation]으로 갈리는데, 그 값은 이 시점에 막 참이 된다.
  /// 여기서 조기 반환하면 도착 초안을 먼저 잡아둔 상태에서 위치를 찍었을 때
  /// "출발지를 선택하세요"가 그대로 남는다 — 위치는 찍혔는데 화면만 아니라고 한다.
  void _onLocationAnchored() {
    setState(() => _selectedOrigin = null);
    // 출발점이 바뀌었으니 목록에 적힌 거리도 전부 옛 값이다. 다시 계산한다.
    unawaited(_refreshReach());
  }

  /// 지도에서 고르기를 끝낸다(선택 완료·취소 공통, 출발지·도착지 공통).
  void _stopPickingOnMap() {
    if (_mapPickTarget == null) return;
    setState(() => _mapPickTarget = null);
  }

  /// 지도에서 매장을 눌렀을 때의 분기점. 지도에서 고르는 중이면 매장 정보
  /// 시트를 열지 않고 그 매장을 해당 칸(출발지/도착지)의 값으로 쓴다.
  ///
  /// 두 지도(야외의 실내 진입 오버레이·실내 탭)가 같은 콜백을 쓰므로, 어느 쪽에서
  /// 골라도 동일하게 동작한다.
  void _onMapStoreTap(PoiSearchResult match) {
    final target = _mapPickTarget;
    if (target == null) {
      unawaited(_openStoreFromMap(match));
      return;
    }
    _applyMapPick(match, target);
  }

  /// 지금 떠 있는 상세 시트가 닫히면 완료되는 Future. 안 떠 있으면 null.
  Future<StoreInfoAction?>? _placeDetailClosing;

  /// 지도에서 매장을 눌러 상세를 연다. **떠 있는 상세가 있으면 먼저 닫는다.**
  ///
  /// 고른 매장은 폴리곤이 파랗게 채워지고([_highlightedStoreId]) 카메라가 그
  /// 매장을 시트 위 영역 한가운데로 끌어온다. 화면 구석을 눌렀을 때 강조된
  /// 매장이 곧바로 시트 뒤로 숨어 "무엇을 골랐는지" 확인할 수 없던 것을 없앤다.
  /// 배율은 건드리지 않는다(`keepZoom` — [_showStoreInfo] 주석).
  ///
  /// 이 시트는 barrier가 없어 포인터를 지도로 흘린다([_withMapsLocked] 주석) —
  /// 시트를 열어 둔 채 지도를 만질 수 있게 한 의도된 설계다. 그 대가로 다른
  /// 매장을 누르면 시트가 그 위에 하나 더 쌓였고, 사용자는 매장 하나를 봤을
  /// 뿐인데 닫기를 두 번 눌러야 했다.
  ///
  /// 닫기를 기다린 뒤에 여는 이유는 두 라우트가 겹치는 순간을 없애기 위해서다.
  /// 기다리지 않고 바로 열면 이전 시트의 pop 애니메이션과 새 시트의 push가
  /// 겹쳐 화면이 한 번 깜빡인다.
  Future<void> _openStoreFromMap(PoiSearchResult match) async {
    final closing = _placeDetailClosing;
    if (closing != null) {
      // pop은 chain 전체를 닫으라는 신호를 만들지만(PopScope), 아래
      // `_runSheetChain`이 시작할 때 그 플래그를 초기화하므로 새 시트에는
      // 영향이 없다.
      Navigator.of(context).pop();
      await closing;
      if (!mounted) return;
    }
    await _runSheetChain(
      () => _showStoreInfo(match, focusOnMap: true, keepZoom: true),
    );
  }

  /// 지도에서 고르는 중에 **매장이 아닌 곳(복도·빈 공간)** 을 눌렀을 때.
  ///
  /// 지도 화면이 그 탭을 통행 그래프에 스냅해 노드까지 확정한 뒤 넘겨주므로,
  /// 여기서는 매장을 눌렀을 때와 **완전히 같은 처리**를 태운다. 두 경로가 갈리면
  /// "복도로 지정한 출발지만 위치 아이콘이 안 따라온다" 같은 절반짜리 동작이
  /// 생긴다.
  ///
  /// 고르는 중이 아닐 때는 아무 일도 하지 않는다. 지도 화면도 같은 조건으로
  /// 막지만([IndoorMapBody.pickingOnMap]), 상태를 소유한 쪽에서 한 번 더 막아
  /// 두 값이 한 프레임 어긋나는 순간에 빈 곳 탭이 목적지가 되는 일을 없앤다.
  void _onMapPointPicked(PoiSearchResult picked) {
    final target = _mapPickTarget;
    if (target == null) return;
    _applyMapPick(picked, target);
  }

  /// 지도 탭으로 확정된 지점을 출발지/도착지에 반영한다. 매장 탭과 복도 탭이
  /// 공유하는 유일한 경로다.
  void _applyMapPick(PoiSearchResult match, DirectionsMapPickTarget target) {
    _stopPickingOnMap();
    // 강조 표시는 남겨두지 않는다 — 곧 경로와 핀이 그 자리를 대신한다.
    _outdoorKey.currentState?.clearHighlight();
    final picked = DirectionsCandidate(
      title: match.name,
      subtitle: match.floor,
      point: match.point,
      nodeId: match.nodeId,
      floor: match.floor,
    );

    if (target == DirectionsMapPickTarget.origin) {
      setState(() => _selectedOrigin = picked);
      // 출발점이 바뀌면 목록에 적힌 거리도 전부 옛 값이다.
      unawaited(_refreshReach());
      final destination = _routeDraftDestination;
      if (destination == null) {
        // 아직 도착지가 없다. 여기서 멈추면 사용자는 매장을 눌렀는데 아무 일도
        // 안 일어난 화면을 본다 — 시트의 [_afterOriginPicked]와 같은 규칙으로
        // 길찾기 시트를 다시 열어 도착지 입력을 이어 준다.
        unawaited(_openDirections(presetOrigin: picked));
        return;
      }
      unawaited(_startRoute(origin: picked, destination: destination));
      return;
    }

    // 지도 탭도 도착지를 확정하는 경로다. 다른 확정 경로와 같이 상단 초안에
    // 남겨, 출발 위치가 없어 경로가 끊겨도 후보가 사라지지 않게 한다.
    setState(() => _routeDraftDestination = picked);
    unawaited(_startRoute(origin: _selectedOrigin, destination: picked));
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
    //
    // **오버레이가 켜져 있을 때만** 이 분기를 탄다([_indoorContextActive]).
    // 오버레이를 닫고 야외 지도를 보는 중이라면 사용자의 위치는 GPS이지 실내
    // 앵커가 아니다. 그때도 실내 라우팅으로 보내면, 화면에는 GPS 위치 아이콘이
    // 있는데 경로만 예전에 찍어둔 건물 안 앵커에서 뻗어 나간다.
    if (_indoorContextActive &&
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

    if (!_indoorContextActive) {
      // 야외 걷기 경로(TMAP)는 출발지도 야외 좌표여야 한다. 실내 지점이 출발지로
      // 남아 있으면(실내에서 "출발지로 설정"한 매장을 그대로 들고 나온 경우)
      // 버리고 GPS 현재 위치에서 시작한다 — 건물 안 좌표를 그대로 보내면 실내
      // 두 지점 사이에 직선이 그려진다. [_dropIndoorOriginIfOutdoors]가 상태도
      // 함께 비우지만, 그 경로를 타지 않은 호출(모드 전환 없이 들어온 경우)에도
      // 같은 규칙이 적용되도록 여기서 한 번 더 막는다.
      final indoorOrigin = origin?.floor != null || origin?.nodeId != null;
      await _outdoorKey.currentState?.showRouteTo(
        destination.point,
        label: destination.title,
        origin: indoorOrigin ? null : origin?.point,
      );
      return;
    }
    // 실내는 showIndoorRouteTo가 층이 다르면 건물 전체 그래프로 층 간 경로
    // (엘리베이터·에스컬레이터 포함)를 계산한다. 여기서는 origin/destination을
    // 다듬지 않고 그대로 넘긴다 — 층이 다르면 다층, 같으면 단일 층으로 분기된다.
    //
    // 야외 경로(showRouteTo)와 **다른 메서드**다. 이름이 비슷하지만 하나는
    // Tmap 보행 경로, 하나는 건물 그래프 탐색이라 인자 타입부터 다르다.
    await _outdoorKey.currentState?.showIndoorRouteTo(
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
  /// 저장한 장소 목록을 연다. 항목을 탭하면 목록이 닫히고 상세 시트가 뜬다.
  ///
  /// 상세를 닫아도 목록으로 돌아가지 않는다 — 이유는 [_openCategoryStores]와 같다.
  Future<void> _openFavorites() async {
    await _runSheetChain(() async {
      final picked = await _withMapsLocked(
        () => FavoritesSheet.show(context, onCloseAll: _requestCloseSheetChain),
      );
      if (_closeSheetChainRequested || picked == null || !mounted) return;
      final enriched = await _favoriteWithCategory(picked);
      if (_closeSheetChainRequested || !mounted) return;
      await _showStoreInfo(enriched.toPoiSearchResult(), focusOnMap: true);
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

  /// 상단 바 햄버거 → 앱 메뉴. 시트는 **고른 항목만 돌려주고**, 실제 동작은
  /// 시트가 닫힌 뒤 여기서 실행한다. 시트가 콜백을 직접 들고 실행하면 이미
  /// 닫힌 시트의 `context`로 다음 시트를 띄우게 되고, 그 사이 모드가 바뀌면
  /// 옛 상태에 대고 동작한다.
  Future<void> _onMenuTap() async {
    final action = await _withMapsLocked(
      () => AppMenuSheet.show(
        context,
        // 하단 바의 "위치 지정" 버튼과 같은 조건이다. 건물 밖에서는 지정할
        // 층이 없어 눌러도 아무 일도 일어나지 않는다.
        showPlaceLocation: _outdoorIndoorEntered,
        debugEnabled: debugModeController.enabled,
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case AppMenuAction.favorites:
        await _openFavorites();
      case AppMenuAction.directions:
        await _openDirections();
      case AppMenuAction.placeLocation:
        _onPlaceLocation();
      case AppMenuAction.calibrate:
        _onCalibrate();
      case AppMenuAction.debugSettings:
        // 디버그 설정은 메인 지도에서 걷어냈으므로 이 메뉴가 유일한 진입점이다.
        // 시트 안에서 토글하면 지도 두 화면이 전역 컨트롤러의 알림을 받아
        // 알아서 다시 그린다.
        await _withMapsLocked<bool>(() async {
          await showDebugModeSettingsSheet(context, debugModeController);
          return true;
        });
    }
  }

  void _onCalibrate() {
    _outdoorKey.currentState?.recalibrate();
  }

  /// "위치 지정" 버튼(하단 바). 야외 지도에서 실내 진입 오버레이가 켜져 있으면
  /// 그 위에서 앵커 배치를 시작하고, 실내 지도 모드면 IndoorMapBody가 처리한다.
  /// 두 화면 모두 같은 PDR 세션을 사용하므로 어느 쪽에서 지정해도 이후 다른
  /// 쪽에서도 그대로 이어져 보인다.
  void _onPlaceLocation() {
    // 이제부터 지도를 탭해야 하므로 검색 막을 먼저 걷는다.
    _closeSearch();
    _outdoorKey.currentState?.startLocationPlacement();
  }

  @override
  Widget build(BuildContext context) {
    final placeInfo = _placeInfo;
    final routeVisible = _outdoorRouteVisible;
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
          OutdoorMapBody(
            key: _outdoorKey,
            onRouteVisibleChanged: (visible) =>
                setState(() => _outdoorRouteVisible = visible),
            onPlacingLocationChanged: (placing) {
              if (_outdoorPlacingLocation == placing) return;
              setState(() => _outdoorPlacingLocation = placing);
            },
            onIndoorEnteredChanged: (entered) {
              if (_outdoorIndoorEntered == entered) return;
              setState(() {
                _outdoorIndoorEntered = entered;
                // 오버레이가 닫히면 카테고리 칩 줄도 함께 사라진다. 선택만
                // 남겨 두면 사용자가 해제할 수단이 없는 채로, 다시 들어갔을
                // 때 영문 모를 강조가 걸려 있다(홈 탭으로 나갈 때와 같은 이유).
                if (!entered) _categorySelection = null;
              });
              // 오버레이를 닫고 야외로 나온 순간부터는 위치·출발지가 GPS다.
              if (!entered) _dropIndoorOriginIfOutdoors();
              // 실내 컨텍스트가 켜지고 꺼질 때마다 거리 기준이 통째로 바뀐다.
              unawaited(_refreshReach());
            },
            onStoreTap: _onMapStoreTap,
            // 실내 오버레이 위에서도 복도를 골라 출발/도착을 정할 수 있다.
            // 실내 탭과 같은 조작이어야 하므로 같은 값을 내려 준다.
            pickingOnMap: _mapPickTarget != null,
            onMapPointPicked: _onMapPointPicked,
            onLocationAnchored: _onLocationAnchored,
            // 실내 화면과 같은 선택을 넘긴다. 야외 지도도 실내 진입
            // 오버레이가 켜지면 같은 도면을 그리므로, 안 넘기면 칩을
            // 눌러도 강조가 안 뜬다.
            categorySelection: _categorySelection,
            onFloorChanged: _onActiveFloorChanged,
            onFloorTransitionChanged: _onFloorTransitionChanged,
            // 실내 화면과 같은 목록을 넘긴다. 야외 지도도 실내 진입
            // 오버레이가 켜지면 층 선택기·위치 지정을 함께 쓰므로, 상단
            // 검색창이나 하단 바를 누른 탭이 지도 탭으로 새어들어가면
            // 실내 오버레이가 닫히거나 그 자리에 PDR 앵커가 찍힌다.
            outerOverlayKeys: [
              _topBarKey,
              _favoritesPillKey,
              _categoryRowKey,
              _searchPanelKey,
              _bottomBarKey,
              _mapPickHintKey,
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
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.12)),
              ),
            ),

          // 상단 오버레이는 하나의 Column으로 쌓는다. 예전에는 검색 패널·카테고리
          // 열이 top: 78, 안내 카드가 top: 128인 고정 offset이었는데, MapTopBar의
          // 높이가 상태에 따라 달라진다 — 평소엔 검색창 한 줄이고 길찾기 draft에서는
          // 출발/도착 두 줄 + Divider다. 그래서 78은 두 상태의 타협치가 되어 평소엔
          // 여백이 남고 길찾기에서는 칩과 겹쳤다. Column이면 간격이 상수 하나로
          // 통일되고 어느 상태에서도 어긋나지 않는다.
          //
          // 히트 테스트용 GlobalKey는 그대로 각 자식에 붙어 있다. 지도 제스처 잠금은
          // 키의 RenderBox를 localToGlobal로 읽으므로 부모가 Stack이든 Column이든
          // 같은 값이 나온다.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            // 키보드가 올라와도 Scaffold를 리사이즈하지 않으므로
            // (resizeToAvoidBottomInset: false), 여기서 바닥을 직접 올려 검색
            // 패널이 키보드 밑으로 들어가지 않게 한다. 예전에는 상단 바 높이를
            // 상수로 가정해 별도 계산했지만, 이제는 Column의 실제 높이를 쓴다.
            bottom: MediaQuery.viewInsetsOf(context).bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              // 예전 Positioned가 left·right로 강제하던 폭을 대신한다. 기본값
              // (center)이면 자식이 제 내용 너비로 줄어들어, 검색 패널이 결과
              // 개수에 따라 폭이 들쭉날쭉해진다.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MapTopBar(
                  key: _topBarKey,
                  onMenuTap: _onMenuTap,
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: _onSearchChanged,
                  onSubmitted: _onSearchSubmitted,
                  searchActive: _searchActive,
                  onCancelSearch: _closeSearch,
                  onDirectionsTap: _openDirections,
                  onSearchRequested: _resumeSearchFromRouteDraft,
                  // 명시적으로 고른 매장이 없어도 현재 위치를 출발지로 쓸 수 있으면
                  // 그렇게 적는다. null을 그대로 넘기면 상단 바가 "출발지를
                  // 선택하세요" placeholder를 띄워, 위치를 방금 찍어둔 사용자에게
                  // 출발지가 비어 있다고 잘못 알린다.
                  routeOriginLabel:
                      _selectedOrigin?.title ??
                      (_canRouteFromCurrentLocation ? '현재 위치' : null),
                  routeDestinationLabel: _routeDraftDestination?.title,
                  onRouteOriginTap: () => _openDirections(
                    presetDestination: _routeDraftDestination,
                    focusOrigin: true,
                  ),
                  onRouteDestinationTap: () => _openDirections(
                    presetDestination: _routeDraftDestination,
                  ),
                  onClearRouteDraft: _routeDraftDestination == null
                      ? null
                      : _clearRouteDraft,
                ),

                // 층 전환 배너는 고정 top 숫자가 아니라 **이 Column 흐름**에
                // 놓는다. 상단 바 높이는 상태마다 달라지므로(검색 한 줄 ↔
                // 출발/도착 두 줄), 상수로 잡으면 어느 한쪽에서 반드시 겹친다.
                // 전환 중에는 아래 카테고리 줄을 접어 자리를 보장한다.
                //
                // 스크림이 올라온 구간에서는 배너를 접는다. 스크림 카드가 같은
                // 문장을 화면 한가운데에서 더 크게 말하고 있어서, 둘을 같이
                // 띄우면 같은 내용이 두 벌로 보인다(배너는 스크림 **아래** 층에
                // 깔리므로 흐려지기까지 한다).
                if (_floorTransition case final transition?
                    when _floorScrimOpacity <= 0)
                  Padding(
                    padding: const EdgeInsets.only(top: _overlayGap),
                    child: Center(
                      child: FloorTransitionBanner(
                        state: transition,
                        onUndo: () =>
                            _outdoorKey.currentState?.undoFloorTransition(),
                      ),
                    ),
                  ),

                // 결과 패널과 카테고리 열은 같은 자리를 쓴다. 검색 중에는
                // 카테고리 열을 접어 두 오버레이가 겹치지 않게 한다.
                if (_searchActive)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        12,
                        _overlayGap,
                        12,
                        12,
                      ),
                      child: SearchPanel(
                        key: _searchPanelKey,
                        buildingId: _buildingId,
                        query: _searchQuery,
                        submitTick: _searchSubmitTick,
                        onStorePicked: _onSearchStorePicked,
                        onBuildingPicked: _onSearchBuildingPicked,
                        onQueryPicked: _onSearchQueryPicked,
                        onSuggestionPicked: _onSearchSuggestionPicked,
                        indoorContextActive: _indoorContextActive,
                        currentFloorId: _activeIndoorFloor,
                        reachByNodeId: _reachByNodeId,
                        // "찾지 못했어요" 화면의 탈출구. 지도 위 chip 줄과 **같은
                        // Future**를 넘긴다 — 다시 요청하면 같은 정보를 두 번
                        // 받게 되고, 두 화면의 카테고리 목록이 어긋날 수 있다.
                        categoryEntries: _categoryEntriesFuture,
                        onCategoryPicked: _onSearchCategoryPicked,
                      ),
                    ),
                  )
                // 층 전환 중에는 카테고리 줄을 접는다. 배너가 상단 바 바로
                // 아래에 오도록 자리를 비우는 것이고, 전환은 몇 초짜리 상태다.
                else if (_floorTransition != null)
                  const SizedBox.shrink()
                // 길찾기 draft에서는 **접지 않고 내려온다.** 상단 바가 출발/도착
                // 두 줄로 커지면 이 Column이 그만큼 아래로 밀어 주므로 겹치지
                // 않는다. 한때 접어 뒀지만, 도착지를 정한 뒤에도 "그럼 저긴
                // 뭐였지" 하고 카테고리를 다시 훑는 흐름이 끊겼다.
                else
                  Padding(
                    padding: const EdgeInsets.only(top: _overlayGap),
                    // 지도 위에는 **대분류 한 줄만** 둔다. 소분류는 chip을 누르면
                    // 바로 올라오는 매장 목록 시트 안으로 옮겼다 — 시트가 곧장
                    // 뜨는 마당에 같은 pill 줄을 지도에도 그리면 화면에 같은
                    // 조작이 두 벌 남는다.
                    child: _MapOverlayScrollRow(
                      key: _categoryRowKey,
                      onPointerOverChanged: (over) => over
                          ? _lockMaps(_mapLockOverlayHover)
                          : _unlockMaps(_mapLockOverlayHover),
                      onPointerDownChanged: (down) => down
                          ? _lockMaps(_mapLockOverlayTouch)
                          : _unlockMaps(_mapLockOverlayTouch),
                      children: [
                        _FavoritesPill(
                          key: _favoritesPillKey,
                          onTap: _openFavorites,
                        ),
                        // 카테고리 필터는 **건물 안을 보고 있을 때만**
                        // 노출한다. 기준은
                        // [_indoorContextActive]다 — 야외 탭이어도 건물을
                        // 탭하거나 줌으로 실내 오버레이가 켜지면 사용자에게는
                        // 실내 화면과 똑같은 도면이 떠 있고, 그 위에 강조가
                        // 그려진다. 모드로 분기하면 그 상태에서 칩만 사라져,
                        // 웹(마우스로 실내 탭을 눌러 들어감)에서는 보이고
                        // 모바일(도면을 탭해 바로 진입)에서는 안 보인다.
                        //
                        // 반대로 오버레이가 꺼진 순수 야외에서는 계속 감춘다.
                        // 아직 들어가지도 않은 건물의 카테고리를 누르게 되고,
                        // 강조는 도면 위에 그려지므로 결과가 보이지 않는다.
                        if (_indoorContextActive) ...[
                          const SizedBox(width: 8),
                          _CategoryChipsRow(
                            entriesFuture: _categoryEntriesFuture,
                            selection: _categorySelection,
                            onSelectionChanged: _onCategoryChipTapped,
                            onRetry: _reloadCategoryEntries,
                          ),
                        ],
                      ],
                    ),
                  ),

                // 지도에서 고르는 중이라는 안내. 이게 없으면 "지도에서 선택"을
                // 눌렀을 때 시트만 닫히고 아무 일도 안 일어난 것처럼 보인다.
                if (_mapPickTarget != null && !_searchActive)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, _overlayGap, 12, 0),
                    child: _MapPickHintCard(
                      key: _mapPickHintKey,
                      target: _mapPickTarget!,
                      // 지금 고르는 칸의 **반대쪽**을 보여준다. 출발지를 고르는
                      // 중이면 도착지가, 도착지를 고르는 중이면 출발지가 무엇으로
                      // 잡혀 있는지 알아야 지금 무엇을 누를지 판단할 수 있다.
                      counterpartLabel:
                          _mapPickTarget == DirectionsMapPickTarget.origin
                          ? _routeDraftDestination?.title
                          : (_selectedOrigin?.title ?? '현재 위치'),
                      onCancel: _stopPickingOnMap,
                    ),
                  )
                else if (placeInfo != null && !_searchActive)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, _overlayGap, 12, 0),
                    child: _PlaceInfoCard(
                      title: placeInfo.title,
                      subtitle: placeInfo.subtitle,
                      onClose: () => setState(() => _placeInfo = null),
                    ),
                  ),
              ],
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
              onCalibrate: _onCalibrate,
              onPlaceLocation: _onPlaceLocation,
              placingLocation: _outdoorPlacingLocation,
              // 야외에서는 실내 진입 오버레이가 켜져 있을 때만 위치 지정 버튼을
              // 노출한다. 오버레이가 꺼진 순수 야외 상태에서는 지정할 층 정보가
              // 없어 눌러도 의미가 없다.
              showPlaceLocation: _outdoorIndoorEntered,
            ),
          ),

          // 층 전환 스크림. root Stack의 **마지막** 레이어라 지도뿐 아니라
          // 검색창·카테고리·하단 바까지 함께 덮는다. 도면 교체 프레임에서만
          // 완전히 덮고 뒤쪽 입력을 막으며, 탑승 구간은 반투명이라 사용자가
          // 지도를 계속 만질 수 있다.
          Positioned.fill(
            child: FloorTransitionScrim(
              opacity: _floorScrimOpacity,
              fadeIn: floorTransitionScrimFadeIn,
              fadeOut: floorTransitionScrimFadeOut,
              state: _floorTransition,
            ),
          ),
        ],
      ),
    );
  }
}

/// 지도 위에 얹은 가로 스크롤 오버레이 열(장소 pill + 카테고리 chip)의 껍데기.
///
/// 이 위젯이 존재하는 이유는 두 가지 모두 **지도가 Flutter 위젯이 아니라
/// MapLibre 플랫폼 뷰**라는 데서 나온다. 위젯 트리에서는 이 열이 지도 위에
/// 있지만, 실제 포인터 입력은 지도 쪽에도 그대로 도착한다.
///
/// 1. **지도 잠금** — 이 열 위에서 휠을 굴리면 그 휠이 지도까지 내려가 지도가
///    확대/축소된다("카테고리 열을 스크롤했는데 지도 배율이 같이 변한다"). 시트를
///    열 때 쓰던 것과 같은 잠금([MapShellScreen._withMapsLocked])을 포인터가 이
///    열 위에 있는 동안에도 걸어 지도 제스처 자체를 꺼 둔다.
/// 2. **세로 휠 → 가로 스크롤** — Flutter의 가로 스크롤 뷰는 세로 휠 delta를
///    0으로 계산해 아예 소비하지 않는다. 그래서 휠을 굴려도 열은 그대로고 지도만
///    움직였다. 세로 delta를 가로 오프셋으로 직접 옮겨 준다.
class _MapOverlayScrollRow extends StatefulWidget {
  const _MapOverlayScrollRow({
    super.key,
    required this.onPointerOverChanged,
    required this.onPointerDownChanged,
    required this.children,
  });

  /// 마우스 포인터가 이 열 위로 들어오거나 나갈 때.
  final ValueChanged<bool> onPointerOverChanged;

  /// 이 열 위에서 손가락/버튼이 눌리거나 떼어질 때. hover가 없는 터치 환경을
  /// 위한 경로라 hover와 별개로 통지한다.
  final ValueChanged<bool> onPointerDownChanged;

  final List<Widget> children;

  @override
  State<_MapOverlayScrollRow> createState() => _MapOverlayScrollRowState();
}

class _MapOverlayScrollRowState extends State<_MapOverlayScrollRow> {
  final _controller = ScrollController();
  bool _pointerOver = false;
  bool _pointerDown = false;

  @override
  void dispose() {
    // 잠금을 쥔 채로 사라지면(검색이 켜져 이 열이 트리에서 빠지는 경우 등)
    // 지도가 영영 잠긴 상태로 남는다. 나가면서 반드시 반납한다.
    //
    // **다음 프레임으로 미루는 것이 중요하다.** 반납은 지도 위젯의 setState로
    // 이어지는데, dispose는 상위 rebuild 도중에 실행될 수 있어 그 자리에서 부르면
    // "setState() called during build"로 터진다. 반납은 멱등이라 (MouseRegion이
    // 제거되며 보내는 onExit와 겹쳐) 두 번 불려도 문제없다.
    final releaseHover = _pointerOver ? widget.onPointerOverChanged : null;
    final releaseTouch = _pointerDown ? widget.onPointerDownChanged : null;
    if (releaseHover != null || releaseTouch != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        releaseHover?.call(false);
        releaseTouch?.call(false);
      });
    }
    _controller.dispose();
    super.dispose();
  }

  void _setPointerOver(bool value) {
    if (_pointerOver == value) return;
    _pointerOver = value;
    widget.onPointerOverChanged(value);
  }

  void _setPointerDown(bool value) {
    if (_pointerDown == value) return;
    _pointerDown = value;
    widget.onPointerDownChanged(value);
  }

  /// 세로 휠을 가로 오프셋으로 옮긴다. 트랙패드 가로 스크롤(dx)도 그대로 받도록
  /// dy가 0일 때는 dx를 쓴다.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    _controller.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      // 잠금·휠 처리는 뷰포트 전체가 아니라 chip이 실제로 그려진 영역에만 건다.
      // 뷰포트는 화면 폭 전체라, 바깥까지 잠그면 chip 오른쪽 빈 곳에 마우스를
      // 올려 둔 것만으로 지도 휠 줌이 죽는다.
      child: MouseRegion(
        onEnter: (_) => _setPointerOver(true),
        onExit: (_) => _setPointerOver(false),
        child: Listener(
          onPointerSignal: _onPointerSignal,
          onPointerDown: (_) => _setPointerDown(true),
          onPointerUp: (_) => _setPointerDown(false),
          onPointerCancel: (_) => _setPointerDown(false),
          child: Row(mainAxisSize: MainAxisSize.min, children: widget.children),
        ),
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
      // 지도에 붙은 조작 줄이다. 그림자를 줄이고 경계는 hairline이 맡는다
      // (AppElevation.onMap).
      elevation: AppElevation.onMap,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.hairline),
      ),
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
/// 사용자에게 보이는 label 기준 가나다 순으로 정렬한다. HttpBuildingRepository가 층별 응답을
/// 캐시하므로 첫 로드 이후엔 즉시.
class _CategoryChipsRow extends StatelessWidget {
  const _CategoryChipsRow({
    required this.entriesFuture,
    required this.selection,
    required this.onSelectionChanged,
    required this.onRetry,
  });

  final Future<List<_CategoryEntry>> entriesFuture;
  final CategorySelection? selection;
  final ValueChanged<CategorySelection?> onSelectionChanged;

  /// 목록 로드가 실패했을 때 다시 읽기.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_CategoryEntry>>(
      future: entriesFuture,
      builder: (context, snapshot) {
        // 실패를 빈 목록과 같이 취급하면 안 된다. 둘 다 `data == null`이지만
        // 화면에서 아무것도 안 그리면 사용자에게는 "이 앱엔 원래 카테고리가
        // 없다"로 보이고, 다시 시도할 방법도 없다. 실패는 눌러서 재시도할 수
        // 있는 칩으로 드러낸다.
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasError) {
          return _CategoryRetryChip(onTap: onRetry);
        }
        final entries = snapshot.data ?? const <_CategoryEntry>[];
        if (entries.isEmpty) return const SizedBox.shrink();
        final categories = sortedCategoryLabels(
          entries.map((entry) => entry.category),
        );
        if (categories.isEmpty) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < categories.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _CategoryChip(
                name: categories[i],
                selected: selection?.category == categories[i],
                // 이미 고른 대분류를 다시 누르면 해제한다. 해제 수단이 따로
                // 없으면 사용자는 필터를 걸고 나서 원래 화면으로 못 돌아온다.
                onTap: () => onSelectionChanged(
                  selection?.category == categories[i]
                      ? null
                      : CategorySelection(category: categories[i]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;

  /// 지금 이 대분류로 지도가 필터돼 있는지. 선택 상태를 카테고리 고유색으로
  /// 칠해, 어떤 카테고리가 걸려 있는지 pill 줄만 보고도 알 수 있게 한다.
  final bool selected;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = categoryIconFor(name);
    final color = categoryColorFor(name);
    return Material(
      color: selected ? color : Colors.white,
      elevation: AppElevation.onMap,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        // 선택된 chip은 카테고리 고유색으로 채워지므로 경계선이 필요 없다.
        side: BorderSide(
          color: selected ? Colors.transparent : AppColors.hairline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: selected ? Colors.white : color),
              const SizedBox(width: 6),
              Text(
                name,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 카테고리 목록을 못 읽었을 때 칩 자리에 대신 뜨는 재시도 버튼.
///
/// 칩과 같은 모양·같은 자리에 둔다. 별도 배너로 띄우면 지도 위 오버레이가
/// 한 줄 더 늘어나 검색창·안내 카드와 자리를 다투게 된다.
class _CategoryRetryChip extends StatelessWidget {
  const _CategoryRetryChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      // 지도에 붙은 조작 줄이다. 그림자를 줄이고 경계는 hairline이 맡는다
      // (AppElevation.onMap).
      elevation: AppElevation.onMap,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.hairline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded, size: 16, color: AppColors.muted),
              SizedBox(width: 6),
              Text(
                '카테고리 다시 불러오기',
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

/// "지도에서 선택"을 누른 뒤 지도 위에 뜨는 안내.
///
/// 시트가 닫힌 자리에 아무 표시도 없으면, 사용자는 방금 누른 버튼이 먹지 않은
/// 것으로 본다. 지금 무엇을 눌러야 하는지와 반대쪽 칸이 무엇으로 잡혀 있는지를
/// 함께 보여주고, 마음이 바뀌면 그 자리에서 취소할 수 있게 한다.
class _MapPickHintCard extends StatelessWidget {
  const _MapPickHintCard({
    super.key,
    required this.target,
    required this.counterpartLabel,
    required this.onCancel,
  });

  /// 지금 지도에서 고르는 중인 칸.
  final DirectionsMapPickTarget target;

  /// 반대쪽 칸에 잡혀 있는 것. 아직 없으면 null이며, 그때는 줄 자체를 그리지
  /// 않는다 — "도착: " 뒤가 비어 있으면 값을 못 읽은 것처럼 보인다.
  final String? counterpartLabel;

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final isOrigin = target == DirectionsMapPickTarget.origin;
    final counterpart = counterpartLabel;
    return Card(
      color: AppColors.blue50,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            const Icon(
              Icons.touch_app_outlined,
              color: AppColors.primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 복도도 고를 수 있게 된 뒤로 "매장을 눌러주세요"는 틀린
                  // 안내가 됐다. 안내가 매장만 말하면 복도를 눌러도 된다는 걸
                  // 아무도 모르고, 매장이 없는 자리를 눌러 본 사용자는 앱이
                  // 반응하지 않는다고 읽는다.
                  Text(
                    isOrigin
                        ? '출발지로 지정할 매장이나 복도를 지도에서 눌러주세요'
                        : '도착지로 지정할 매장이나 복도를 지도에서 눌러주세요',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  if (counterpart != null)
                    Text(
                      isOrigin ? '도착: $counterpart' : '출발: $counterpart',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: '지도에서 선택 취소',
              onPressed: onCancel,
              icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceInfoCard extends StatelessWidget {
  const _PlaceInfoCard({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

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
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
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
