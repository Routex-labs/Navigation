import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../domain/dijkstra.dart';
import '../../domain/outdoor_poi_ranking.dart';
import '../../models/building.dart';
import '../../models/category_count.dart';
import '../../models/favorite_place.dart';
import '../../models/floor_plan.dart';
import '../../models/outdoor_poi.dart';
import '../../models/poi_search_result.dart';
import '../../models/transit_route.dart';
import '../../theme/app_theme.dart';
import '../../widgets/building_switcher_sheet.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/category_label_order.dart';
import '../../widgets/category_map_filter.dart';
import '../../widgets/category_stores_sheet.dart';
import '../../widgets/category_taxonomy.dart';
import '../../widgets/directions_sheet.dart';
import '../../widgets/favorites_sheet.dart';
import '../../widgets/map_bottom_bar.dart';
import '../../widgets/map_top_bar.dart';
import '../../widgets/outdoor_poi_sheet.dart';
import '../../widgets/place_detail_sheet.dart';
import '../../widgets/search_panel.dart';
import '../../widgets/transit_routes_sheet.dart';
import '../../widgets/travel_mode_bar.dart';
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

/// 카테고리 필터 pill이 쓰는 (층·대분류·소분류)별 매장 수.
///
/// 층까지 들고 있는 이유는 "이 층 N곳" 안내 때문이다 — 선택한 카테고리가 지금
/// 보고 있는 층에 하나도 없으면 지도에 파란 강조가 아예 안 뜨는데, 그 상태와
/// "필터가 안 먹었다"를 사용자가 구분할 방법이 달리 없다.
typedef _CategoryEntry = CategoryCount;

class _MapShellScreenState extends State<MapShellScreen> {
  /// 상단 오버레이 사이 간격. 예전 top: 78 / top: 128 같은 고정 offset을
  /// 대신하는 유일한 값이다. 상단 바 높이가 상태에 따라 달라져도 이 간격은
  /// 그대로라 어느 모드에서든 같은 여백으로 보인다.
  static const _overlayGap = 8.0;

  late MapMode _mode = widget.initialMode;
  String _buildingId = demoBuildingId;

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

  /// 카테고리 선택을 바꾼다. 지도 강조는 상태를 내려받은 두 지도가 알아서
  /// 갱신하므로 여기서는 상태만 바꾼다.
  void _onCategorySelectionChanged(CategorySelection? selection) {
    if (_categorySelection == selection) return;
    setState(() => _categorySelection = selection);
  }

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

  /// 건물 밖 장소를 함께 찾을 기준점. 검색을 시작할 때 야외 지도에서 한 번
  /// 받아 둔다([_activateSearch]).
  ///
  /// **매 build마다 지도에서 읽지 않는다.** 지도 상태를 GlobalKey로 읽는 건
  /// build 중에 하기 나쁜 일이고(레이아웃 전에는 카메라가 없다), 검색 한 번
  /// 도중에 기준점이 흔들리면 같은 검색어의 결과가 타이핑 중에 바뀐다.
  LatLng? _outdoorSearchCenter;

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
    final reach = await _indoorKey.currentState?.reachFromCurrentPosition();
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

  void _setMode(MapMode mode) {
    if (mode == _mode) return;
    // 하단 바는 검색 막(barrier) 위에 있어 검색 중에도 눌린다. 화면이 바뀌는데
    // 결과 패널만 남아 있으면 안 되므로 여기서 함께 닫는다.
    _closeSearch();
    setState(() {
      _mode = mode;
      _placeInfo = null;
      // 홈으로 나가면 카테고리 필터도 푼다. 야외에서는 칩을 감추므로, 선택만
      // 남겨두면 사용자가 해제할 수단이 없는 채로 실내 오버레이에만 강조가
      // 남는다 — 왜 파랗게 칠해졌는지 알 방법이 없는 상태가 된다.
      if (mode == MapMode.outdoor) _categorySelection = null;
    });
    // '홈'을 누른 것은 "야외 지도를 보겠다"는 뜻이다. 야외 지도가 실내 진입
    // 오버레이를 켠 상태로 남아 있으면, 홈으로 왔는데 도면·실내 위치 아이콘이
    // 그대로 보이고 길찾기도 실내 앵커에서 출발한다. 오버레이를 닫고 카메라도
    // 야외 시야로 되돌린다.
    if (mode == MapMode.outdoor) {
      final outdoor = _outdoorKey.currentState;
      if (outdoor != null) unawaited(outdoor.returnToOutdoorView());
    }
    _dropIndoorOriginIfOutdoors();
    // 건물 안으로 들어온 시점에 미리 계산해 둔다. 매장을 지도에서 바로 눌러
    // 상세를 여는 흐름은 검색을 거치지 않으므로, 여기서 준비하지 않으면 상세에
    // 거리 줄이 비어 있다가 나중에야 채워진다.
    unawaited(_refreshReach());
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
  /// 상태다. 길찾기·카테고리 시트는 이 값으로 분기해야 한다 — 모드(_mode)만
  /// 보고 분기하면, 야외 지도 위에서 실내 도면을 훑는 동안 길찾기 후보가
  /// 매장이 아닌 건물 이름만 뒤져 "아무것도 안 나오는" 상태가 된다.
  bool get _indoorContextActive =>
      _mode == MapMode.indoor || _outdoorIndoorEntered;

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
    if (_mode == MapMode.indoor) return _indoorKey.currentState?.currentFloor;
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
    _indoorKey.currentState?.setInteractive(interactive);
  }

  /// 바텀시트가 떠 있는 동안 지도 제스처를 꺼서, 시트를 마우스 휠로
  /// 스크롤할 때 그 아래 지도까지 같이 스크롤/줌되지 않게 한다. 실내 지도는
  /// 웹에서 실제 DOM 캔버스(MapLibre)라 시트 위에서도 휠 이벤트가 새어나갈
  /// 수 있어서 필요하다.
  Future<T?> _withMapsLocked<T>(Future<T?> Function() showSheet) async {
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
    setState(() {
      _searchActive = true;
      // **실내 도면을 보는 중에도 바깥을 함께 찾는다.**
      //
      // 처음에는 [_indoorContextActive]일 때 껐다. "실내에서 화장실을 찾는
      // 사람에게 길 건너 편의점을 섞지 말자"는 뜻이었는데, 이 게이트가 기능을
      // 통째로 죽였다 — 폰에서는 실내 진입 임계 zoom이 화면 폭에 맞춰 16.8까지
      // 내려가는데(indoor_entry_zoom.dart) 야외 지도 초기 zoom이 17이라,
      // 건물 근처에서 앱을 켜면 **첫 프레임부터** 오버레이가 켜져 있다. 즉
      // 실기기에서는 이 조건이 거의 항상 참이라 바깥 검색이 한 번도 안 돌았다.
      //
      // 원래 걱정은 게이트가 아니라 **순서**로 이미 해결돼 있다. 바깥 결과는
      // 항상 실내 결과 **아래**에 별도 헤더를 달고 붙으므로, 실내에 답이 있으면
      // 사용자는 위부터 읽고 바깥은 눈에 들어오지도 않는다. 실내가 빈손일 때만
      // 바깥이 첫 줄이 되는데, 그건 정확히 바깥이 답인 경우다.
      _outdoorSearchCenter = _outdoorKey.currentState?.outdoorSearchCenter;
    });
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
    setState(() {
      _searchQuery = value;
      _searchSubmitTick++;
    });
  }

  Future<void> _onSearchStorePicked(PoiSearchResult store) async {
    _closeSearch();
    await _runSheetChain(() => _showStoreInfo(store, focusOnMap: true));
  }

  /// 검색 결과의 **건물 밖** 장소를 골랐을 때. 매장과 시트가 다르므로
  /// ([OutdoorPoiSheet]) 별도 흐름을 탄다.
  Future<void> _onSearchPoiPicked(OutdoorPoi poi) async {
    _closeSearch();
    await _runSheetChain(() => _showOutdoorPoiInfo(poi));
  }

  /// 야외 장소 시트. 매장 시트와 같은 규칙으로 "출발/도착을 실제로 골랐는가"를
  /// 돌려준다 — 부모 loop가 그 값으로 이전 시트로 되돌릴지 정한다.
  Future<bool> _showOutdoorPoiInfo(OutdoorPoi poi) async {
    // 목록에서 고른 장소는 지금 화면 어디에 있는지 알 수 없다. 시트가 덮기
    // 전에 지도를 그쪽으로 옮겨, 시트를 닫으면 바로 그 자리가 보이게 한다.
    await _outdoorKey.currentState?.focusPoint(poi.point);
    if (!mounted) return false;

    final action = await _withMapsLocked(
      () => OutdoorPoiSheet.show(
        context,
        poi: poi,
        onCloseAll: _requestCloseSheetChain,
        transitEnabled: transitRepository.isAvailable,
      ),
    );
    if (!mounted) return false;
    if (_closeSheetChainRequested) return true;
    if (action == null) return false;

    // 야외 좌표뿐인 후보다. 노드·층이 없으므로 [_startRoute]는 이 값을 실내
    // 라우팅으로 보내지 않고 도보 경로로 흘려보낸다. 좌표가 우리 건물 안일
    // 때의 보정도 [_startRoute]가 한다 — 진입점마다 하면 또 갈린다.
    final candidate = DirectionsCandidate(
      title: poi.name,
      subtitle: poi.address ?? '건물 밖 장소',
      point: poi.point,
    );
    switch (action) {
      case OutdoorPoiAction.setOrigin:
        setState(() => _selectedOrigin = candidate);
        final destination = _routeDraftDestination;
        if (destination != null) {
          await _startRoute(origin: candidate, destination: destination);
        } else {
          await _openDirections(presetOrigin: candidate);
        }
      case OutdoorPoiAction.setDestination:
        setState(() => _routeDraftDestination = candidate);
        final origin = _selectedOrigin;
        if (origin != null || _canRouteFromCurrentLocation) {
          await _startRoute(origin: origin, destination: candidate);
        }
      case OutdoorPoiAction.transit:
        setState(() => _routeDraftDestination = candidate);
        await _startTransitRoute(candidate);
    }
    return true;
  }

  /// 대중교통 경로를 물어보고, 후보 중 하나를 고르면 야외 지도에 그린다.
  ///
  /// 출발지는 야외 지도가 정한다([OutdoorMapBodyState.routeOriginPoint]) —
  /// 지도에서 찍은 출발 지점이 있으면 그것을, 없으면 GPS를 쓴다. 실내 앵커는
  /// 쓰지 않는다(건물 안 좌표를 보내면 정류장이 건물 반대편에서 잡힌다).
  Future<void> _startTransitRoute(DirectionsCandidate destination) async {
    final outdoor = _outdoorKey.currentState;
    // 명시적으로 고른 출발지라도 **실내 지점이면 쓰지 않는다.** 건물 안 좌표를
    // 보내면 TMAP이 그 좌표에서 가장 가까운 정류장을 찾는데, 건물이 크면 실제로
    // 나가야 하는 문의 반대편이 잡힌다. 그때는 GPS로 떨어뜨린다.
    final selectedOrigin = _selectedOrigin;
    final outdoorOrigin =
        (selectedOrigin != null &&
            selectedOrigin.floor == null &&
            selectedOrigin.nodeId == null)
        ? selectedOrigin.point
        : null;
    final origin = outdoorOrigin ?? outdoor?.routeOriginPoint;
    if (outdoor == null || origin == null) {
      _showSnack('현재 위치를 아직 못 잡았습니다. GPS 신호를 확인하거나 출발지를 직접 지정해주세요.');
      return;
    }

    final routes = await transitRepository.getTransitRoutes(
      origin: origin,
      destination: destination.point,
    );
    if (!mounted) return;

    // 결말마다 사용자가 할 행동이 다르다. 한 문구로 묶으면 700m 앞 목적지를
    // 두고 계속 재시도하게 된다([TransitRoutesStatus] 주석).
    switch (routes.status) {
      case TransitRoutesStatus.unavailable:
        _showSnack('대중교통 안내를 쓸 수 없습니다. TMAP 키 설정을 확인해주세요.');
        return;
      case TransitRoutesStatus.failed:
        _showSnack('대중교통 경로를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.');
        return;
      case TransitRoutesStatus.tooClose:
        // 걸어갈 수 있는 거리다. 안내 없이 끝내지 않고 도보 경로로 이어 준다 —
        // 사용자가 원한 것은 "저기까지 가는 방법"이지 "대중교통 그 자체"가 아니다.
        _showSnack('가까운 거리라 대중교통 경로가 없습니다. 도보로 안내합니다.');
        await _startRoute(origin: _selectedOrigin, destination: destination);
        return;
      case TransitRoutesStatus.noRoute:
        _showSnack('이 구간의 대중교통 경로를 찾지 못했습니다.');
        return;
      case TransitRoutesStatus.ok:
        break;
    }

    final picked = await _withMapsLocked(
      () => TransitRoutesSheet.show(
        context,
        routes: routes,
        destinationLabel: destination.title,
        onCloseAll: _requestCloseSheetChain,
      ),
    );
    if (!mounted || picked == null) return;
    await _outdoorKey.currentState?.showTransitRoute(
      picked,
      destination: destination.point,
      label: '${destination.title}까지',
      origin: origin,
    );
  }

  /// ETA 카드 라벨에서 목적지 이름만 뽑는다.
  ///
  /// 그 라벨은 화면용이라 꼬리가 붙어 있다 — 문 경유 안내에서는
  /// `이솝까지 · 남측 문 경유`다. 그대로 시트 제목에 넣으면
  /// "이솝까지 · 남측 문 경유까지 대중교통"이 된다.
  String _destinationNameFromEtaLabel(String label) {
    var name = label.split('·').first.trim();
    if (name.endsWith('까지')) {
      name = name.substring(0, name.length - '까지'.length).trim();
    }
    return name.isEmpty ? '목적지' : name;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 검색 결과의 **건물**을 골랐을 때. 그 건물 입구까지 안내한다.
  ///
  /// 되묻지 않는다. 예전에는 "건물까지 갈지, 안의 매장까지 갈지"를 시트로
  /// 물었는데, 그 질문 자체가 필요 없어졌다 — 밖에서도 건물 안 매장이 그대로
  /// 검색되므로([SearchPanel]), 매장이 목적지인 사용자는 애초에 매장 줄을
  /// 고른다. 건물 줄을 고른 사람은 건물이 목적지인 사람이다.
  ///
  /// 매장 줄을 고르면 [_showStoreInfo]를 거쳐 문을 경유하는 실내 안내로
  /// 이어진다([_startRoute]). 즉 어느 줄을 골랐느냐가 곧 의도이고, 화면은 그
  /// 의도를 다시 확인하지 않는다.
  void _onSearchBuildingPicked(Building building) {
    _closeSearch();
    final point = _buildingDestinationPoint(building);
    if (point == null) {
      // 좌표를 하나도 못 구한 건물이다. 안내를 못 하는 이유를 밝히지 않으면
      // 사용자는 결과를 눌렀는데 아무 일도 안 일어난 화면을 본다.
      _showSnack('이 건물의 위치를 아직 받아오지 못했습니다. 잠시 후 다시 시도해주세요.');
      return;
    }
    final candidate = DirectionsCandidate(
      title: building.name,
      subtitle: '건물 입구',
      point: point,
    );
    setState(() => _routeDraftDestination = candidate);
    final origin = _selectedOrigin;
    if (origin != null || _canRouteFromCurrentLocation) {
      unawaited(_startRoute(origin: origin, destination: candidate));
    }
  }

  /// "이 건물까지" 안내할 때의 도착 좌표.
  ///
  /// 야외 지도가 아는 **지상 출입구**를 우선한다 — 건물 중심을 도착점으로 주면
  /// TMAP 보행자 경로가 건물 안쪽을 향하다 아무 도로로나 스냅해, 실제로 들어갈
  /// 수 있는 문과 다른 면에 사용자를 내려놓는다. 야외 지도가 아직 그 건물을
  /// 로드하지 않았거나 문 데이터가 없으면 건물 응답의 출입구·외곽선 중심으로
  /// 떨어진다([Building.outdoorAnchor]). 그것마저 없으면 null.
  LatLng? _buildingDestinationPoint(Building building) {
    return _outdoorKey.currentState?.entrancePointFor(building.id) ??
        building.outdoorAnchor;
  }

  /// 매장 정보 시트를 띄운다. 검색 결과를 탭했을 때와 지도 위 매장 폴리곤을
  /// 직접 탭했을 때 모두 이 메서드를 거쳐 같은 시트가 뜨고, 출발지/도착지로
  /// 지정하면 그 매장을 채운 채로 길찾기 시트로 넘어간다.
  ///
  /// 반환값은 사용자가 출발/도착 액션을 실제로 골랐는지를 뜻한다. 저장된
  /// 장소 시트에서 넘어온 경우 호출자가 이 값을 보고 "그냥 닫힘"이면 다시
  /// 저장된 장소 시트로 돌려보내는 데 쓴다.
  Future<bool> _showStoreInfo(
    PoiSearchResult match, {
    bool focusOnMap = false,
  }) async {
    // 목록에서 고른 매장은 지금 화면 어디에 있는지 알 수 없다. 시트를 띄우기
    // 전에 지도를 그 매장으로 옮겨, 시트를 닫으면 바로 그 자리가 보이게 한다.
    // 지도 폴리곤을 직접 탭한 경우에는 옮기지 않는다 — 이미 보고 있는 매장을
    // 다시 중앙으로 끌어오면 방금 보던 주변 맥락이 사라진다.
    if (focusOnMap) {
      // 곧 올라올 시트 높이를 함께 넘겨, 매장이 시트 뒤가 아니라 그 위 영역
      // 한가운데에 놓이게 한다. 시트 높이를 바꾸면 카메라도 자동으로 따라온다.
      await _indoorKey.currentState?.focusStore(
        match,
        bottomSheetFraction: kPlaceDetailSheetInitialSize,
      );
      if (!mounted) return false;
    }
    final favorite = FavoritePlace.fromPoiSearchResult(
      match,
      buildingId: _buildingId,
    );
    // 시트를 띄우기 전에 구한다. 그래프·층 도면은 이미 받아 둔 것을 재사용하고
    // 다익스트라만 한 번 더 도는 정도라, 시트가 눈에 띄게 늦어지지 않는다.
    // 실패는 빈 목록이므로 시설 줄만 빠지고 시트는 그대로 열린다.
    final facilities =
        await _indoorKey.currentState?.nearbyFacilitiesFor(match) ?? const [];
    if (!mounted) return false;
    final action = await _withMapsLocked(
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
        // "이 매장에서" 가장 가까운 시설. 위 reach와 기준이 다르다.
        facilities: facilities,
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
      final tookAction = await _showStoreInfo(picked, focusOnMap: true);
      if (_closeSheetChainRequested || !mounted) return false;
      if (tookAction) return true;
    }
    return false;
  }

  /// **모든 검색 진입점이 함께 쓰는 후보 목록.**
  ///
  /// 상단 검색창과 길찾기 시트가 각자 검색을 구현하면 반드시 갈린다. 실제로
  /// 갈렸다 — 한쪽에는 건물 밖 장소(TMAP)가 있고 다른 쪽에는 없어서, 같은
  /// 검색어를 어디에 치느냐에 따라 나오는 곳이 달랐다. "무엇이 후보인가"를
  /// 정하는 자리는 하나뿐이어야 한다.
  ///
  /// 세 가지 출처를 이 순서로 합친다.
  ///
  /// 1. **건물 안 매장**(우리 백엔드) — 층·노드가 붙어 있어 문을 경유하는 실내
  ///    안내까지 이어진다. 밖에서 "루이비통"을 치는 사람의 목적지가 이것이다.
  /// 2. **건물**(우리 백엔드) — 입구까지 안내한다.
  /// 3. **건물 밖 장소**(TMAP POI) — 좌표까지 도보·대중교통.
  ///
  /// 건물 안을 보고 있으면 1번만 쓴다. 지금 서 있는 층 위에서 길을 찾는 중인데
  /// 길 건너 편의점이 후보에 섞이면, 정작 찾던 매장이 뒤로 밀린다.
  /// **모든 검색 진입점이 함께 쓰는 후보 목록.**
  ///
  /// 상단 검색창과 길찾기 시트가 각자 검색을 구현하면 반드시 갈린다. 실제로
  /// 갈렸다 — 한쪽에는 건물 밖 장소(TMAP)가 있고 다른 쪽에는 없어서, 같은
  /// 검색어를 어디에 치느냐에 따라 나오는 곳이 달랐다. "무엇이 후보인가"를
  /// 정하는 자리는 하나뿐이어야 한다.
  ///
  /// 세 가지 출처를 이 순서로 합친다.
  ///
  /// 1. **건물 안 매장**(우리 백엔드) — 층·노드가 붙어 있어 문을 경유하는 실내
  ///    안내까지 이어진다. TMAP POI로 흡수된 것은 여기서 빠진다.
  /// 2. **건물**(우리 백엔드) — 입구까지 안내한다.
  /// 3. **건물 밖 장소**(TMAP POI) — 좌표까지 도보·대중교통. 다만 우리 건물
  ///    안 매장을 가리키는 POI면 그 매장의 층·노드가 실려 실내까지 이어진다
  ///    ([mergeOutdoorResults]).
  ///
  /// 건물 안을 보고 있으면 1번만 쓴다. 지금 서 있는 층 위에서 길을 찾는 중인데
  /// 길 건너 편의점이 후보에 섞이면, 정작 찾던 매장이 뒤로 밀린다.
  Future<List<DirectionsCandidate>> _searchDirectionsCandidates(
    String query,
  ) async {
    final normalized = query.trim().toLowerCase();

    // 매장 검색은 **항상 건물 전체**를 뒤진다(currentFloorId를 넘기지 않는다).
    //
    // 예전에는 현재 층으로 좁히고 "전체 층에서 찾기" 토글로 넓히게 했다. 그런데
    // 길찾기를 여는 이유 자체가 대개 "지금 층에 없는 곳으로 가려고"라, 기본값이
    // 사용자 의도의 반대였다 — 찾는 매장이 결과에 아예 없어서 매번 토글을 켜야
    // 했다. 다른 층 결과에는 층 라벨이 부제로 붙으므로, 어느 층 매장인지는
    // 목록에서 그대로 읽힌다.
    final results = await destinationRepository.searchDestinations(
      _buildingId,
      query,
    );
    final buildings = await buildingRepository.getAllBuildings();
    // 매장 줄에 함께 적을 건물 이름. 조건 없이 항상 붙인다 — 상단 검색 패널과
    // 같은 규칙이고, 이유는 그쪽 주석(`_storeTile`)에 적었다.
    final buildingName = buildings
        .where((b) => b.id == _buildingId)
        .map((b) => b.name)
        .firstOrNull;
    List<DirectionsCandidate> storeCandidates() =>
        results.map((s) => _storeCandidate(s, buildingName)).toList();
    if (_indoorContextActive) return storeCandidates();

    // 밖에서는 **아무것도 안 쳤으면 아무것도 보여주지 않는다.**
    //
    // 건물 안에서는 빈 검색어가 "이 건물의 장소 전체 목록"이라는 뜻이라 그대로
    // 훑어볼 수 있다. 밖에서는 그 목록이 "여기서 갈 만한 곳"이 아니라 남의 건물
    // 내부 목록이라, 시트를 열자마자 띄우면 치지도 않은 답이 정해져 있는 화면이
    // 된다.
    if (normalized.isEmpty) return const [];

    // 건물 자체도 후보로 남기되 매장보다 뒤에 놓는다 — 밖에서 길찾기를 여는
    // 이유는 대개 특정 매장이다.
    //
    // **후보 좌표는 목록 응답만으로는 못 구한다.** `GET /buildings`는 id·이름·
    // 층 목록만 주고 출입구·외곽선은 상세(`/buildings/{id}`)에만 있다. 그래서
    // 야외 지도가 이미 상세로 받아 둔 값을 먼저 쓰고([_buildingDestinationPoint]),
    // 그마저 없으면 후보에서 뺀다 — 좌표 없는 후보는 눌러도 경로가 안 나온다.
    final buildingCandidates = <DirectionsCandidate>[];
    for (final building in buildings) {
      if (!building.name.toLowerCase().contains(normalized)) continue;
      final point = _buildingDestinationPoint(building);
      if (point == null) continue;
      buildingCandidates.add(
        DirectionsCandidate(
          title: building.name,
          subtitle: '${building.floors.length}개 층',
          point: point,
          // 이 후보가 건물이라는 표시. 목록의 아이콘(건물/핀)이 이 값으로 갈린다.
          buildingId: building.id,
        ),
      );
    }

    final merged = await _mergeOutdoorResults(
      query,
      results,
      buildings.map((b) => b.name).toList(),
    );
    final buildingNames = buildingCandidates
        .map((c) => collapseName(c.title))
        .toSet();
    // 우리 매장 줄은 **전부** 남긴다. 겹치는 POI 줄은 이미 빠져 있다
    // ([mergeOutdoorResults]) — 우리 줄에는 층·노드가 붙어 있어 실내까지
    // 안내되고, POI 줄은 건물 입구에서 끝나기 때문이다.
    return [
      ...merged.indoorStores.map((s) => _storeCandidate(s, buildingName)),
      ...buildingCandidates,
      for (final row in merged.outdoorRows)
        if (!buildingNames.contains(collapseName(row.poi.name)))
          _outdoorRowCandidate(row),
    ];
  }

  /// 매장 하나를 후보로 만든다. [buildingName]을 주면 부제에 함께 적는다.
  ///
  /// "스타벅스 리저브 / B2"만으로는 어느 건물의 스타벅스인지 알 수 없다. 밖에서
  /// 검색하면 길 건너 스타벅스도 함께 뜨고 그쪽에는 주소가 적혀 있어, 정작
  /// 실내까지 안내되는 우리 줄만 층 하나로 남아 가장 안 읽혔다.
  ///
  /// 조건 없이 항상 붙인다. 한때 "건물 안을 보고 있으면 생략"을 뒀다가 화면에서
  /// 통째로 사라졌다 — 실내 오버레이는 건물로 확대하기만 해도 켜지므로, 건물
  /// 근처에서 검색하는 흔한 경우가 전부 "건물 안"으로 판정됐다.
  DirectionsCandidate _storeCandidate(
    PoiSearchResult store, [
    String? buildingName,
  ]) => DirectionsCandidate(
    title: store.name,
    subtitle: buildingName == null
        ? store.floor
        : '$buildingName · ${store.floor}',
    point: store.point,
    nodeId: store.nodeId,
    floor: store.floor,
  );

  /// 바깥 줄 하나를 후보로 만든다.
  ///
  /// 여기까지 온 POI는 우리가 모르는 곳이다 — 우리 실내 데이터가 아는 가게를
  /// 가리키는 POI는 목록을 만들 때 이미 빠진다([mergeOutdoorResults]).
  DirectionsCandidate _outdoorRowCandidate(OutdoorSearchRow row) =>
      DirectionsCandidate(
        title: row.poi.name,
        subtitle: row.poi.address ?? '건물 밖 장소',
        point: row.poi.point,
      );

  /// 바깥 조회를 돌리고 우리 실내 결과와 합친다. 기준점을 못 구했거나 TMAP을
  /// 쓸 수 없으면 바깥 줄 없이 실내 결과만 돌려준다.
  Future<MergedOutdoorResults> _mergeOutdoorResults(
    String query,
    List<PoiSearchResult> indoorStores,
    List<String> buildingNames,
  ) async {
    final center = _outdoorKey.currentState?.outdoorSearchCenter;
    if (!outdoorPoiRepository.isAvailable || center == null) {
      return MergedOutdoorResults(const [], indoorStores);
    }

    final List<OutdoorPoi> pois;
    try {
      pois = await outdoorPoiRepository.searchNearby(query, center: center);
    } on Object {
      // 바깥 조회 실패로 후보가 통째로 비면 안 된다. 매장·건물은 이미 손에 있다.
      return MergedOutdoorResults(const [], indoorStores);
    }

    // 규칙은 도메인 함수가 갖고 있다(`domain/outdoor_poi_ranking.dart`).
    // 상단 검색 패널도 같은 함수를 부른다 — 여기서 다시 구현하면 또 갈린다.
    final outdoor = _outdoorKey.currentState;
    final merged = mergeOutdoorResults(
      pois: filterByNameRelevance(query, pois),
      indoorStores: indoorStores,
      isAtBuilding: (poi) => outdoor?.isAtIndoorBuilding(poi.point) ?? false,
      buildingNames: buildingNames,
    );
    // **중복 제거 결과를 로그로 남긴다.** 화면에서는 "겹쳐서 뺐다"와 "원래
    // 한 줄이었다"가 똑같이 보여서, 규칙이 통째로 안 도는 것을 눈으로 구분할
    // 수 없다. 실제로 이 자리를 세 번 잘못 짚었다.
    final dropped = pois.length - merged.outdoorRows.length;
    debugPrint(
      '[poi-merge] "$query" 바깥 ${pois.length}건 중 $dropped건이 '
      '우리 매장과 겹쳐 빠짐 (실내 후보 ${indoorStores.length}건, '
      '건물 이름 $buildingNames)',
    );
    return merged;
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
    //
    // 건물을 골랐든 매장을 골랐든 여기서 갈리지 않는다. 후보에 이미 답이
    // 들어 있기 때문이다 — 매장 후보에는 층·노드가 붙어 있어 [_startRoute]가
    // 문을 경유하는 실내 안내로 보내고, 건물 후보에는 없어서 입구까지의 도보
    // 안내로 간다. 상단 검색에서 같은 것을 골랐을 때와 결과가 같아야 하므로,
    // 두 진입점이 **같은 함수에서 갈라져야** 한다.
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

  /// 지금 고른 이동 수단. 도착지를 새로 정하면 거리를 보고 다시 정해진다.
  TravelMode _travelMode = TravelMode.walk;

  /// 걸어갈 만한 거리의 상한(m).
  ///
  /// 1.5 km는 보통 걸음으로 20분쯤이다. 그보다 멀면 대중교통을 먼저 보여 주는
  /// 편이 맞다 — 도보 안내를 지나쳐 다시 누르게 하는 것보다 낫고, 반대로 이
  /// 값을 더 낮추면 두 정거장 거리를 굳이 버스로 안내하게 된다.
  static const _walkableMeters = 1500.0;

  /// 거리를 보고 처음 보여 줄 이동 수단을 정한다.
  ///
  /// 출발점을 모르면(GPS 미확보) 도보로 둔다. 모르는 채로 대중교통을 부르면
  /// "현재 위치를 아직 못 잡았습니다"만 뜨고 끝나, 사용자는 수단을 고른 적도
  /// 없는데 실패 안내를 본다.
  TravelMode _defaultTravelMode(
    DirectionsCandidate? origin,
    DirectionsCandidate destination,
  ) {
    if (!transitRepository.isAvailable) return TravelMode.walk;
    final from = origin?.point ?? _outdoorKey.currentState?.routeOriginPoint;
    if (from == null) return TravelMode.walk;
    final meters = wgs84DistanceMeters(from, destination.point);
    return meters > _walkableMeters ? TravelMode.transit : TravelMode.walk;
  }

  /// 이동 수단 줄에서 직접 골랐을 때. 자동 선택을 덮어쓴다.
  Future<void> _onTravelModePicked(TravelMode mode) async {
    final destination = _routeDraftDestination;
    if (destination == null || _travelMode == mode) return;
    setState(() => _travelMode = mode);
    if (mode == TravelMode.transit) {
      await _startTransitRoute(destination);
      return;
    }
    await _startRoute(
      origin: _selectedOrigin,
      destination: destination,
      autoSelectMode: false,
    );
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
      _runSheetChain(() => _showStoreInfo(match));
      return;
    }
    _applyPickedCandidate(
      target,
      DirectionsCandidate(
        title: match.name,
        subtitle: match.floor,
        point: match.point,
        nodeId: match.nodeId,
        floor: match.floor,
      ),
    );
  }

  /// 야외 지도에서 매장이 아닌 **아무 지점**을 눌렀을 때. 좌표만 있는 후보라
  /// 노드·층이 없고, 상위 흐름은 이걸 걷기 경로의 끝점으로 쓴다.
  ///
  /// 야외에는 이름을 붙일 근거가 없어 좌표를 그대로 부제로 적는다. 사용자가
  /// 자기가 어디를 찍었는지 확인할 수 있는 유일한 단서다.
  void _onMapPointPick(LatLng point) {
    final target = _mapPickTarget;
    if (target == null) return;
    _applyPickedCandidate(
      target,
      DirectionsCandidate(
        title: target == DirectionsMapPickTarget.origin
            ? '지도에서 지정한 출발 위치'
            : '지도에서 지정한 도착 위치',
        subtitle:
            '${point.latitude.toStringAsFixed(5)}, '
            '${point.longitude.toStringAsFixed(5)}',
        point: point,
      ),
    );
  }

  /// 지도에서 고른 후보를 해당 칸에 넣고 경로 계산까지 이어 간다.
  ///
  /// 매장 탭과 좌표 탭이 **같은 함수를 지나야 한다.** 두 경로가 갈리면 한쪽에만
  /// "출발지가 바뀌었으니 거리 목록을 다시 계산한다" 같은 뒤처리가 붙어, 어느
  /// 쪽으로 골랐느냐에 따라 화면이 달라진다.
  void _applyPickedCandidate(
    DirectionsMapPickTarget target,
    DirectionsCandidate picked,
  ) {
    _stopPickingOnMap();
    // 강조 표시는 남겨두지 않는다 — 곧 경로와 핀이 그 자리를 대신한다.
    _indoorKey.currentState?.clearHighlight();
    _outdoorKey.currentState?.clearHighlight();

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
  /// 도착지가 정해졌을 때 **어떻게 갈지를 먼저 고른다.**
  ///
  /// [autoSelectMode]가 참이면 거리를 보고 수단을 정한다 — 걸어갈 만하면 도보,
  /// 아니면 대중교통. 사용자가 이동 수단 줄에서 직접 고른 경우에는 거짓으로
  /// 불러 그 선택을 덮지 않는다.
  ///
  /// 예전에는 이 판단이 없어서 10 km 떨어진 목적지에 "약 147분 / 10649m" 도보
  /// 안내가 먼저 떴다. 걸어서 두 시간 반 걸리는 길을 기본 답으로 내미는 셈이라,
  /// 사용자는 매번 그 화면을 지나 대중교통 버튼을 다시 눌러야 했다.
  Future<void> _startRoute({
    DirectionsCandidate? origin,
    required DirectionsCandidate destination,
    bool autoSelectMode = true,
  }) async {
    // 건물 안 매장이 목적지면 수단을 고르지 않는다. 그 안내는 "문을 경유해
    // 매장까지"라 도보 구간과 실내 구간이 한 몸이고([showOutdoorToIndoorRouteTo]),
    // 대중교통으로 바꾸면 그 실내 구간이 통째로 사라진다.
    if (autoSelectMode &&
        _mode == MapMode.outdoor &&
        destination.nodeId == null) {
      final mode = _defaultTravelMode(origin, destination);
      if (_travelMode != mode) setState(() => _travelMode = mode);
      if (mode == TravelMode.transit) {
        await _startTransitRoute(destination);
        return;
      }
    }

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
    //
    // 오버레이만으로는 부족하다 — **출발점이 실제로 건물 안에 있어야 한다.**
    // 오버레이는 건물을 확대하거나 탭하기만 해도 켜지므로, 밖에 서 있는
    // 사용자에게도 켜져 있다. 밖에서 건물 안 매장을 검색해 고른 뒤 건물로
    // 확대해 둔 상태가 정확히 그렇다.
    // 그때 실내 라우팅으로 보내면 시작 노드를 정할 실내 위치가 없어
    // "출발 위치를 먼저 지정해주세요"만 나오고 안내가 끝난다. 정작 그 사용자에게
    // 필요한 것은 아래의 "문을 경유해 매장까지"다. 그래서 출발지를 명시하지
    // 않았다면 실내 위치(PDR 앵커)가 잡혀 있을 때만 이 분기를 탄다.
    final indoorStartReady =
        indoorNavigationDriver.currentCalibration.canRenderPosition;
    if (_mode == MapMode.outdoor &&
        _indoorContextActive &&
        destination.floor != null &&
        destination.nodeId != null &&
        // origin이 있다면 그것도 실내 노드여야 실내 그래프로 이을 수 있다.
        // 건물 입구 같은 야외 후보라면 아래 걷기 경로로 흘려보낸다.
        (origin == null
            ? indoorStartReady
            : (origin.floor != null && origin.nodeId != null))) {
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

    // 건물 **밖에서** 건물 안 매장을 고른 경우다. 목적지 좌표로 곧장 걷기 경로를
    // 그리면 도착점이 건물 내부 좌표라 TMAP이 외벽 아무 곳으로나 안내하고, 거기서
    // 안내가 끝난다. 대신 가장 가까운 지상 출입구를 경유하도록 야외 화면에 맡긴다
    // — 실내 구간까지 미리 풀어 두었다가 건물에 들어가면 이어 붙인다.
    //
    // 출발지가 실내 지점이면 여기로 보내지 않는다. 그건 건물 안 두 지점 사이의
    // 이동이라 "밖에서 문으로 들어간다"는 전제가 성립하지 않는다. 반대로 지도에서
    // 찍은 야외 좌표는 그대로 넘긴다 — GPS가 안 잡히거나 다른 곳에서 출발하는
    // 경로를 보려는 경우이고, 그때도 들어가는 문은 있어야 한다.
    //
    // 조건에서 `!_indoorContextActive`를 뺀 것이 중요하다. 오버레이가 켜져 있어도
    // 실내 위치가 없으면 사용자는 아직 밖에 있고, 그 경우 위 분기가 이미 통과시켜
    // 여기까지 흘려보낸다. 오버레이 유무로 다시 막으면 "건물 안에서 매장 고르기"로
    // 들어온 사용자가 매장을 눌러도 안내가 시작되지 않는다.
    final outdoorOrigin =
        origin != null && origin.floor == null && origin.nodeId == null;
    if (_mode == MapMode.outdoor &&
        destination.floor != null &&
        destination.nodeId != null &&
        (origin == null || outdoorOrigin)) {
      await _outdoorKey.currentState?.showOutdoorToIndoorRouteTo(
        PoiSearchResult(
          name: destination.title,
          floor: destination.floor!,
          point: destination.point,
          nodeId: destination.nodeId,
        ),
        origin: outdoorOrigin ? origin.point : null,
      );
      return;
    }

    if (_mode == MapMode.outdoor) {
      // 야외 걷기 경로(TMAP)는 출발지도 야외 좌표여야 한다. 실내 지점이 출발지로
      // 남아 있으면(실내에서 "출발지로 설정"한 매장을 그대로 들고 나온 경우)
      // 버리고 GPS 현재 위치에서 시작한다 — 건물 안 좌표를 그대로 보내면 실내
      // 두 지점 사이에 직선이 그려진다. [_dropIndoorOriginIfOutdoors]가 상태도
      // 함께 비우지만, 그 경로를 타지 않은 호출(모드 전환 없이 들어온 경우)에도
      // 같은 규칙이 적용되도록 여기서 한 번 더 막는다.
      final indoorOrigin = origin?.floor != null || origin?.nodeId != null;
      // 도착 좌표가 **우리 건물 안**이면 문 좌표로 바꾼다.
      //
      // TMAP POI에는 백화점 입점 브랜드처럼 건물 안 매장이 섞여 있다. 건물 내부
      // 좌표를 도보 안내의 끝점으로 주면 TMAP이 가장 가까운 도로로 스냅해,
      // 실제로 들어갈 수 있는 문과 다른 면에 사용자를 내려놓는다.
      //
      // 여기 한 곳에서만 보정한다. 후보를 만드는 자리(상단 검색·길찾기 시트·
      // 야외 장소 시트)마다 하면 한 곳을 빠뜨리는 순간 그 진입점만 조용히
      // 달라진다 — 이 화면에서 반복된 실패가 정확히 그 모양이었다.
      //
      // 그 매장이 우리 실내 데이터에도 있다면 사용자는 애초에 목록 위쪽의 매장
      // 줄(층·노드가 붙어 실내까지 안내된다)을 골랐을 것이다. 여기까지 왔다는
      // 것은 우리가 그 매장을 모른다는 뜻이고, 그러면 문까지가 맞게 말할 수 있는
      // 최대치다.
      final endpoint =
          _outdoorKey.currentState?.entranceIfInsideBuilding(
            destination.point,
          ) ??
          destination.point;
      await _outdoorKey.currentState?.showRouteTo(
        endpoint,
        label: destination.title,
        origin: indoorOrigin ? null : origin?.point,
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
          () =>
              FavoritesSheet.show(context, onCloseAll: _requestCloseSheetChain),
        );
        if (_closeSheetChainRequested || picked == null || !mounted) return;
        final enriched = await _favoriteWithCategory(picked);
        if (_closeSheetChainRequested || !mounted) return;
        final tookAction = await _showStoreInfo(
          enriched.toPoiSearchResult(),
          focusOnMap: true,
        );
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
      () =>
          BuildingSwitcherSheet.show(context, selectedBuildingId: _buildingId),
    );
    if (selected == null || selected == _buildingId || !mounted) return;
    setState(() {
      _buildingId = selected;
      _placeInfo = null;
      // 건물이 바뀌면 카테고리 목록도 그 건물 것으로 다시 읽고, 이전 건물에서
      // 고른 선택은 버린다 — 새 건물에 없는 카테고리가 걸린 채로 남으면 지도에
      // 아무것도 강조되지 않는데 pill만 눌린 상태로 보인다.
      _categoryEntriesFuture = _loadCategoryEntries();
      _categorySelection = null;
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
      return;
    }
    if (_outdoorIndoorEntered) {
      _outdoorKey.currentState?.startLocationPlacement();
      return;
    }
    // 순수 야외에는 층도 PDR 앵커도 없다. 여기서 "위치 지정"이 뜻하는 것은
    // **출발 위치를 지도에서 직접 찍는 것**이다.
    //
    // GPS를 대신 덮어쓰지 않는다는 점이 실내와 다르고, 그게 의도다. 위치 마커와
    // 정확도 배지, 그리고 실내 진입/이탈 판정은 계속 진짜 GPS를 본다 — 수동
    // 좌표로 그 입력을 물들이면, 지금 검증하려는 진입 판정이 사람이 찍은 값을
    // 근거로 돌게 된다.
    setState(() => _mapPickTarget = DirectionsMapPickTarget.origin);
  }

  @override
  Widget build(BuildContext context) {
    final placeInfo = _placeInfo;
    final routeVisible = _mode == MapMode.outdoor
        ? _outdoorRouteVisible
        : _indoorRouteVisible;
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
                pickingPointOnMap: _mapPickTarget != null,
                onMapPointPick: _onMapPointPick,
                // 도보 안내 카드의 "대중교통". 야외 목적지는 무엇이든(매장·
                // 지도에서 찍은 지점·건물 입구) 이 카드를 지나므로, 진입점을
                // 여기 하나로 모은다.
                onTransitRequested: (destination, label) => unawaited(
                  _startTransitRoute(
                    DirectionsCandidate(
                      title: _destinationNameFromEtaLabel(label),
                      subtitle: '',
                      point: destination,
                    ),
                  ),
                ),
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
                onLocationAnchored: _onLocationAnchored,
                // 실내 화면과 같은 선택을 넘긴다. 야외 지도도 실내 진입
                // 오버레이가 켜지면 같은 도면을 그리므로, 안 넘기면 칩을
                // 눌러도 강조가 안 뜬다.
                categorySelection: _categorySelection,
                onFloorChanged: _onActiveFloorChanged,
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
              IndoorMapBody(
                key: _indoorKey,
                buildingId: _buildingId,
                onRouteVisibleChanged: (visible) =>
                    setState(() => _indoorRouteVisible = visible),
                onStoreTap: _onMapStoreTap,
                onLocationAnchored: _onLocationAnchored,
                onPlacingLocationChanged: (placing) {
                  if (_indoorPlacingLocation == placing) return;
                  setState(() => _indoorPlacingLocation = placing);
                },
                categorySelection: _categorySelection,
                onFloorChanged: _onActiveFloorChanged,
                outerOverlayKeys: [
                  _topBarKey,
                  _favoritesPillKey,
                  _categoryRowKey,
                  _searchPanelKey,
                  _bottomBarKey,
                  _mapPickHintKey,
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
                  showHamburger: _mode == MapMode.indoor,
                  onHamburgerTap: _onHamburgerTap,
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: _onSearchChanged,
                  onSubmitted: _onSearchSubmitted,
                  searchActive: _searchActive,
                  onCancelSearch: _closeSearch,
                  onDirectionsTap: _openDirections,
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

                // 이동 수단 줄. 도착지가 정해진 야외 안내에서만 뜬다.
                //
                // 검색 중에는 감춘다 — 그 자리는 결과 패널이 쓰고, 검색을 하는
                // 동안에는 아직 어디로 갈지도 안 정해졌다.
                if (_mode == MapMode.outdoor &&
                    _routeDraftDestination != null &&
                    !_searchActive)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, _overlayGap, 12, 0),
                    child: TravelModeBar(
                      selected: _travelMode,
                      transitEnabled: transitRepository.isAvailable,
                      onSelected: (mode) =>
                          unawaited(_onTravelModePicked(mode)),
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
                        currentFloorId: _activeIndoorFloor,
                        reachByNodeId: _reachByNodeId,
                        // 야외를 보고 있을 때만 값이 있다. 건물 안 도면을 보는
                        // 중이면 null이라 바깥 검색 자체가 돌지 않는다.
                        outdoorSearchCenter: _outdoorSearchCenter,
                        onOutdoorPoiPicked: (poi) =>
                            unawaited(_onSearchPoiPicked(poi)),
                        // 같은 가게가 두 줄로 뜨지 않게 하는 판정. 길찾기
                        // 후보 목록도 같은 규칙을 쓴다.
                        isInsideIndoorBuilding: (point) =>
                            _outdoorKey.currentState?.isAtIndoorBuilding(
                              point,
                            ) ??
                            false,
                      ),
                    ),
                  )
                // 길찾기 draft에서는 **접지 않고 내려온다.** 상단 바가 출발/도착
                // 두 줄로 커지면 이 Column이 그만큼 아래로 밀어 주므로 겹치지
                // 않는다. 한때 접어 뒀지만, 도착지를 정한 뒤에도 "그럼 저긴
                // 뭐였지" 하고 카테고리를 다시 훑는 흐름이 끊겼다.
                else
                  Padding(
                    padding: const EdgeInsets.only(top: _overlayGap),
                    // 대분류 줄과 소분류 줄을 세로로 쌓는다. 두 줄을 하나의 가로
                    // 스크롤에 넣으면 소분류가 대분류 오른쪽 끝에 붙어, 어느
                    // 대분류에 딸린 것인지 읽히지 않는다.
                    child: Column(
                      key: _categoryRowKey,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MapOverlayScrollRow(
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
                            // 노출한다. 기준은 모드(_mode)가 아니라
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
                                onSelectionChanged: _onCategorySelectionChanged,
                                onRetry: _reloadCategoryEntries,
                              ),
                            ],
                          ],
                        ),
                        // 소분류 줄과 개수 안내는 대분류를 고른 뒤에만 뜬다.
                        if (_indoorContextActive &&
                            _categorySelection != null) ...[
                          const SizedBox(height: _overlayGap),
                          _SubcategoryPillsRow(
                            entriesFuture: _categoryEntriesFuture,
                            selection: _categorySelection!,
                            activeFloor: _activeFloorLabel,
                            onSelectionChanged: _onCategorySelectionChanged,
                            onPointerOverChanged: (over) => over
                                ? _lockMaps(_mapLockOverlayHover)
                                : _unlockMaps(_mapLockOverlayHover),
                            onPointerDownChanged: (down) => down
                                ? _lockMaps(_mapLockOverlayTouch)
                                : _unlockMaps(_mapLockOverlayTouch),
                            onOpenList: (category) {
                              _runSheetChain(
                                () => _openCategoryStores(category),
                              );
                            },
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
              mode: _mode,
              onModeChanged: _setMode,
              onCalibrate: _onCalibrate,
              onPlaceLocation: _onPlaceLocation,
              placingLocation: _mode == MapMode.indoor
                  ? _indoorPlacingLocation
                  : (_outdoorPlacingLocation ||
                        _mapPickTarget == DirectionsMapPickTarget.origin),
              // 순수 야외에서도 노출한다. 예전에는 오버레이가 켜졌을 때만 켰는데,
              // 그 규칙은 이 버튼이 "층 위에 PDR 앵커를 찍는 것"만 뜻하던 시절의
              // 것이다. 이제 야외에서는 출발 위치를 지도에서 찍는 흐름을 열어
              // 주므로, GPS가 안 잡히거나 다른 지점에서 출발하는 경로를 보고 싶은
              // 사용자에게 눌러야 할 이유가 생겼다.
              showPlaceLocation: true,
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

/// 대분류를 고른 뒤 그 아래에 뜨는 소분류 pill 줄과 개수 안내.
///
/// 소분류가 2개 미만인 대분류(뷰티 — 화장품·향수 하나뿐)에서는 pill 줄을 아예
/// 만들지 않는다. 고를 것이 하나뿐인 줄은 탭을 한 번 더 요구할 뿐이다.
class _SubcategoryPillsRow extends StatelessWidget {
  const _SubcategoryPillsRow({
    required this.entriesFuture,
    required this.selection,
    required this.activeFloor,
    required this.onSelectionChanged,
    required this.onPointerOverChanged,
    required this.onPointerDownChanged,
    required this.onOpenList,
  });

  final Future<List<_CategoryEntry>> entriesFuture;
  final CategorySelection selection;

  /// 지금 보고 있는 층 라벨. null이면(순수 야외) 층 개념이 없으므로 건물 전체
  /// 기준으로 안내한다.
  final String? activeFloor;

  final ValueChanged<CategorySelection?> onSelectionChanged;
  final ValueChanged<bool> onPointerOverChanged;
  final ValueChanged<bool> onPointerDownChanged;

  /// "목록" 버튼. 지도 강조만으로는 매장 이름을 훑기 어려워, 기존 카테고리
  /// 매장 목록 시트로 넘어가는 길을 남겨 둔다.
  final ValueChanged<String> onOpenList;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_CategoryEntry>>(
      future: entriesFuture,
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <_CategoryEntry>[];
        if (entries.isEmpty) return const SizedBox.shrink();

        final options = subcategoryOptionsFor(
          selection.category,
          entries.map((entry) => (entry.category, entry.subcategory)),
        );
        final showPills = hasMeaningfulSubcategories(options);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showPills)
              _MapOverlayScrollRow(
                onPointerOverChanged: onPointerOverChanged,
                onPointerDownChanged: onPointerDownChanged,
                children: [
                  _SubcategoryPill(
                    label: '전체',
                    selected: selection.subcategory == null,
                    onTap: () => onSelectionChanged(
                      CategorySelection(category: selection.category),
                    ),
                  ),
                  for (final option in options) ...[
                    const SizedBox(width: 6),
                    _SubcategoryPill(
                      label: option.label,
                      selected: selection.subcategory == option.value,
                      // 이미 고른 소분류를 다시 누르면 대분류 전체로 되돌린다.
                      onTap: () => onSelectionChanged(
                        CategorySelection(
                          category: selection.category,
                          subcategory: selection.subcategory == option.value
                              ? null
                              : option.value,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            const SizedBox(height: 6),
            _CategoryFilterHint(
              entries: entries,
              selection: selection,
              activeFloor: activeFloor,
              onOpenList: () => onOpenList(selection.category),
            ),
          ],
        );
      },
    );
  }
}

/// 지금 필터에 몇 곳이 걸렸는지 알려주는 줄.
///
/// **이게 없으면 "이 층에 없음"과 "필터가 고장남"을 구분할 수 없다.** 강조
/// 방식이라 지도는 정상으로 보이는데 파란 칠만 안 뜨기 때문이다. 이 층에 없으면
/// 다른 층에 몇 곳이 있는지까지 알려줘, 사용자가 층을 옮길 근거를 준다.
class _CategoryFilterHint extends StatelessWidget {
  const _CategoryFilterHint({
    required this.entries,
    required this.selection,
    required this.activeFloor,
    required this.onOpenList,
  });

  final List<_CategoryEntry> entries;
  final CategorySelection selection;
  final String? activeFloor;
  final VoidCallback onOpenList;

  bool _matches(_CategoryEntry entry) {
    if (entry.category != selection.category) return false;
    final subcategory = selection.subcategory;
    return subcategory == null || entry.subcategory == subcategory;
  }

  @override
  Widget build(BuildContext context) {
    // 한 줄이 매장 하나가 아니라 (층·대분류·소분류) 묶음이라 **개수를 더해야**
    // 한다. 줄 수를 세면 "카페 53곳"이 "카페 8곳"(층 수)으로 나온다.
    final matched = entries.where(_matches);
    final total = matched.fold<int>(0, (sum, entry) => sum + entry.count);
    final floor = activeFloor;
    final onThisFloor = floor == null
        ? total
        : matched
              .where((entry) => entry.floor == floor)
              .fold<int>(0, (sum, entry) => sum + entry.count);

    final String text;
    if (total == 0) {
      // 데이터에 그 조합이 아예 없다. pill이 데이터에서 나오므로 정상 흐름에서는
      // 도달하지 않지만, 층 응답이 부분적으로 실패한 경우를 위해 남겨 둔다.
      text = '해당 매장을 찾지 못했습니다';
    } else if (floor == null) {
      text = '건물 전체 $total곳';
    } else if (onThisFloor > 0) {
      text = '$floor $onThisFloor곳 · 전체 $total곳';
    } else {
      text = '$floor에는 없습니다 · 다른 층 $total곳';
    }

    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onOpenList,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '목록',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 14,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 소분류 pill. 대분류 chip보다 한 단계 작고 아이콘이 없다 — 두 줄이 같은
/// 무게로 보이면 어느 쪽이 상위인지 읽히지 않는다.
class _SubcategoryPill extends StatelessWidget {
  const _SubcategoryPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : Colors.white,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.text,
            ),
          ),
        ),
      ),
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
                  Text(
                    isOrigin
                        ? '출발지로 지정할 매장을 지도에서 눌러주세요'
                        : '도착지로 지정할 매장을 지도에서 눌러주세요',
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
