import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/service_locator.dart';
import '../../domain/geo_transform.dart';
import '../../features/debug_mode/debug_mode.dart';
import '../../features/indoor_navigation/application/floor_map_matcher.dart';
import '../../features/indoor_navigation/contract/indoor_navigation_contract.dart';
import '../../features/indoor_navigation/debug/pdr_debug_device_info.dart';
import '../../features/indoor_navigation/debug/pdr_debug_session_recorder.dart';
import '../../features/indoor_navigation/debug/pdr_debug_session_share.dart';
import '../../features/indoor_navigation/application/corridor_position_tracker.dart';
import '../../features/indoor_navigation/application/corridor_tracking_session.dart';
import '../../features/indoor_navigation/application/guidance_trail_session.dart';
import '../../features/indoor_navigation/application/escalator_node_naming.dart';
import '../../features/indoor_navigation/application/escalator_transition_detector.dart';
import '../../features/indoor_navigation/application/indoor_location_estimate.dart';
import '../../domain/multi_floor_router.dart';
import '../../domain/route_guidance.dart';
import '../../domain/route_progress.dart';
import '../../models/building.dart';
import '../../models/building_graph.dart';
import '../../models/floor_graph.dart';
import '../../models/floor_plan.dart';
import '../../models/indoor_route.dart';
import '../../models/poi_search_result.dart';
import '../../theme/app_theme.dart';
import '../../widgets/category_map_filter.dart';
import '../../widgets/eta_card.dart';
import '../../widgets/floor_plan_view.dart';
import '../../widgets/floor_selector.dart';
import '../../widgets/map_overlay_tap_guard.dart';

const _walkingSpeedMetersPerSecond = 1.2;

// MapShellScreen이 지도 위에 얹는 상단 검색바/하단 홈-실내 버튼바가 지도를
// 가리는 두께. 축소 하한 계산이 "실제 보이는 영역" 기준으로 되려면 이만큼
// 잘라서 뷰포트로 넘겨야 한다. 각 위젯의 SafeArea 안쪽 padding + Material
// 내용 높이(48px IconButton, 44px 모드 세그먼트 등)를 합해 눈으로 재본 값.
const _mapShellTopChromePx = 68.0;
const _mapShellBottomChromePx = 112.0;

// IndoorMapBody 자신이 얹는 하단 오버레이(경로 ETA 카드) 높이.
// 층 selector는 이제 화면 왼쪽 하단(하단 바 옆)에 놓이므로 vertical fit에는
// 영향을 주지 않고 여기서 별도 상수로 잡지 않는다.
const _etaCardHeightPx = 130.0;

// 위치 지정 안내와 기압 디버그 칩을 상단 오버레이 아래에 놓기 위한 오프셋.
// SafeArea와 함께 써서 노치 기기에서 오버레이가 상태바만큼 내려앉는 것까지 따라간다.
//
// MapShellScreen이 실내에서 쌓는 **최악의 경우**를 위에서부터 더한 값이다
// (_overlayGap = 8, 상단 바 높이는 실기기 화면에서 실측):
//   출발/도착 두 줄 바 111 + 8 + 대분류 pill 30 + 8 + 소분류 pill 26
//   + 6 + 개수 안내 26 = 215
// 여기에 여유 21을 더해 236이다.
//
// **최악의 경우로 고정하는 이유**: 실제 높이는 네 가지로 변한다 — 상단 바가 한 줄
// (검색)이냐 두 줄(출발/도착)이냐, 소분류 줄이 뜨느냐(대분류에 소분류가 2개 이상),
// 개수 안내가 뜨느냐(카테고리 선택 여부). 상태마다 칩이 위아래로 튀면 값을 읽기
// 더 어렵고, 상위가 쌓는 실제 높이를 이 화면이 알 방법도 없다(다른 Stack이다).
// 그래서 한 자리에 고정하고 흔한 상태에서는 여백이 남는 쪽을 택한다.
//
// 값을 줄이기 전에: 상단 바가 두 줄이면서 소분류·개수 안내가 함께 뜬 화면을
// 반드시 확인할 것. 이 조합을 안 보고 고쳤다가 두 번 겹쳤다.
//
// 야외 화면의 동명 상수(132)와 **일부러 다르다.** 홈에서는 카테고리 칩을 아예
// 노출하지 않기로 해서 그쪽 상단 오버레이는 장소 pill 한 줄뿐이다.
const _placingHintTopPx = 236.0;

// 사용자가 매장 내부/건물 밖을 탭했을 때 멀리 떨어진 복도로 강제 스냅하지
// 않기 위한 상한이다. 입구나 매장 앞을 누르는 정상적인 경우에는 충분히
// 여유를 두되, 잘못 눌러 건물 반대편에서 PDR이 시작하는 일은 막는다.
const _maxPdrAnchorSnapDistanceM = 12.0;

/// 앵커 확정 전에 heading 수렴을 기다리는 최대 시간. 넘기면 경고만 띄우고
/// 진행한다 — 자기 왜곡이 심한 곳에서 앵커 확정 자체가 막히면 더 나쁘다.
const _headingSettleTimeout = Duration(seconds: 4);

// MapShellScreen이 route 표시 시 MapBottomBar(홈/실내 세그먼트)를 위로 리프트
// 하는 양. PDR 버튼도 이 값만큼 같이 올라야 홈/실내 버튼과 세로 정렬이 유지된다.
// map_shell_screen.dart의 _etaBarLiftHeight와 동일해야 한다.
const _bottomBarLiftPx = 92.0;

// MapBottomBar 내부의 하단 패딩(홈/실내 세그먼트 하단 여백). PDR 버튼을
// 같은 하단 여백으로 붙여야 두 버튼이 시각적으로 같은 baseline에 놓인다.
const _bottomBarInnerBottomPaddingPx = 14.0;

// 홈/실내 세그먼트의 왼쪽에 8px 간격으로 PDR 제어를 붙이는 right inset.
// iPhone 13 Pro 기준 세그먼트 폭(160px) + 화면 우측 여백(16px) + 간격(8px)이다.
const _pdrControlRightInsetPx = 184.0;

// 하단 바의 "위치 지정 / 위치 보정" 버튼 열 하단 offset(SafeArea 안쪽 기준).
// MapBottomBar Column 구조: [버튼 열] + spacer(10) + [ModeSegment(~45)] + padding(14).
// pill 하단을 이 값과 맞추면 층 선택기와 위 버튼들이 같은 층에 놓인 것처럼 보인다.
const _floorSelectorBottomOffset = _bottomBarInnerBottomPaddingPx + 45.0 + 10.0;

/// 실내 지도 본문(층 평면도 + 경로/매장 오버레이). 검색창·길찾기·건물 전환 같은
/// 공통 UI는 [MapShellScreen]이 상단/하단 바로 얹으므로 여기서는 다루지 않는다.
class IndoorMapBody extends StatefulWidget {
  const IndoorMapBody({
    super.key,
    required this.buildingId,
    this.onRouteVisibleChanged,
    this.onStoreTap,
    this.onPlacingLocationChanged,
    this.onLocationAnchored,
    this.outerOverlayKeys = const [],
    this.categorySelection,
    this.onFloorChanged,
  });

  /// 보고 있는 층이 바뀔 때 호출된다(최초 로드 포함). 상위(MapShellScreen)가
  /// 카테고리 필터의 "이 층 N곳" 안내를 이 신호로 다시 계산한다 — getter로만
  /// 읽으면 층이 바뀌어도 상위가 다시 그리지 않아 개수가 옛 층에 머문다.
  final ValueChanged<String?>? onFloorChanged;

  final String buildingId;

  /// 지도 위 카테고리 필터 pill에서 고른 카테고리. 상위(MapShellScreen)가
  /// 소유하고 실내·야외 양쪽에 같은 값을 내려, 두 화면의 강조가 어긋나지
  /// 않게 한다. null이면 강조하지 않는다.
  final CategorySelection? categorySelection;

  /// ETA 카드가 화면 최하단에 새로 나타나거나 사라질 때 호출된다.
  /// 상위(MapShellScreen)가 이 값으로 하단 공용 바를 그 위로 띄운다.
  final ValueChanged<bool>? onRouteVisibleChanged;

  /// 지도 위 매장 폴리곤을 탭하면 호출된다. 상위(MapShellScreen)가 검색
  /// 결과를 탭했을 때와 똑같이 매장 정보 시트를 띄운다.
  final ValueChanged<PoiSearchResult>? onStoreTap;

  /// "위치 지정" 흐름이 시작되어 지도 탭을 대기 중인지가 바뀔 때 호출된다.
  /// 상위(MapShellScreen)가 이 값으로 하단 바의 "위치 지정" 버튼을 눌린
  /// 상태로 표시해서, 사용자가 다음 동작(지도 탭)을 알 수 있게 한다.
  final ValueChanged<bool>? onPlacingLocationChanged;

  /// 사용자의 현재 위치가 새로 잡혔을 때 호출된다 — "위치 지정"으로 지도를
  /// 탭했을 때가 여기에 해당한다.
  ///
  /// 상위(MapShellScreen)는 이 신호로 **기억해둔 출발지 매장을 버린다.** 그러지
  /// 않으면 매장을 출발지로 지정해 길찾기를 한 뒤 위치를 다시 잡아도, 다음
  /// 길찾기가 방금 잡은 위치가 아니라 예전에 고른 매장에서 출발한다.
  final VoidCallback? onLocationAnchored;

  /// 상위(MapShellScreen)가 지도 위에 얹은 오버레이(검색창·저장한 장소 pill·
  /// 하단 공용 바 등)의 GlobalKey들. 이 영역 안의 탭은 뒤의 매장 선택으로
  /// 이어지지 않게 map click 처리에서 제외한다.
  final List<GlobalKey> outerOverlayKeys;

  @override
  State<IndoorMapBody> createState() => IndoorMapBodyState();
}

class IndoorMapBodyState extends State<IndoorMapBody> {
  bool _loading = true;
  Building? _building;
  String? _selectedFloor;
  FloorPlan? _floorPlan;
  FloorGraph? _floorGraph;
  String _mapCalibrationVersion = 'unversioned';
  IndoorRoute? _route;

  /// 층 간 경로일 때만 채워진다. [_route]는 이 다층 경로 중 지금 [_selectedFloor]
  /// 에 해당하는 세그먼트를 얹은 것이며, 층 selector로 다른 층 지도를 열면
  /// [_route]가 그 층 세그먼트로 갈아탄다(경로가 완전히 초기화되지 않음).
  MultiFloorRoute? _multiFloorRoute;
  PoiSearchResult? _routeDestination;
  bool _interactive = true;

  /// 지금 표시 중인 층 세그먼트 기준으로 해석한 경로 진행 상태.
  ///
  /// 경로가 없거나 PDR 위치가 없으면 null이다. 위치 추정에는 영향을 주지
  /// 않으며(단방향), 남은거리 표시와 진단에만 쓴다.
  RouteProgress? _routeProgress;

  /// 다음 진행률 계산의 지역 탐색 기준. 경로·층 세그먼트가 바뀔 때마다
  /// 반드시 null로 되돌려야 한다 — 이전 세그먼트 기준 진행거리를 그대로 두면
  /// 새 세그먼트에서는 창 밖 값이 되어 매 걸음 재획득이 켜진다.
  double? _lastRouteTraveledM;
  int? _lastRouteProgressAcceptedSteps;
  int? _lastRouteEvaluatedSteps;
  int _offRouteEvidenceUpdates = 0;
  int? _offRouteFirstEvidenceAtMs;
  bool _rerouteInFlight = false;
  int _lastRerouteAtMs = 0;

  // 지도 위에 얹은 오버레이(층 selector, PDR 버튼 등) 영역을 map click 처리기
  // 에서 배제하기 위한 GlobalKey들. MapLibre PlatformView가 Flutter gesture
  // arena를 우회하는 문제 때문에 오버레이 위 탭도 뒤의 매장까지 함께 클릭되는
  // 문제를 여기서 명시적으로 걸러낸다.
  final _floorSelectorKey = GlobalKey();
  final _pdrControlKey = GlobalKey();
  final _debugModeSettingsKey = GlobalKey();
  final _etaCardKey = GlobalKey();
  final _mapOverlayTapGuard = MapOverlayTapGuard();
  Offset? _etaClosePointerDown;

  /// 위치 지정 안내 배너. 오른쪽 상단 X를 누른 탭이 지도까지 새어들어가 배너
  /// 아래 지점에 앵커가 찍히는 것을 막는다 — 취소했는데 위치가 지정되면
  /// 사용자 입장에선 취소가 안 먹은 것으로 보인다.
  final _placingHintKey = GlobalKey();

  /// [globalPoint]가 지도 위 오버레이 영역 안이면 true — 그 좌표의 지도 탭은
  /// 매장 선택 처리를 건너뛰어야 한다. 자체 오버레이(층 selector, PDR)와
  /// 상위가 넘겨준 outer 오버레이(검색창·저장 장소·하단 바 등)를 모두 검사한다.
  bool _isTapOnMapOverlay(Offset globalPoint) {
    if (_mapOverlayTapGuard.consumeIfBlocked(globalPoint)) return true;

    for (final key in [
      _floorSelectorKey,
      _pdrControlKey,
      _debugModeSettingsKey,
      _placingHintKey,
      _etaCardKey,
      ...widget.outerOverlayKeys,
    ]) {
      final ctx = key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(globalPoint)) return true;
    }
    return false;
  }

  String? _highlightedStoreId;
  late final DebugPdrTrailState _pdrTrailState;
  final CorridorTrackingSession _corridorTrackingSession =
      CorridorTrackingSession();
  final GuidanceTrailSession _guidanceTrailSession = GuidanceTrailSession();
  StreamSubscription<PdrSnapshot>? _pdrSnapshotSub;
  StreamSubscription<CalibrationStatus>? _pdrCalibrationSub;
  StreamSubscription<AltitudeSample>? _pdrAltitudeSub;
  bool _placingPdrAnchor = false;
  PdrDebugSessionRecorder? _pdrDebugRecorder;

  /// 기압으로 에스컬레이터 층 이동을 판정한다. 화면이 층·그래프·보정 위치를
  /// 먹여 주고, 확정이 나오면 [_applyEscalatorTransition]이 층을 바꾼다.
  final EscalatorTransitionDetector _escalatorDetector =
      EscalatorTransitionDetector();

  /// 자동 층 전환 직전의 층·앵커. 되돌리기가 이 값으로 복원한다.
  String? _preTransferFloor;
  PdrAnchor? _preTransferAnchor;
  IndoorRoute? _preTransferRoute;
  MultiFloorRoute? _preTransferMultiRoute;
  PoiSearchResult? _preTransferDestination;

  /// 반 층을 지난 뒤 하차가 확정되기 전의 두 단계 전환 상태. 이 동안 화면은
  /// 새 층을 먼저 보여주되 마커는 도착 에스컬레이터 노드에 고정한다.
  ll.LatLng? _pendingTransferMarker;
  GraphNode? _pendingArrivalNode;
  bool _pendingArrivalRouteReady = false;

  /// 기압 샘플은 지도/그래프 로딩보다 빠르게 들어올 수 있다. 후보 시작→확정
  /// 또는 취소 순서를 Future 체인으로 직렬화해, 로딩 중 두 번째 상태가 앞질러
  /// 앵커를 엉뚱한 층에 적용하지 못하게 한다.
  Future<void> _floorTransitionQueue = Future<void>.value();

  /// 실내 화면 직접 진입 시 GPS 자동 초기화는 건물의 최초 층에서 한 번만 한다.
  /// 층 선택기를 누를 때마다 재시도하면 사용자가 다른 층을 구경한 것만으로 PDR
  /// 기준 층과 위치가 덮이므로, 같은 건물·초기 층 키를 다시 실행하지 않는다.
  String? _autoEstimateAttemptKey;

  /// 전환 적용 중 재진입 방지. 층 도면을 불러오는 동안 다음 기압 샘플이 또
  /// 확정을 내면 두 번 전환되면서 앵커가 어긋난다.
  bool _applyingFloorTransition = false;

  /// 디버그 칩에 보여줄 기압 관측 한 줄. 샘플이 5Hz까지 오므로 setState가 아니라
  /// notifier로 칩만 다시 그린다.
  final ValueNotifier<String?> _altimeterDebugText = ValueNotifier(null);

  /// FloorPlanView의 카메라를 직접 제어(회전/중심 이동)하기 위한 controller.
  /// 재보정 버튼이 첫 탭에서 사용자가 바라보는 방향으로 지도를 돌리고,
  /// 두 번째 탭에서 현재 위치를 화면 정중앙에 오게 하는 데 쓴다. 건물/층 변경
  /// 마다 FloorPlanView가 새 state로 재생성되지만 controller는 새 state에
  /// 자동 attach 되므로 이 필드는 한 번만 만들어 재사용한다.
  final _floorPlanController = FloorPlanController();

  /// 재보정 버튼 탭 카운터. 홀수 번째(1·3·5번째) 탭은 현재 위치를 화면 정중앙에
  /// 놓고, 짝수 번째(2·4·6번째) 탭은 사용자가 바라보는 방향(heading)에 맞춰
  /// 지도를 회전시킨다. 위치나 heading을 아직 몰라 실제 동작이 스킵된 탭은
  /// 카운트를 올리지 않아, 다음 탭이 원하는 동작을 이어가도록 한다.
  int _recalibrateTapCount = 0;
  bool _exportingPdrDebugJson = false;
  double _mapCameraBearingDeg = 0;
  final ValueNotifier<double> _mapCameraBearingNotifier = ValueNotifier(0);
  final GlobalKey _pdrShareButtonKey = GlobalKey();

  /// 디버그 설정은 야외 지도의 실내 진입 오버레이와 공유한다(service_locator).
  /// 화면마다 별도 인스턴스를 만들면 한쪽에서 켠 디버그 모드가 다른 쪽에
  /// 반영되지 않는다.
  final DebugModeController _debugModeController = debugModeController;

  /// 지금 이 실내 지도가 보여주는 층 이름(예: "B2"). 층이 아직 로드되지
  /// 않았거나 건물 로딩 실패 상태면 null. MapShellScreen이 길찾기·카테고리
  /// 시트의 검색을 현재 층으로 좁힐 때 참조한다. 상단 검색창은 층으로 좁히지
  /// 않고 건물 전체를 뒤지므로 이 값을 쓰지 않는다.
  String? get currentFloor => _selectedFloor;

  /// 검색·길찾기 시트가 지도 위에 떠 있는 동안 지도 제스처를 꺼서, 시트를
  /// 마우스 휠로 스크롤할 때 그 아래 지도까지 같이 움직이지 않게 한다.
  void setInteractive(bool value) {
    if (_interactive == value) return;
    setState(() => _interactive = value);
  }

  /// 앵커 배치 대기 상태를 바꿀 때는 항상 이 헬퍼로 지나 setState + 상위
  /// 알림을 함께 처리한다. 상위(MapShellScreen)는 이 알림을 받아 하단 바의
  /// "위치 지정" 버튼을 "눌린 상태"로 표시한다.
  void _setPlacingAnchor(bool value) {
    if (_placingPdrAnchor == value) return;
    setState(() => _placingPdrAnchor = value);
    widget.onPlacingLocationChanged?.call(value);
  }

  /// 매장 정보 시트가 닫히면 상위(MapShellScreen)가 호출해서 지도 위
  /// 강조 표시도 같이 지운다.
  void clearHighlight() {
    if (_highlightedStoreId == null) return;
    setState(() => _highlightedStoreId = null);
  }

  /// 목록(검색 결과·카테고리 매장 목록·저장한 장소)에서 고른 매장을 지도에서
  /// 보여 준다. 다른 층이면 그 층으로 옮긴 뒤 카메라를 매장으로 가져간다.
  ///
  /// 카메라를 여기서 직접 밀지 않고 [FloorPlanView]에 값으로 내려 주는 이유는
  /// 층 전환 타이밍이다 — 근거는 `FloorPlanView.focusTarget` 주석 참고.
  /// [bottomSheetFraction]은 곧 화면 아래를 덮을 시트의 높이 비율이다. 그만큼
  /// 매장을 위로 올려 시트 뒤에 숨지 않게 한다.
  Future<void> focusStore(
    PoiSearchResult store, {
    double bottomSheetFraction = 0,
  }) async {
    final floor = store.floor;
    if (floor.isNotEmpty && floor != _selectedFloor) {
      await _selectFloor(floor);
      if (!mounted) return;
    }
    setState(() {
      _highlightedStoreId = store.placeId;
      _focusTarget = store.point;
      _focusBottomSheetFraction = bottomSheetFraction;
      _focusTick++;
    });
  }

  /// 지도가 찾아가야 할 매장 위치와, 같은 매장을 다시 골라도 다시 움직이게
  /// 하는 카운터. 자세한 이유는 `FloorPlanView.focusTarget`·`focusTick` 주석.
  ll.LatLng? _focusTarget;
  int _focusTick = 0;
  double _focusBottomSheetFraction = 0;

  /// 백엔드 연결 실패 시 사용자에게 보여줄 메시지. null이면 정상 상태.
  /// 이게 없으면 fetch 예외가 조용히 삼켜져 로딩 스피너가 영원히 멈추지 않는다.
  String? _error;

  @override
  void initState() {
    super.initState();
    _debugModeController.addListener(_onDebugModeChanged);
    indoorLocationEstimateController.addListener(_onIndoorEstimateChanged);
    _pdrTrailState = DebugPdrTrailState.fromCurrent(
      snapshot: indoorNavigationDriver.currentSnapshot,
      calibration: indoorNavigationDriver.currentCalibration,
    );
    _pdrSnapshotSub = indoorNavigationDriver.snapshots.listen((snapshot) {
      _pdrDebugRecorder?.recordSnapshot(snapshot);
      if (mounted) {
        setState(() {
          _pdrTrailState.recordSnapshot(snapshot);
          _syncCorridorTracking(snapshot);
        });
      }
    });
    _pdrCalibrationSub = indoorNavigationDriver.calibration.listen((status) {
      if (mounted) {
        setState(() {
          _pdrDebugRecorder?.recordCalibration(status);
          _pdrTrailState.recordCalibration(status);
          _syncCorridorTracking(_pdrTrailState.snapshot);
        });
        if (status.phase == CalibrationPhase.calibrated ||
            status.phase == CalibrationPhase.uncalibrated) {
          _setPlacingAnchor(false);
        }
      }
    });
    _pdrAltitudeSub = indoorNavigationDriver.altitudeSamples.listen(
      _onAltitudeSample,
    );
    _loadBuilding();
  }

  @override
  void dispose() {
    _pdrSnapshotSub?.cancel();
    _pdrCalibrationSub?.cancel();
    _pdrAltitudeSub?.cancel();
    // 앱 전역 인스턴스라 dispose하지 않는다 — 여기서 버리면 야외 지도가
    // 같은 컨트롤러를 계속 구독하고 있다가 notifyListeners에서 죽는다.
    _debugModeController.removeListener(_onDebugModeChanged);
    indoorLocationEstimateController.removeListener(_onIndoorEstimateChanged);
    _mapCameraBearingNotifier.dispose();
    _altimeterDebugText.dispose();
    super.dispose();
  }

  /// 디버그 모드는 이제 **표시만** 바꾼다.
  ///
  /// 예전에는 디버그를 끄면 PDR 세션까지 정지시켰다. PDR이 상시 실행이 된
  /// 뒤에는 그 동작이 "선을 숨기려다 위치 추적이 끊기는" 결과가 되므로
  /// 세션에 손대지 않고 다시 그리기만 한다.
  void _onDebugModeChanged() {
    if (mounted) setState(() {});
  }

  void _onIndoorEstimateChanged() {
    if (mounted) setState(() {});
  }

  void _onMapCameraBearingChanged(double bearingDeg) {
    if (!bearingDeg.isFinite ||
        (bearingDeg - _mapCameraBearingDeg).abs() < 0.05) {
      return;
    }
    _mapCameraBearingDeg = bearingDeg;
    _mapCameraBearingNotifier.value = bearingDeg;
  }

  /// 실내 지도를 보는 동안 PDR 세션을 켜 둔다.
  ///
  /// anchor가 없으면 지도 위에 위치를 놓을 수 없지만, 센서를 미리 돌려두면
  /// 사용자가 위치를 지정하는 순간 heading이 이미 수렴하고 보폭 추정이 안정된
  /// 상태다. 예전처럼 버튼을 누른 직후부터 세션을 시작하면 그 워밍업 구간이
  /// 그대로 주행 초반 오차로 남았다.
  ///
  /// 층 인자는 지금 보고 있는 층으로 준다. 실제 기준점은 anchor 확정 시점에
  /// 잡히므로, 사용자가 다른 층을 훑어보다 위치를 지정해도 그 층이 이긴다.
  Future<void> _startPdrIfIdle() async {
    final floor = _selectedFloor;
    if (floor == null) return;
    if (indoorNavigationDriver.currentRuntimeStatus.state !=
        PdrRuntimeState.idle) {
      return;
    }
    // 권한이 거부된 상태에서 화면 진입마다 시작을 시도하면 degraded warning만
    // 반복해서 쌓인다. 다이얼로그를 띄우지 않고 상태만 확인해 건너뛴다.
    if (!await isPedometerPermissionGranted()) return;
    if (!mounted || _selectedFloor != floor) return;
    if (indoorNavigationDriver.currentRuntimeStatus.state !=
        PdrRuntimeState.idle) {
      return;
    }
    await indoorNavigationDriver.startGuidance(floorId: floor);
  }

  @override
  void didUpdateWidget(covariant IndoorMapBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.buildingId != widget.buildingId) {
      _autoEstimateAttemptKey = null;
      _route = null;
      _multiFloorRoute = null;
      _routeDestination = null;
      _highlightedStoreId = null;
      _loadBuilding();
    }
  }

  Future<void> _loadBuilding() async {
    setState(() {
      _loading = true;
      _error = null;
      // 건물을 바꾸는 동안 이전 건물의 층 평면도가 남아있으면, 아직 로딩
      // 중인데도 _buildBody가 "새 건물 ID + 이전 건물 평면도" 조합으로
      // FloorPlanView를 그려버린다 — 그 상태로 지도 위젯이 한 번 초기
      // 카메라를 잡아버리면(_fitToFootprint) 이후 진짜 평면도가 도착해도
      // 다시 맞추지 않아 엉뚱한 위치를 보여준 채로 굳는다(햄버거로 건물
      // 전환한 직후 지도가 빈 화면으로 보이는 원인). 새 평면도가 준비될
      // 때까지는 로딩 스피너만 보이도록 확실히 비워둔다.
      _floorPlan = null;
      _floorGraph = null;
      _mapCalibrationVersion = 'unversioned';
    });
    try {
      final building = await buildingRepository.getBuilding(widget.buildingId);
      if (!mounted) return;

      // floors.first가 아니라 initialFloor를 쓴다. 층 목록은 위층부터라
      // 지하층이 있는 건물에서 first는 최상층(6F)이다.
      final selectedFloor = building?.initialFloor;
      setState(() {
        _building = building;
        _selectedFloor = selectedFloor;
        _loading = false;
      });
      widget.onFloorChanged?.call(selectedFloor);
      if (selectedFloor != null) await _loadFloorPlan(selectedFloor);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '지도를 불러오지 못했습니다. 서버 연결을 확인해주세요.';
      });
    }
  }

  Future<void> _loadFloorPlan(String floor) async {
    try {
      final geojson = await buildingRepository.getFloorGeoJson(
        widget.buildingId,
        floor,
      );
      if (!mounted || geojson == null) return;
      final graphJson = geojson['navigation_graph'];
      final graph = graphJson is Map<String, dynamic>
          ? FloorGraph.fromJson(graphJson)
          : null;
      setState(() {
        _floorPlan = FloorPlan.fromJson(geojson);
        _floorGraph = graph;
        _mapCalibrationVersion =
            geojson['map_calibration_version'] as String? ?? 'unversioned';
        _syncCorridorTracking(_pdrTrailState.snapshot);
      });
      // 층 도면이 준비된 시점이 PDR을 켤 수 있는 가장 이른 지점이다. 이미
      // 돌고 있으면 아무것도 하지 않는다.
      unawaited(_startPdrIfIdle());
      unawaited(_initializeEstimatedLocationFromGps(floor, graph));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '지도를 불러오지 못했습니다. 서버 연결을 확인해주세요.');
    }
  }

  Future<void> _initializeEstimatedLocationFromGps(
    String floor,
    FloorGraph? graph,
  ) async {
    final buildingId = widget.buildingId;
    if (_autoEstimateAttemptKey == buildingId) return;
    _autoEstimateAttemptKey = buildingId;

    if (graph == null ||
        indoorNavigationDriver.currentCalibration.canRenderPosition) {
      return;
    }

    final existing = indoorLocationEstimateController.current;
    IndoorLocationEstimate? estimate;
    if (existing != null &&
        existing.buildingId == widget.buildingId &&
        existing.floorId == floor &&
        existing.isFresh(DateTime.now())) {
      estimate = existing;
    } else {
      final position = await requestIndoorEstimatePosition();
      if (!mounted ||
          widget.buildingId != buildingId ||
          _selectedFloor != floor ||
          indoorNavigationDriver.currentCalibration.canRenderPosition) {
        return;
      }
      if (position == null) return;
      estimate = estimateIndoorLocationFromGps(
        buildingId: buildingId,
        floorId: floor,
        graph: graph,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        observedAt: position.timestamp,
      );
      if (estimate == null) return;
      indoorLocationEstimateController.update(estimate);
    }
    final resolvedEstimate = estimate;

    // 마커는 estimate를 저장한 순간 바로 보인다. PDR 결합은 센서와 자북
    // heading이 준비된 경우에만 이어서 적용해, 자동 동작이 방향 선택 모달을
    // 띄우거나 임의 기준 heading으로 첫 경로를 만들지 않게 한다.
    await _startPdrIfIdle();
    if (!mounted ||
        _selectedFloor != floor ||
        indoorNavigationDriver.currentRuntimeStatus.state ==
            PdrRuntimeState.idle ||
        indoorNavigationDriver.currentCalibration.canRenderPosition) {
      return;
    }
    final deadline = DateTime.now().add(_headingSettleTimeout);
    while (!indoorNavigationDriver.isHeadingConverged &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted || _selectedFloor != floor) return;
    }
    final snapshot = indoorNavigationDriver.currentSnapshot;
    if (!canAutoAnchorEstimatedLocation(
      hasHeading: snapshot?.hasHeading ?? false,
      headingReferenceIsMagneticNorth:
          snapshot?.quality.features.headingReferenceIsMagneticNorth ?? false,
    )) {
      return;
    }

    await indoorNavigationDriver.confirmAnchorByPin(
      floorPointM: resolvedEstimate.localM,
      axes: fitPdrToFloorAxes(graph.nodes),
    );
  }

  Future<void> _selectFloor(String floor) async {
    // 층 간 경로가 활성이면 그 층의 세그먼트로 갈아타고, 없으면(단일 층 경로
    // 또는 경로 없음) 이전 경로/도착지 강조를 지운다.
    final multiRoute = _multiFloorRoute;
    final nextSegmentRoute = multiRoute?.segmentForFloor(floor)?.route;
    final hadRouteVisible = _hasActiveRoute;
    setState(() {
      _selectedFloor = floor;
      _floorPlan = null;
      _floorGraph = null;
      _mapCalibrationVersion = 'unversioned';
      if (multiRoute == null) {
        // 단일 층 경로였다면 다른 층 지도 위에 남아 있어도 의미가 없다.
        _route = null;
        _routeDestination = null;
      } else {
        // 다층 경로: 이 층 세그먼트가 있으면 그것으로 갈아타고, 이 층에
        // 세그먼트가 없으면 지도 위에는 그리지 않되 다층 경로 자체는 유지.
        _route = nextSegmentRoute;
      }
      // 세그먼트가 갈아타면 진행거리 기준점도 새 세그먼트 기준으로 다시
      // 잡아야 한다. 남겨두면 층을 바꾼 순간 남은거리가 튄다.
      _routeProgress = null;
      _lastRouteTraveledM = null;
      _lastRouteProgressAcceptedSteps = null;
      _lastRouteEvaluatedSteps = null;
      _offRouteEvidenceUpdates = 0;
      _offRouteFirstEvidenceAtMs = null;
      _highlightedStoreId = null;
    });
    if (hadRouteVisible != _hasActiveRoute) {
      widget.onRouteVisibleChanged?.call(_hasActiveRoute);
    }
    widget.onFloorChanged?.call(floor);
    // 세그먼트를 갈아탔으면 판정 기준 간선 집합도 바뀐다.
    if (multiRoute != null && nextSegmentRoute != null) {
      _recordRouteContext(nextSegmentRoute, isMultiFloor: true);
    }
    // 층 선택기(또는 라우팅 자동 층 전환)는 "다른 층 지도를 훑어보는" 동작이지
    // 사용자가 물리적으로 이동한 신호가 아니다. 그래서 PDR 세션을 건드리지
    // 않고 앵커도 그대로 둔다 — 다른 층에서는 anchor.floorId 게이팅으로 현재
    // 위치 마커가 자동으로 숨겨지고, 사용자가 원래 층으로 돌아오면 다시
    // 표시된다. 실제로 계단·엘리베이터로 이동해 새 층에서 위치를 다시 잡고
    // 싶다면 하단 바 "위치 지정" 버튼으로 직접 앵커 배치를 시작하면 된다.
    await _loadFloorPlan(floor);
  }

  /// 하단 바 재보정 버튼(위치 지정 오른쪽). 탭할 때마다 두 동작을 번갈아
  /// 수행한다:
  ///  1) 첫 탭: 사용자의 현재 위치를 화면 정중앙에 오게 카메라를 옮긴다.
  ///  2) 두 번째 탭: 사용자가 바라보는 방향(PDR heading)이 화면 위쪽에 오도록
  ///     지도를 회전한다.
  ///
  /// 위치/heading이 아직 없어 해당 동작을 수행할 수 없으면 안내만 띄우고
  /// 카운트를 올리지 않아, 다음 탭이 원하는 동작을 이어서 시도한다.
  Future<void> recalibrate() async {
    if (!_floorPlanController.isAttached) return;

    // 홀수 번째 탭(1,3,5...) → 중앙 정렬, 짝수 번째 탭(2,4,6...) → 회전.
    // 실제로 동작을 수행한 경우에만 카운트를 올린다.
    final isCenterAction = _recalibrateTapCount.isEven;
    if (isCenterAction) {
      final target = _pdrCurrentLocation ?? _pdrAnchorLocation;
      if (target == null) {
        _showPdrMessage('아직 현재 위치가 없습니다. 위치 지정 버튼으로 먼저 위치를 잡아주세요.');
        return;
      }
      await _floorPlanController.centerOn(target);
    } else {
      final heading = _pdrCurrentHeadingDeg;
      if (heading == null) {
        _showPdrMessage('아직 바라보는 방향을 알 수 없습니다. 위치 지정 후 조금 걸어 방향을 잡아주세요.');
        return;
      }
      // 회전도 내 위치를 중심으로 한다. 중앙 정렬 후 걸어간 뒤 회전을 누르면
      // 화면 중심과 내 위치가 이미 어긋나 있어, 중심을 그대로 두고 돌리면 내
      // 위치가 화면 가장자리로 밀려난다.
      await _floorPlanController.rotateToBearing(
        heading,
        center: _pdrCurrentLocation ?? _pdrAnchorLocation,
      );
    }
    _recalibrateTapCount++;
  }

  /// 하단 바의 "위치 지정" 버튼에서 호출된다. 지도를 사용하지 않고 건물에
  /// 들어와 자동 위치 추정이 아직 없을 때, 사용자가 지도 위 한 점을 탭해 자기
  /// 위치를 직접 지정하도록 앵커 배치 모드에 진입한다.
  ///
  /// PDR은 실내 지도를 보는 동안 이미 돌고 있으므로 여기서는 세션을 새로
  /// 만들지 않는다. 권한 거부 등으로 아직 idle이면 이 시점에 한 번 더 시작을
  /// 시도한다 — 사용자가 위치를 지정하려는 명확한 의사 표시이기 때문이다.
  /// 실제 탭 처리는 기존 [_onMapPressedForPdr]가 그대로 맡는다.
  Future<void> startLocationPlacement() async {
    final floor = _selectedFloor;
    final graph = _floorGraph;
    if (floor == null ||
        graph == null ||
        graph.nodes.isEmpty ||
        graph.edges.isEmpty) {
      _showPdrMessage('이 층은 위치 지정에 필요한 지도 정보가 아직 없습니다.');
      return;
    }
    // 위치를 다시 지정하는 것은 기준점을 새로 잡는 것이다. 세션을 이 층에 맞추고
    // 이전 anchor 기준의 궤적·보정 상태를 비우는 일은 모두 여기서 처리한다.
    if (!await _bindPdrSessionToFloor(floor, announceFailure: true)) return;
    _setPlacingAnchor(true);
    _showPdrMessage('지도에서 현재 서 있는 위치를 탭해 지정해주세요.');
  }

  /// 길찾기 시트에서 도착지를 고르면 호출된다. 출발과 도착이 같은 층이면
  /// 층별 그래프로 다익스트라를 돌리고, 다른 층이면 건물 전체 그래프
  /// (수직 전이 간선 포함)로 층 간 경로를 계산해 층별 세그먼트로 나눠 표시한다.
  ///
  /// [origin]을 주면 그 매장 입구 노드를 시작점으로 쓰고, 없으면 사용자의
  /// 현재 위치(PDR 또는 앵커) 층에서 가장 가까운 그래프 노드를 자동으로 고른다.
  Future<void> showRouteTo(
    PoiSearchResult destination, {
    PoiSearchResult? origin,
  }) async {
    // 출발점의 층을 결정한다. 명시적 출발지가 있으면 그 매장의 층, 없으면
    // 사용자 앵커의 층(현재 표시 중인 층이 아니다 — 사용자가 다른 층 지도를
    // 훑어보는 동안에도 앵커 층 기준으로 출발해야 한다).
    final startFloor = origin?.floor ?? _pdrTrailState.anchor?.floorId;
    final endFloor = destination.floor;
    final endNodeId = destination.nodeId;
    if (endNodeId == null) {
      _showPdrMessage('도착지 노드 정보가 없어 경로를 계산할 수 없습니다.');
      return;
    }
    if (startFloor == null) {
      _showPdrMessage('출발 위치를 먼저 지정해주세요. 하단 "위치 지정" 버튼으로 이 층 위에 시작점을 탭하면 됩니다.');
      return;
    }

    setState(() {
      _routeDestination = destination;
    });

    // 매장을 출발지로 골랐으면 현재 위치도 그 매장으로 옮긴다. 이걸 안 하면
    // 경로는 그 매장에서 뻗어 나가는데 위치 아이콘만 예전 자리(또는 아무 데도)
    // 남아, 사용자는 자기가 어디 있다고 표시되는지와 경로가 어긋난 화면을 본다.
    final originNodeId = origin?.nodeId;
    if (originNodeId != null && startFloor.isNotEmpty) {
      await _anchorAtStoreOrigin(
        floor: startFloor,
        nodeId: originNodeId,
        storePoint: origin!.point,
      );
      if (!mounted) return;
    }

    if (startFloor == endFloor) {
      await _computeAndShowSingleFloorRoute(
        floor: endFloor,
        endNodeId: endNodeId,
        explicitOriginNodeId: origin?.nodeId,
      );
    } else {
      await _computeAndShowMultiFloorRoute(
        startFloor: startFloor,
        endFloor: endFloor,
        endNodeId: endNodeId,
        explicitOriginNodeId: origin?.nodeId,
      );
    }
    if (!mounted) return;
    // 두 경로 계산 모두 마지막에 화면을 출발지 층으로 옮겨 두므로, 이 시점의
    // _floorGraph는 출발지 층 그래프다.
    await _maybeAutoAnchorAtOrigin(origin, startFloor: startFloor);
    if (!mounted) return;
    _warnIfAnchorOnAnotherFloor();
  }

  /// 앵커가 지금 보고 있는 층에 없으면 그 사실을 알린다.
  ///
  /// 이 상태에서는 현재 위치 마커·PDR 궤적·복도 보정·경로 진행률·층 전이 판정이
  /// **전부 조용히 꺼진다**(모두 `anchor.floorId == _selectedFloor`로 게이팅된다).
  /// 실측에서 앵커는 1F, 화면은 B2인 채로 한 세션을 다 걸었고, 로그에 보정 샘플이
  /// 0건이었다. 사용자 입장에서는 "아무것도 안 움직인다"로만 보이므로 이유를
  /// 말해 주고 재지정 손잡이를 함께 준다.
  void _warnIfAnchorOnAnotherFloor() {
    final anchor = _pdrTrailState.anchor;
    final floor = _selectedFloor;
    if (anchor == null || floor == null || anchor.floorId == floor) return;
    showDebugToast(
      context,
      message:
          '현재 위치가 ${anchor.floorId}에 잡혀 있어 $floor 지도에서는 위치와 이동이 '
          '표시되지 않습니다.',
      bottomOffset:
          _mapShellBottomChromePx +
          (_hasActiveRoute ? _etaCardHeightPx : 0) +
          12,
      actionLabel: '이 층에서 지정',
      onAction: () => unawaited(_resetAnchorForManualPlacement(floor)),
    );
  }

  /// 사용자가 길찾기에서 **출발지를 직접 골랐을 때** 그 노드를 앵커로 잡는다.
  ///
  /// 출발지를 명시적으로 고르는 행위는 "나는 지금 여기 있다"는 진술이다. 그
  /// 정보를 경로 계산에만 쓰고 버리면, 사용자는 방금 자기 위치를 알려줬는데도
  /// 마커가 뜨지 않아 "위치 지정"을 한 번 더 해야 한다.
  ///
  /// 다음 경우에는 잡지 않는다.
  /// - 출발지를 자동으로 고른 경우(현재 위치 기반). 이미 앵커가 있다는 뜻이고,
  ///   사용자가 위치를 새로 진술한 것도 아니다.
  /// - 같은 층에 이미 확정된 앵커가 있는 경우. 실시간 보정 위치가 매장 입구
  ///   노드보다 정확하므로 덮어쓰지 않는다.
  ///
  /// 잡은 뒤에는 되돌릴 손잡이를 함께 띄운다. 출발지가 실제 위치와 다르면
  /// 조용히 틀린 지점에서 안내가 시작되는데, 그건 사용자가 알아챌 수 있어야 한다.
  Future<void> _maybeAutoAnchorAtOrigin(
    PoiSearchResult? origin, {
    required String startFloor,
  }) async {
    final originNodeId = origin?.nodeId;
    if (origin == null || originNodeId == null) return;
    if (_selectedFloor != startFloor) return;
    final existing = _pdrTrailState.anchor;
    if (existing != null && existing.floorId == startFloor) return;
    final graph = _floorGraph;
    if (graph == null) return;
    final node = graph.nodes.where((n) => n.id == originNodeId).firstOrNull;
    if (node == null) return;
    if (indoorNavigationDriver.currentRuntimeStatus.state ==
        PdrRuntimeState.idle) {
      await _startPdrIfIdle();
      if (!mounted) return;
      if (indoorNavigationDriver.currentRuntimeStatus.state ==
          PdrRuntimeState.idle) {
        // 센서가 없으면 앵커를 잡아도 움직이지 않는다. 경로만 그린 채 둔다.
        return;
      }
    }

    setState(() {
      _pdrTrailState.beginNewSession();
      _corridorTrackingSession.reset();
      _routeProgress = null;
      _lastRouteTraveledM = null;
      _lastRouteProgressAcceptedSteps = null;
      _lastRouteEvaluatedSteps = null;
      _offRouteEvidenceUpdates = 0;
      _offRouteFirstEvidenceAtMs = null;
    });
    await _confirmPdrAnchor(
      PdrLocalPoint(node.xM, node.yM),
      floorId: startFloor,
    );
    if (!mounted) return;
    if (!indoorNavigationDriver.currentCalibration.canRenderPosition) return;
    showDebugToast(
      context,
      message: '${origin.name}에서 출발하는 것으로 보고 현재 위치를 잡았습니다.',
      bottomOffset:
          _mapShellBottomChromePx +
          (_hasActiveRoute ? _etaCardHeightPx : 0) +
          12,
      actionLabel: '위치 다시 지정',
      onAction: () => unawaited(_resetAnchorForManualPlacement(startFloor)),
    );
  }

  /// 자동으로 잡은 앵커를 버리고 사용자 지정 흐름으로 되돌린다.
  Future<void> _resetAnchorForManualPlacement(String floor) async {
    // changeFloor는 같은 층으로 불러도 걸음 세션과 앵커를 초기화하고
    // awaitingPin으로 되돌린다 — 앵커만 버리는 전용 명령이 따로 없다.
    await indoorNavigationDriver.changeFloor(floorId: floor);
    if (!mounted) return;
    await startLocationPlacement();
  }

  /// 같은 층 안에서 계산한 경로를 지도에 얹는다. 기존 흐름과 동일.
  Future<void> _computeAndShowSingleFloorRoute({
    required String floor,
    required String endNodeId,
    String? explicitOriginNodeId,
    bool preserveVisibleRoute = false,
  }) async {
    if (floor != _selectedFloor) {
      await _selectFloor(floor);
      if (!mounted) return;
    }
    final floorPlan = _floorPlan;
    if (floorPlan == null) return;

    if (!preserveVisibleRoute) {
      setState(() {
        // 새 목적지를 받을 때마다 초기화해서, 이번 경로가 계산되면 지도가
        // 전체 경로에 맞춰 다시 줌아웃되게 한다(FloorPlanView의 null→값 전환).
        _route = null;
        _multiFloorRoute = null;
        // 새 경로의 진행거리는 이전 경로와 아무 관계가 없다.
        _routeProgress = null;
        _lastRouteTraveledM = null;
        _lastRouteProgressAcceptedSteps = null;
        _lastRouteEvaluatedSteps = null;
        _offRouteEvidenceUpdates = 0;
        _offRouteFirstEvidenceAtMs = null;
      });
    }

    final startNodeId =
        explicitOriginNodeId ??
        _pickStartNodeIdOnFloor(floor, excludingNodeId: endNodeId);
    if (startNodeId == null) {
      _showPdrMessage('출발 위치를 먼저 지정해주세요. 하단 "위치 지정" 버튼으로 이 층 위에 시작점을 탭하면 됩니다.');
      widget.onRouteVisibleChanged?.call(false);
      return;
    }
    final computedRoute = await buildingRepository.getShortestRoute(
      widget.buildingId,
      floor,
      startNodeId,
      endNodeId,
    );
    if (!mounted) return;
    if (computedRoute == null) {
      setState(() => _route = null);
      widget.onRouteVisibleChanged?.call(false);
      _showPdrMessage('경로를 찾지 못했습니다. 다른 매장을 골라보거나 출발지를 다시 지정해주세요.');
      return;
    }
    final route = explicitOriginNodeId == null || preserveVisibleRoute
        ? _routeStartingAtCurrent(computedRoute, floor)
        : computedRoute;
    final seededProgress = _seedProgressAtCurrentRouteStart(route);
    final seededSteps = _pdrTrailState.snapshot?.preview.steps;
    setState(() {
      _route = route;
      _multiFloorRoute = null;
      _routeProgress = seededProgress;
      _lastRouteTraveledM = seededProgress?.traveledM;
      _lastRouteProgressAcceptedSteps = seededProgress == null
          ? null
          : seededSteps;
      _lastRouteEvaluatedSteps = null;
      _offRouteEvidenceUpdates = 0;
      _offRouteFirstEvidenceAtMs = null;
    });
    widget.onRouteVisibleChanged?.call(true);
    _startRouteRecording(route, isMultiFloor: false);
  }

  /// 새 경로가 확정되면 이 경로용 진단 세션을 준비한다.
  ///
  /// 이탈 재탐색(_rerouteFromCurrentPosition)은 **같은 길안내가 계속되는 것**이라
  /// 세션을 갈아타지 않고 판정 기준 간선만 새 경로로 갱신한다. 층 세그먼트를
  /// 갈아탈 때(_selectFloor)와 같은 처리다. 예전에는 여기서 이전 세션을 닫았고,
  /// 세션 종료는 종료 사유를 구분하지 않아 재탐색마다 "길안내가 끝났습니다"
  /// 안내가 떴다 — 아직 걷고 있는데 완료로 보이는 오해였고, 재탐색 전 주행
  /// 구간도 함께 버려졌다.
  void _startRouteRecording(IndoorRoute route, {required bool isMultiFloor}) {
    final continuingGuidance =
        _pdrDebugRecorder != null &&
        (_rerouteInFlight || _preTransferDestination != null);
    if (continuingGuidance) {
      _recordRouteContext(route, isMultiFloor: isMultiFloor);
      return;
    }
    // 목적지가 새로 정해진 경우다. 이전 세션 데이터는 여기서 버려지므로
    // 내보내기 안내를 띄우지 않는다(안내를 눌러도 꺼낼 게 없다).
    if (_pdrDebugRecorder != null) {
      _endRouteRecordingSession(announceExport: false);
    }
    final floor = _pdrTrailState.anchor?.floorId ?? _selectedFloor;
    if (floor != null) {
      _guidanceTrailSession.start(
        floorId: floor,
        result: _corridorTrackingSession.result,
      );
    }
    _beginRouteRecordingSession();
    _recordRouteContext(route, isMultiFloor: isMultiFloor);
  }

  /// 진행률 시계열을 사후에 검증할 수 있도록, 판정 기준이 된 경로를 디버그
  /// 파일에 함께 남긴다.
  void _recordRouteContext(IndoorRoute route, {required bool isMultiFloor}) {
    _pdrDebugRecorder?.recordRouteContext(
      destinationName: _routeDestination?.name,
      destinationNodeId: _routeDestination?.nodeId,
      floorId: _selectedFloor,
      edgeIds: route.edgeIds,
      routeDistanceM: route.distanceMeters,
      isMultiFloor: isMultiFloor,
    );
  }

  /// 서로 다른 층 사이 경로를 건물 전체 그래프로 계산해, 층별 세그먼트로
  /// 나눠 저장한다. 현재 화면(_selectedFloor)이 세그먼트를 가지고 있으면 그
  /// 세그먼트가 지도에 그려지고, 다른 층으로 전환해도 그 층의 세그먼트로
  /// 자동으로 갈아탄다.
  Future<void> _computeAndShowMultiFloorRoute({
    required String startFloor,
    required String endFloor,
    required String endNodeId,
    String? explicitOriginNodeId,
  }) async {
    final buildingGraph = await buildingRepository.getBuildingGraph(
      widget.buildingId,
    );
    if (!mounted) return;
    if (buildingGraph == null || buildingGraph.nodes.isEmpty) {
      _showPdrMessage('층 간 경로 계산에 필요한 그래프를 불러오지 못했습니다.');
      widget.onRouteVisibleChanged?.call(false);
      return;
    }

    final startNodeId =
        explicitOriginNodeId ??
        _pickStartNodeIdInBuildingGraph(
          graph: buildingGraph,
          startFloorName: startFloor,
          excludingNodeId: endNodeId,
        );
    if (startNodeId == null) {
      _showPdrMessage('출발 위치를 먼저 지정해주세요. 하단 "위치 지정" 버튼으로 이 층 위에 시작점을 탭하면 됩니다.');
      widget.onRouteVisibleChanged?.call(false);
      return;
    }

    final computedRoute = computeMultiFloorRoute(
      buildingGraph,
      startNodeId,
      endNodeId,
    );
    if (!mounted) return;
    if (computedRoute == null || computedRoute.isEmpty) {
      setState(() {
        _route = null;
        _multiFloorRoute = null;
      });
      widget.onRouteVisibleChanged?.call(false);
      _showPdrMessage('층 간 경로를 찾지 못했습니다. 엘리베이터/에스컬레이터 연결을 확인해주세요.');
      return;
    }
    final route = _multiRouteStartingAtCurrent(computedRoute, startFloor);
    final startSegment = route.segmentForFloor(startFloor)?.route;
    final seededProgress = startSegment == null
        ? null
        : _seedProgressAtCurrentRouteStart(startSegment);
    final seededSteps = _pdrTrailState.snapshot?.preview.steps;

    // 다층 경로 상태로 확정. 현재 표시 중인 층이 세그먼트를 가지고 있으면
    // 그 세그먼트를 화면에 그리고, 아니면 상단 층 selector로 갈아탈 때
    // _selectFloor가 그 층 세그먼트를 자동으로 얹는다.
    setState(() {
      _multiFloorRoute = route;
      _route = route.segmentForFloor(_selectedFloor ?? '')?.route;
      _routeProgress = _selectedFloor == startFloor ? seededProgress : null;
      _lastRouteTraveledM = _routeProgress?.traveledM;
      _lastRouteProgressAcceptedSteps = _routeProgress == null
          ? null
          : seededSteps;
      _lastRouteEvaluatedSteps = null;
      _offRouteEvidenceUpdates = 0;
      _offRouteFirstEvidenceAtMs = null;
    });
    widget.onRouteVisibleChanged?.call(true);
    final currentSegmentRoute = _route;
    if (currentSegmentRoute != null) {
      _startRouteRecording(currentSegmentRoute, isMultiFloor: true);
    }

    // 다층 경로를 처음 그릴 때는 언제나 출발지 층으로 화면을 이동한다.
    // 검색·시트로 목적지 층(또는 중간 층)을 훑어보다 도착을 확정한 순간에도
    // 사용자가 가장 먼저 봐야 하는 건 "내가 지금 있는 곳과 첫 걸음의 방향"이지
    // 목적지 층의 도착 지점이 아니다. 예전에는 "지금 층에 세그먼트만 있으면
    // 그대로 둔다"고 봤는데, 이러면 3층 매장을 훑던 뷰가 그대로 3층에 머물러
    // 위치 핀이 3층 에스컬레이터에 찍히는 오해를 만든다.
    if (_selectedFloor != startFloor) {
      await _selectFloor(startFloor);
    }
  }

  /// 사용자 위치에서 가장 가까운 그래프 노드를 시작점으로 고른다.
  ///
  /// 예전엔 "가장 가까운 매장의 centroid"를 기준으로 그 매장의 entrance node를
  /// 반환했는데(a) 매장 중심점은 실제 입구 위치와 크게 다를 수 있고 (b) 사용자가
  /// 복도에 서 있으면 옆 매장 입구가 시작점이 돼 경로가 실제 위치에서 뚝
  /// 떨어진 지점에서 시작하는 것처럼 보였다. 이제는 통행 그래프의 모든 노드
  /// (복도·교차점·매장 입구 등)에서 사용자의 floor-local 위치와 가장 가까운
  /// 노드를 고르므로 복도에 서 있으면 그 복도 노드가 자연스럽게 잡힌다.
  ///
  /// [floorName]은 시작점이 있어야 하는 층 라벨. 사용자의 앵커가 그 층에 있어야
  /// 위치를 알 수 있으므로, 앵커가 다른 층이면 null을 돌려준다. 위치를 모르는
  /// 상태에서는 도면 중심을 가짜 시작점으로 추정하지 않는다.
  String? _pickStartNodeIdOnFloor(String floorName, {String? excludingNodeId}) {
    final graph = _floorGraph;
    if (graph == null || graph.nodes.isEmpty) return null;
    // 현재 로드된 층 그래프가 요청 층과 다르면 이 헬퍼로는 답할 수 없다.
    if (_selectedFloor != floorName) return null;
    final current = _pdrFloorLocation();
    if (current == null) return null;

    return _nearestNodeId(
      graph.nodes,
      current.eastM,
      current.northM,
      excludingNodeId: excludingNodeId,
    );
  }

  /// 건물 전체 그래프에서 사용자의 앵커 층에 있는 노드 중 앵커 위치에 가장
  /// 가까운 노드를 고른다. 층 간 경로의 시작점.
  String? _pickStartNodeIdInBuildingGraph({
    required BuildingGraph graph,
    required String startFloorName,
    String? excludingNodeId,
  }) {
    final anchor = _pdrTrailState.anchor;
    if (anchor == null || anchor.floorId != startFloorName) return null;
    final current = _pdrFloorLocation() ?? anchor.anchorLocalM;

    // 앵커 층의 노드만 후보로 쓴다(앵커의 floorId는 사람이 보는 층 라벨이며,
    // 그래프 노드의 floorId는 내부 Floor.id다 — floorNamesById로 매핑한다).
    final floorId = graph.floorNamesById.entries
        .firstWhere(
          (entry) => entry.value == startFloorName,
          orElse: () => const MapEntry('', ''),
        )
        .key;
    if (floorId.isEmpty) return null;
    final candidates = graph.nodes
        .where((node) => node.floorId == floorId)
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    return _nearestNodeId(
      candidates,
      current.eastM,
      current.northM,
      excludingNodeId: excludingNodeId,
    );
  }

  String? _nearestNodeId(
    List<GraphNode> nodes,
    double xM,
    double yM, {
    String? excludingNodeId,
  }) {
    GraphNode? nearest;
    double? nearestDistanceSquared;
    for (final node in nodes) {
      if (node.id == excludingNodeId) continue;
      final dx = node.xM - xM;
      final dy = node.yM - yM;
      final distanceSquared = dx * dx + dy * dy;
      if (nearestDistanceSquared == null ||
          distanceSquared < nearestDistanceSquared) {
        nearestDistanceSquared = distanceSquared;
        nearest = node;
      }
    }
    return nearest?.id;
  }

  /// 다익스트라는 노드에서 시작하므로 현재 위치가 간선 중간이면 파란선이 몇 m
  /// 떨어진 노드에서 시작한다. 현재 보정 위치→시작 노드 연결을 경로 앞에 붙이고
  /// 현재 간선 id도 포함해, 마커에서 파란선이 시작하며 이탈 판정이 같은 간선
  /// 위에서 재탐색을 반복하지 않게 한다.
  IndoorRoute _routeStartingAtCurrent(IndoorRoute route, String floor) {
    final anchor = _pdrTrailState.anchor;
    final result = _corridorTrackingSession.result;
    final graph = _floorGraph;
    if (anchor == null ||
        anchor.floorId != floor ||
        _selectedFloor != floor ||
        result == null ||
        graph == null ||
        route.pointsLocalM.isEmpty) {
      return route;
    }
    final current = result.previewPosition;
    final first = route.pointsLocalM.first;
    final connectorM = math.sqrt(
      math.pow(current.eastM - first.x, 2) +
          math.pow(current.northM - first.y, 2),
    );
    final edgeId = result.currentEdgeId;
    if (connectorM < 0.05) {
      if (edgeId == null || route.edgeIds.contains(edgeId)) return route;
      return IndoorRoute(
        points: route.points,
        distanceMeters: route.distanceMeters,
        pointsLocalM: route.pointsLocalM,
        edgeIds: [edgeId, ...route.edgeIds],
      );
    }
    final wgs84 = fitFloorGeoTransform(
      graph.nodes,
    ).apply(current.eastM, current.northM);
    final edgeIds = route.edgeIds
        .where((id) => id != edgeId)
        .toList(growable: true);
    if (edgeId != null) edgeIds.insert(0, edgeId);
    return IndoorRoute(
      points: [ll.LatLng(wgs84.$1, wgs84.$2), ...route.points],
      distanceMeters: route.distanceMeters + connectorM,
      pointsLocalM: [
        LocalPoint(current.eastM, current.northM),
        ...route.pointsLocalM,
      ],
      edgeIds: edgeIds,
    );
  }

  RouteProgress? _seedProgressAtCurrentRouteStart(IndoorRoute route) {
    final result = _corridorTrackingSession.result;
    if (result == null || route.pointsLocalM.isEmpty) return null;
    final first = route.pointsLocalM.first;
    final distanceToStartM = math.sqrt(
      math.pow(result.previewPosition.eastM - first.x, 2) +
          math.pow(result.previewPosition.northM - first.y, 2),
    );
    // 현재 위치를 앞에 붙인 경로에만 0m 기준점을 심는다. 명시적 노드에서
    // 출발하는 경로가 멀리 있는데 억지로 0m로 잡으면 마커가 순간이동한다.
    if (distanceToStartM > 0.5) return null;
    return seedRouteProgressAtRouteStart(
      routePointsLocalM: route.pointsLocalM,
      routeEdgeIds: route.edgeIds.toSet(),
      currentEdgeId: result.currentEdgeId,
      headingDeg: result.previewHeadingDeg,
    );
  }

  MultiFloorRoute _multiRouteStartingAtCurrent(
    MultiFloorRoute route,
    String floor,
  ) {
    if (route.segments.isEmpty || route.segments.first.floorName != floor) {
      return route;
    }
    final original = route.segments.first;
    final updated = _routeStartingAtCurrent(original.route, floor);
    final addedDistance =
        updated.distanceMeters - original.route.distanceMeters;
    if (identical(updated, original.route)) return route;
    final first = IndoorRouteSegment(
      floorId: original.floorId,
      floorName: original.floorName,
      route: updated,
      transferModeToNext: original.transferModeToNext,
      transferPointsToNext: original.transferPointsToNext,
      transferDistanceMeters: original.transferDistanceMeters,
      transferCostMeters: original.transferCostMeters,
      transferEdgeId: original.transferEdgeId,
      transferFromNodeId: original.transferFromNodeId,
      transferToNodeId: original.transferToNodeId,
    );
    return MultiFloorRoute(
      segments: [first, ...route.segments.skip(1)],
      totalDistanceMeters: route.totalDistanceMeters + addedDistance,
      // 현재 위치까지의 연결선은 보행이라 거리와 비용이 같은 만큼 늘어난다.
      totalCostMeters: route.totalCostMeters + addedDistance,
    );
  }

  /// 사용자의 현재 층 위치(floor-local m)를 돌려준다. PDR 확정 위치가 있으면
  /// 그걸, 없으면 사용자가 지정한 앵커(같은 층일 때만)를 쓴다. 이 층에 아직
  /// 아무 위치도 없으면 null.
  PdrLocalPoint? _pdrFloorLocation() {
    final matched = _pdrMatchedFloorPath;
    if (matched.isNotEmpty) return matched.last;
    final anchor = _pdrTrailState.anchor;
    if (anchor != null && anchor.floorId == _selectedFloor) {
      return anchor.anchorLocalM;
    }
    return null;
  }

  void _clearRoute() {
    final pointerDown = _etaClosePointerDown;
    _etaClosePointerDown = null;
    if (pointerDown != null) {
      _mapOverlayTapGuard.retainPointerDown(pointerDown);
    }
    setState(() {
      _route = null;
      _multiFloorRoute = null;
      _routeDestination = null;
      _routeProgress = null;
      _lastRouteTraveledM = null;
      _lastRouteProgressAcceptedSteps = null;
      _lastRouteEvaluatedSteps = null;
      _offRouteEvidenceUpdates = 0;
      _offRouteFirstEvidenceAtMs = null;
      _guidanceTrailSession.clear();
    });
    widget.onRouteVisibleChanged?.call(false);
    // 한 번의 길안내가 여기서 끝난다. 세션을 닫고 내보내기 기회를 준다.
    _endRouteRecordingSession();
  }

  /// ETA 카드가 지금 화면에 노출돼야 하는지. 단일 층 경로는 이 층에 실제
  /// 폴리라인이 있을 때만 노출하지만, 다층 경로는 어느 층을 보고 있든 계속
  /// 노출한다 — 사용자가 "여기서 어디로 얼마 걸어가야 하는지" 상시 알기 위함.
  bool get _hasActiveRoute => _multiFloorRoute != null || _route != null;

  /// ETA에 쓸 **남은** 거리와 비용을 한 번에 계산한다.
  ///
  /// - `distanceM`: 사용자에게 "m 남음"으로 보이는 값. 수직 이동은 실제 수평 거리만
  ///   더한다(에스컬 약 20m, 엘리베 약 0~3m).
  /// - `costM`: 보행 등가 비용. 탑승·대기 시간이 들어 있어 보행 속도로 나누면 소요
  ///   시간이 된다. 거리 표시에는 쓰지 않는다 — 거리가 비용만큼 부풀어 보인다.
  ///
  /// PDR 진행률이 있으면 현재 위치 이후만 센다. 없으면(PDR 미실행, 보고 있는 층에
  /// 세그먼트가 없음 등) 경로 전체를 쓴다 — 이 경우엔 "출발 전 총량"이라 그대로 맞다.
  ({double distanceM, double costM}) _etaRemaining(
    IndoorRoute? currentFloorRoute,
  ) {
    final multi = _multiFloorRoute;
    final progress = _routeProgress;

    if (multi != null) {
      final total = (
        distanceM: multi.totalDistanceMeters,
        costM: multi.totalCostMeters,
      );
      if (progress == null) return total;
      // 지금 층 세그먼트의 남은 거리 + 아직 밟지 않은 이후 세그먼트 길이 합.
      // 현재 세그먼트를 못 찾으면(층 selector로 다른 층을 보는 중) 총량으로
      // 되돌린다 — 그 화면에서는 진행률이 지금 층과 무관하다.
      final currentIndex = _currentSegmentIndex(multi);
      if (currentIndex == null) return total;
      var distanceM =
          progress.remainingM +
          multi.segments[currentIndex].transferDistanceMeters;
      var costM =
          progress.remainingM + multi.segments[currentIndex].transferCostMeters;
      for (
        var index = currentIndex + 1;
        index < multi.segments.length;
        index++
      ) {
        final segment = multi.segments[index];
        distanceM +=
            segment.route.distanceMeters + segment.transferDistanceMeters;
        costM += segment.route.distanceMeters + segment.transferCostMeters;
      }
      return (distanceM: distanceM, costM: costM);
    }

    // 단층 경로에는 수직 이동이 없어 거리와 비용이 같다.
    final remainingM =
        progress?.remainingM ?? currentFloorRoute?.distanceMeters ?? 0;
    return (distanceM: remainingM, costM: remainingM);
  }

  ({List<ll.LatLng> remaining, List<ll.LatLng> completed}) _routeVisuals(
    IndoorRoute? route,
  ) {
    if (route == null) {
      return (remaining: const [], completed: const []);
    }
    final progress = _routeProgress;
    if (progress == null || route.pointsLocalM.length != route.points.length) {
      return (remaining: route.points, completed: const []);
    }
    final split = splitRouteAtProgress(route.pointsLocalM, progress);
    final graph = _floorGraph;
    if (split == null || graph == null) {
      return (remaining: route.points, completed: const []);
    }
    final transform = fitFloorGeoTransform(graph.nodes);
    List<ll.LatLng> convert(List<LocalPoint> points) => [
      for (final point in points)
        (() {
          final wgs84 = transform.apply(point.x, point.y);
          return ll.LatLng(wgs84.$1, wgs84.$2);
        })(),
    ];
    return (
      remaining: convert(split.remaining),
      completed: convert(split.completed),
    );
  }

  RouteGuidanceInstruction? _currentRouteGuidance(IndoorRoute? route) {
    if (route == null || route.pointsLocalM.length != route.points.length) {
      return null;
    }
    final segment = _multiFloorRoute?.segmentForFloor(_selectedFloor ?? '');
    final multi = _multiFloorRoute;
    final allowArrival =
        multi == null ||
        (segment != null &&
            identical(segment, multi.destinationSegment) &&
            _selectedFloor == _routeDestination?.floor);
    return buildRouteGuidance(
      localPoints: route.pointsLocalM,
      wgs84Points: route.points,
      progress: _routeProgress,
      transferMode: segment?.transferModeToNext,
      allowArrival: allowArrival,
    );
  }

  /// 지금 보고 있는 층이 다층 경로의 몇 번째 세그먼트인지. 없으면 null.
  int? _currentSegmentIndex(MultiFloorRoute multi) {
    final floor = _selectedFloor;
    if (floor == null) return null;
    for (var index = 0; index < multi.segments.length; index++) {
      if (multi.segments[index].floorName == floor) return index;
    }
    return null;
  }

  /// ETA 라벨. 다층 경로에서는 어떤 층/이동수단으로 가는지 요약을 덧붙여
  /// 사용자가 "지금 이 층에 안 그려진 이유"를 이해할 수 있게 한다.
  String _etaLabel(PoiSearchResult destination) {
    final multi = _multiFloorRoute;
    if (multi == null) return '${destination.name}까지';
    final buffer = StringBuffer('${destination.name}까지');
    for (var index = 0; index < multi.segments.length; index++) {
      final segment = multi.segments[index];
      buffer.write(
        index == 0 ? ' · ${segment.floorName}' : ' → ${segment.floorName}',
      );
      final transferMode = segment.transferModeToNext;
      if (transferMode != null) {
        buffer.write(transferMode == 'elevator' ? ' (엘리베이터)' : ' (에스컬레이터)');
      }
    }
    return buffer.toString();
  }

  /// 지금 표시 중인 층에 도착 핀을 찍어야 하면 그 좌표, 아니면 null.
  /// 단일 층 경로: 늘 도착지. 다층 경로: 마지막 세그먼트(목적지 층)일 때만.
  ll.LatLng? _destinationPinForCurrentFloor(
    IndoorRoute? currentFloorRoute,
    PoiSearchResult? destination,
  ) {
    final multi = _multiFloorRoute;
    if (multi != null) {
      if (multi.destinationSegment.floorName != _selectedFloor) return null;
      final points = multi.destinationSegment.route.points;
      if (points.isNotEmpty) return points.last;
      return destination?.point;
    }
    if (currentFloorRoute != null && currentFloorRoute.points.isNotEmpty) {
      return currentFloorRoute.points.last;
    }
    return destination?.point;
  }

  List<PdrLocalPoint> get _pdrConfirmedFloorPath {
    final snapshot = _pdrTrailState.snapshot;
    final anchor = _pdrTrailState.anchor;
    final graph = _floorGraph;
    if (snapshot == null ||
        anchor == null ||
        anchor.floorId != _selectedFloor ||
        graph == null ||
        graph.nodes.isEmpty) {
      return const [];
    }
    final pdrToFloor = FloorCoordinateTransform(anchor);
    return snapshot.path.map(pdrToFloor.toFloor).toList(growable: false);
  }

  List<PdrLocalPoint> get _pdrRawFloorPath {
    final snapshot = _pdrTrailState.snapshot;
    final anchor = _pdrTrailState.anchor;
    final graph = _floorGraph;
    if (snapshot == null ||
        anchor == null ||
        anchor.floorId != _selectedFloor ||
        graph == null ||
        graph.nodes.isEmpty) {
      return const [];
    }
    final pdrToFloor = FloorCoordinateTransform(anchor);
    return snapshot.reconciledPreviewPath
        .map(pdrToFloor.toFloor)
        .toList(growable: false);
  }

  List<PdrLocalPoint> get _pdrRoninFloorPath {
    final snapshot = _pdrTrailState.snapshot;
    final anchor = _pdrTrailState.anchor;
    final graph = _floorGraph;
    if (snapshot == null ||
        !snapshot.ronin.supported ||
        anchor == null ||
        anchor.floorId != _selectedFloor ||
        graph == null ||
        graph.nodes.isEmpty) {
      return const [];
    }
    final pdrToFloor = FloorCoordinateTransform(anchor);
    return snapshot.ronin.path.map(pdrToFloor.toFloor).toList(growable: false);
  }

  /// 원본과 분리해 세션 동안 누적한 복도 제약 경로다. build 시점마다 confirmed
  /// 전체를 다시 매칭하지 않아 현재 edge·heading bias·회전 증거가 유지된다.
  List<PdrLocalPoint> get _pdrMatchedFloorPath {
    final anchor = _pdrTrailState.anchor;
    if (anchor == null || anchor.floorId != _selectedFloor) return const [];
    return _corridorTrackingSession.result?.correctedPath ?? const [];
  }

  List<PdrLocalPoint> get _pdrMatchedPreviewFloorPath {
    final anchor = _pdrTrailState.anchor;
    if (anchor == null || anchor.floorId != _selectedFloor) return const [];
    final preview = _corridorTrackingSession.result?.previewPath ?? const [];
    return preview.length >= 2 ? preview : const [];
  }

  Set<String> get _pdrMatchedEdgeIds {
    if (!_hasMeaningfulPdrMovement(_pdrConfirmedFloorPath)) return const {};
    final edgeId = _corridorTrackingSession.result?.currentEdgeId;
    return edgeId == null ? const {} : {edgeId};
  }

  /// 세션 시작 직후에는 원점 한 개만 가장 가까운 간선에 투영되면서, 사용자가
  /// 아직 걷지 않았는데도 그 간선 전체가 청록색으로 강조될 수 있다. 실제 PDR
  /// 이동이 생긴 뒤에만 활성 간선을 표시한다.
  bool _hasMeaningfulPdrMovement(List<PdrLocalPoint> path) {
    if (path.length < 2) return false;
    var distanceM = 0.0;
    for (var index = 1; index < path.length; index++) {
      final dx = path[index].eastM - path[index - 1].eastM;
      final dy = path[index].northM - path[index - 1].northM;
      distanceM += math.sqrt(dx * dx + dy * dy);
      if (distanceM >= 0.2) return true;
    }
    return false;
  }

  ll.LatLng? get _pdrCurrentLocation {
    final graph = _floorGraph;
    final result = _corridorTrackingSession.result;
    if (graph == null || result == null) return null;
    final progress = _routeProgress;
    final projected = progress?.projectedPoint;
    final canFollowGuidance =
        _hasActiveRoute &&
        projected != null &&
        result.state != CorridorTrackingState.uncertain &&
        (progress!.onRouteEdge ||
            (!progress.reacquired &&
                progress.offsetM < 4 &&
                _offRouteEvidenceUpdates < 3));
    // 센서·복도 보정의 원본은 그대로 두고 화면 마커만 수용된 경로 투영점을
    // 따른다. 이탈 증거가 확정되면 원시 보정 위치로 돌아가 재탐색 결과를
    // 기다리므로 실제 이탈을 파란선 위에 숨기지 않는다.
    final current = canFollowGuidance
        ? PdrLocalPoint(projected.x, projected.y)
        : result.previewPosition;
    final wgs84 = fitFloorGeoTransform(
      graph.nodes,
    ).apply(current.eastM, current.northM);
    return ll.LatLng(wgs84.$1, wgs84.$2);
  }

  ll.LatLng? get _freshGpsIndoorEstimate {
    final estimate = indoorLocationEstimateController.current;
    if (estimate == null ||
        estimate.buildingId != widget.buildingId ||
        estimate.floorId != _selectedFloor ||
        !estimate.isFresh(DateTime.now())) {
      return null;
    }
    return estimate.wgs84;
  }

  double? get _pdrCurrentHeadingDeg {
    final snapshot = _pdrTrailState.snapshot;
    final anchor = _pdrTrailState.anchor;
    if (snapshot == null || anchor == null || !snapshot.hasHeading) return null;
    final transform = FloorCoordinateTransform(anchor);
    final correctedFloorHeading =
        _corridorTrackingSession.result?.previewHeadingDeg;
    return correctedFloorHeading == null
        ? normalizePdrBearing(snapshot.walkingHeadingDeg + anchor.rotationDeg)
        : transform.floorBearingToMapBearing(correctedFloorHeading);
  }

  /// 기압 샘플 한 건을 판정기에 넣고, 로그에 남기고, 확정이면 층을 옮긴다.
  void _onAltitudeSample(AltitudeSample sample) {
    if (!mounted) return;
    // 조기 전환 뒤 화면은 목적 층을 먼저 보여주지만 판정기는 탑승 층의
    // baseline·노드 허가를 끝까지 유지해야 한다. 후보가 닫힌 뒤에만 화면
    // 컨텍스트를 다시 주입한다.
    if (_escalatorDetector.pendingTransition == null) {
      _escalatorDetector.updateContext(
        floorLabel: _selectedFloor,
        graph: _floorGraph,
        floorLabels: _building?.floors ?? const [],
      );
    }
    final transition = _escalatorDetector.onAltitude(sample);
    final started = _escalatorDetector.takeStartedTransition();
    final cancelled = _escalatorDetector.takeCancelledTransition();

    final recorder = _pdrDebugRecorder;
    if (recorder != null) {
      recorder.recordAltimeterStatus(indoorNavigationDriver.altimeterStatus);
      recorder.recordAltitudeSample(
        sample,
        smoothedM: _escalatorDetector.smoothedAltitudeM,
        baselineM: _escalatorDetector.baselineM,
        deltaM: _escalatorDetector.deltaM,
        armed: _escalatorDetector.isArmed,
        candidate: _escalatorDetector.hasCandidate,
      );
    }
    // 레코더가 없어도 이벤트는 비운다. 안 그러면 다음 길안내 세션의 로그에
    // 지난 세션 판정이 섞여 들어간다.
    final events = _escalatorDetector.takeEvents();
    if (events.isNotEmpty) recorder?.recordFloorTransitionEvents(events);

    _altimeterDebugText.value = _debugModeController.enabled
        ? _altimeterDebugLine(sample)
        : null;

    if (started != null) {
      _enqueueFloorTransition(() => _beginEscalatorTransition(started));
    }
    if (cancelled != null) {
      _enqueueFloorTransition(() => _cancelEscalatorTransition(cancelled));
    }
    if (transition != null) {
      _enqueueFloorTransition(() => _completeEscalatorTransition(transition));
    }
  }

  void _enqueueFloorTransition(Future<void> Function() action) {
    _floorTransitionQueue = _floorTransitionQueue
        .then((_) => mounted ? action() : Future<void>.value())
        .onError((Object error, StackTrace stackTrace) {
          debugPrint('floor transition failed: $error\n$stackTrace');
        });
  }

  /// 디버그 칩 한 줄. 판정이 안 걸리는 이유를 현장에서 눈으로 가리기 위한 값이다.
  String _altimeterDebugLine(AltitudeSample sample) {
    final delta = _escalatorDetector.deltaM;
    final deltaText = delta == null ? '—' : '${delta.toStringAsFixed(2)}m';
    final state = _escalatorDetector.hasCandidate
        ? '후보'
        : (_escalatorDetector.isArmed ? '허가' : '대기');
    return '기압 ${sample.pressureHpa.toStringAsFixed(2)}hPa · Δ$deltaText · $state';
  }

  /// 반 층을 지난 즉시 새 층을 보여준다. 아직 하차 전이라 PDR 원점은 바꾸지
  /// 않고, 새 층의 도착 노드에 별도 마커만 고정한다.
  Future<void> _beginEscalatorTransition(EscalatorTransition transition) async {
    if (_applyingFloorTransition) return;
    final building = _building;
    if (building == null) return;
    if (!building.floors.contains(transition.toFloorLabel)) return;
    if (_selectedFloor != transition.fromFloorLabel) {
      // 판정 중에 사용자가 층 선택기로 다른 층을 열었다. 어느 층 기준인지
      // 모호해졌으므로 적용하지 않는다.
      return;
    }

    _applyingFloorTransition = true;
    try {
      _preTransferFloor = _selectedFloor;
      _preTransferAnchor = _pdrTrailState.anchor;
      _preTransferRoute = _route;
      _preTransferMultiRoute = _multiFloorRoute;
      _preTransferDestination = _routeDestination;
      _pendingArrivalRouteReady = false;

      await _selectFloor(transition.toFloorLabel);
      if (!mounted) return;

      final graph = _floorGraph;
      final arrival = _findArrivalNode(graph, transition);
      if (graph == null || arrival == null) {
        _showPdrMessage(
          '${transition.toFloorLabel} 도착 지점을 찾는 중입니다. 하차 후에도 위치가 '
          '보이지 않으면 "위치 지정"으로 현재 위치를 찍어주세요.',
        );
        return;
      }
      final wgs84 = fitFloorGeoTransform(
        graph.nodes,
      ).apply(arrival.xM, arrival.yM);
      setState(() {
        _pendingArrivalNode = arrival;
        _pendingTransferMarker = ll.LatLng(wgs84.$1, wgs84.$2);
        // 단일 층 경로였다면 _selectFloor가 목적지를 지운다. 실제 이동 확정 뒤
        // 새 위치에서 재탐색해야 하므로 목적지 계약은 보존한다.
        _routeDestination = _preTransferDestination;
      });

      // 층 화면을 먼저 바꾼 순간부터 실제 도착 에스컬레이터 기준 경로를
      // 그린다. PDR 재활성화는 센서 기준점의 문제이지 경로 계산의 선행조건이
      // 아니다. 취소될 수 있으므로 원래 경로 백업은 아직 지우지 않는다.
      await _rerouteAfterVerticalTransfer(
        arrivalNodeId: arrival.id,
        floor: transition.toFloorLabel,
        clearBackups: false,
      );
      if (!mounted) return;
      _pendingArrivalRouteReady = _route != null || _multiFloorRoute != null;
    } finally {
      _applyingFloorTransition = false;
    }
  }

  /// 고도 변화가 잦아든 순간 새 층 도착 노드를 PDR 원점으로 확정한다. 전환 중
  /// 쌓인 걸음은 applyVerticalTransfer의 pedometer reset으로 버려, 마커가
  /// 고정점에서 한꺼번에 튀지 않게 한다.
  Future<void> _completeEscalatorTransition(
    EscalatorTransition transition,
  ) async {
    if (_applyingFloorTransition) return;
    _applyingFloorTransition = true;
    try {
      if (_selectedFloor != transition.toFloorLabel) {
        await _selectFloor(transition.toFloorLabel);
        if (!mounted) return;
      }
      final graph = _floorGraph;
      final arrival =
          _pendingArrivalNode ?? _findArrivalNode(graph, transition);
      if (graph == null || arrival == null) {
        setState(() {
          _pendingTransferMarker = null;
          _pendingArrivalNode = null;
        });
        _showPdrMessage(
          '${transition.toFloorLabel} 도착 지점을 찾지 못했습니다. '
          '하단 "위치 지정"으로 현재 위치를 찍어주세요.',
        );
        return;
      }

      setState(() {
        // 이전 층 궤적과 복도 보정 상태는 새 층에서 이어지지 않는다.
        _pdrTrailState.beginNewSession();
        _corridorTrackingSession.reset();
      });
      await indoorNavigationDriver.applyVerticalTransfer(
        floorId: transition.toFloorLabel,
        anchorLocalM: PdrLocalPoint(arrival.xM, arrival.yM),
        axes: fitPdrToFloorAxes(graph.nodes),
      );
      if (!mounted) return;

      setState(() {
        _pendingTransferMarker = null;
        _pendingArrivalNode = null;
      });

      if (!_pendingArrivalRouteReady) {
        await _rerouteAfterVerticalTransfer(
          arrivalNodeId: arrival.id,
          floor: transition.toFloorLabel,
        );
      } else {
        _clearTransferRouteBackups(keepUndoAnchor: true);
      }
      if (!mounted) return;

      final directionLabel = transition.direction == EscalatorDirection.up
          ? '올라간'
          : '내려간';
      showDebugToast(
        context,
        message:
            '에스컬레이터로 ${transition.toFloorLabel}에 $directionLabel 것으로 보여 '
            '지도를 옮겼습니다.',
        bottomOffset:
            _mapShellBottomChromePx +
            (_hasActiveRoute ? _etaCardHeightPx : 0) +
            12,
        actionLabel: '아니에요',
        onAction: () => unawaited(_undoFloorTransition()),
      );
    } finally {
      _applyingFloorTransition = false;
    }
  }

  /// 반 층 후보가 되돌아가거나 타임아웃되면 화면·경로를 탑승 전 상태로 복원한다.
  Future<void> _cancelEscalatorTransition(
    EscalatorTransition transition,
  ) async {
    final floor = _preTransferFloor;
    if (floor == null) return;
    if (_selectedFloor != floor) {
      await _selectFloor(floor);
      if (!mounted) return;
    }
    setState(() {
      _route = _preTransferRoute;
      _multiFloorRoute = _preTransferMultiRoute;
      _routeDestination = _preTransferDestination;
      _pendingTransferMarker = null;
      _pendingArrivalNode = null;
      _routeProgress = null;
      _lastRouteTraveledM = null;
      _lastRouteProgressAcceptedSteps = null;
      _lastRouteEvaluatedSteps = null;
      _offRouteEvidenceUpdates = 0;
      _offRouteFirstEvidenceAtMs = null;
      _pendingArrivalRouteReady = false;
    });
    _clearTransferRouteBackups(keepUndoAnchor: false);
  }

  Future<void> _rerouteAfterVerticalTransfer({
    required String arrivalNodeId,
    required String floor,
    bool clearBackups = true,
  }) async {
    final destination = _preTransferDestination ?? _routeDestination;
    final destinationNodeId = destination?.nodeId;
    if (destination == null || destinationNodeId == null) {
      if (clearBackups) {
        _clearTransferRouteBackups(keepUndoAnchor: true);
      }
      return;
    }
    setState(() => _routeDestination = destination);
    if (destination.floor == floor) {
      await _computeAndShowSingleFloorRoute(
        floor: floor,
        endNodeId: destinationNodeId,
        explicitOriginNodeId: arrivalNodeId,
      );
    } else {
      await _computeAndShowMultiFloorRoute(
        startFloor: floor,
        endFloor: destination.floor,
        endNodeId: destinationNodeId,
        explicitOriginNodeId: arrivalNodeId,
      );
    }
    if (clearBackups) {
      _clearTransferRouteBackups(keepUndoAnchor: true);
    }
  }

  void _clearTransferRouteBackups({required bool keepUndoAnchor}) {
    _preTransferRoute = null;
    _preTransferMultiRoute = null;
    _preTransferDestination = null;
    if (!keepUndoAnchor) {
      _preTransferFloor = null;
      _preTransferAnchor = null;
    }
    _pendingArrivalRouteReady = false;
  }

  /// 자동 전환을 되돌린다. 층과 앵커를 전환 직전 값으로 복원한다.
  ///
  /// 되돌린 뒤 위치는 "에스컬레이터를 타기 직전 지점"이다. 그 사이 걸은 거리는
  /// 복원하지 않는다 — 잘못된 전환이었다면 그 구간의 걸음은 어차피 어느 층
  /// 기준인지 알 수 없다.
  Future<void> _undoFloorTransition() async {
    final floor = _preTransferFloor;
    final anchor = _preTransferAnchor;
    final destination = _routeDestination;
    if (floor == null || anchor == null) return;
    _preTransferFloor = null;
    _preTransferAnchor = null;
    if (_applyingFloorTransition) return;
    _applyingFloorTransition = true;
    try {
      await _selectFloor(floor);
      if (!mounted) return;
      setState(() {
        _pdrTrailState.beginNewSession();
        _corridorTrackingSession.reset();
      });
      await indoorNavigationDriver.applyVerticalTransfer(
        floorId: floor,
        anchorLocalM: anchor.anchorLocalM,
        axes: anchor.axes,
      );
      if (!mounted) return;
      if (destination != null) {
        await showRouteTo(destination);
      }
    } finally {
      _applyingFloorTransition = false;
    }
  }

  /// 새 층에서 이 이동의 **도착 노드**를 찾는다.
  ///
  /// 1순위는 이름 규칙(`{그룹}-UP(FR{출발층})`)이다. 백엔드 수직 전이 간선은
  /// 위치 근접으로 짝지어져 탑승/도착이 뒤바뀔 수 있어 근거로 쓰지 않는다
  /// ([EscalatorNodeName] 문서 참고). 이름으로 못 찾으면 같은 그룹·같은 방향의
  /// 에스컬레이터 노드로 폴백하고, 그것도 없으면 null을 돌려준다.
  GraphNode? _findArrivalNode(
    FloorGraph? graph,
    EscalatorTransition transition,
  ) {
    if (graph == null) return null;
    final expectedArrivalNodeId = transition.expectedArrivalNodeId;
    if (expectedArrivalNodeId != null) {
      for (final node in graph.nodes) {
        if (node.id == expectedArrivalNodeId && node.type == 'escalator') {
          return node;
        }
      }
    }
    GraphNode? sameGroupFallback;
    for (final node in graph.nodes) {
      if (node.type != 'escalator') continue;
      final parsed = EscalatorNodeName.tryParse(node.name);
      if (parsed == null) continue;
      if (parsed.isArrivalOf(
        group: transition.group,
        direction: transition.direction,
        fromFloorLabel: transition.fromFloorLabel,
      )) {
        return node;
      }
      if (sameGroupFallback == null &&
          parsed.group == transition.group &&
          parsed.direction == transition.direction) {
        sameGroupFallback = node;
      }
    }
    return sameGroupFallback;
  }

  void _syncCorridorTracking(PdrSnapshot? snapshot) {
    final anchor = _pdrTrailState.anchor;
    if (anchor == null || anchor.floorId != _selectedFloor) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final result = _corridorTrackingSession.update(
      graph: _floorGraph,
      anchor: anchor,
      snapshot: snapshot,
      timestampMs: nowMs,
    );
    if (result != null) {
      _guidanceTrailSession.update(floorId: anchor.floorId, result: result);
      // 층 전이 판정에는 **보정된** 위치를 준다. 원시 PDR 좌표를 주면 앵커
      // 오차만큼 에스컬레이터 노드 근접 판정이 어긋난다.
      _escalatorDetector.onPosition(
        positionM: result.correctedPosition,
        steps: snapshot?.steps ?? 0,
        timestampMs: nowMs,
      );
      final currentSegment = _multiFloorRoute?.segmentForFloor(anchor.floorId);
      final currentRoute = currentSegment?.route;
      if (currentSegment?.transferModeToNext == 'escalator' &&
          currentSegment?.transferFromNodeId != null &&
          currentRoute != null &&
          currentRoute.pointsLocalM.isNotEmpty) {
        final routeEnd = currentRoute.pointsLocalM.last;
        _escalatorDetector.onEscalatorRouteApproach(
          positionM: result.previewPosition,
          routeEndM: PdrLocalPoint(routeEnd.x, routeEnd.y),
          expectedBoardingNodeId: currentSegment!.transferFromNodeId!,
          expectedArrivalNodeId: currentSegment.transferToNodeId,
          steps: snapshot?.steps ?? 0,
          timestampMs: nowMs,
        );
      }
    }
    if (result != null) {
      _pdrDebugRecorder?.recordCorridorCorrection(result);
      if (snapshot != null) {
        _pdrDebugRecorder?.recordTrackerInput(
          observation: _corridorTrackingSession.lastObservation,
          wasReset: _corridorTrackingSession.lastWasReset,
          result: result,
          snapshot: snapshot,
          previewTailPeakTimesMs: _corridorTrackingSession
              .previewTailPeakTimesMs(snapshot),
        );
      }
    }
    _syncRouteProgress(
      result,
      confirmedSteps: snapshot?.steps,
      previewSteps: snapshot?.preview.steps,
    );
  }

  /// 보정 위치를 지금 층의 경로 세그먼트에 투영해 진행 상태를 갱신한다.
  ///
  /// 경로는 이 계산의 **입력이 아니라 출력 쪽**에만 있다 — tracker에는 아무것도
  /// 되돌려주지 않으므로, 경로가 위치 추정을 끌어당기는 일이 구조적으로
  /// 불가능하다.
  void _syncRouteProgress(
    CorridorTrackingResult? result, {
    int? confirmedSteps,
    int? previewSteps,
  }) {
    final route = _route;
    if (route == null || result == null) {
      if (_routeProgress != null || _lastRouteTraveledM != null) {
        setState(() {
          _routeProgress = null;
          _lastRouteTraveledM = null;
          _lastRouteProgressAcceptedSteps = null;
          _lastRouteEvaluatedSteps = null;
          _offRouteEvidenceUpdates = 0;
          _offRouteFirstEvidenceAtMs = null;
        });
      }
      return;
    }

    final localPosition = LocalPoint(
      result.previewPosition.eastM,
      result.previewPosition.northM,
    );
    final first = route.pointsLocalM.isEmpty ? null : route.pointsLocalM.first;
    final atNewRouteStart =
        _routeProgress == null &&
        first != null &&
        math.sqrt(
              math.pow(localPosition.x - first.x, 2) +
                  math.pow(localPosition.y - first.y, 2),
            ) <=
            0.5;
    final progress = atNewRouteStart
        ? seedRouteProgressAtRouteStart(
            routePointsLocalM: route.pointsLocalM,
            routeEdgeIds: route.edgeIds.toSet(),
            currentEdgeId: result.currentEdgeId,
            headingDeg: result.previewHeadingDeg,
          )
        : computeRouteProgress(
            routePointsLocalM: route.pointsLocalM,
            routeEdgeIds: route.edgeIds.toSet(),
            // 표시 위치와 같은 값을 쓴다. 확정(초록) 위치로 계산하면 화면의
            // 마커와 남은거리가 서로 다른 시점을 가리킨다.
            position: localPosition,
            currentEdgeId: result.currentEdgeId,
            headingDeg: result.previewHeadingDeg,
            previousTraveledM: _lastRouteTraveledM,
          );
    if (progress == null) return;

    final previousDisplayProgress = _routeProgress;
    final responsiveSteps = previewSteps ?? confirmedSteps;
    _maybeRerouteAfterDeviation(progress, result, responsiveSteps);
    final holdForPendingDeviation =
        !progress.onRouteEdge &&
        _offRouteEvidenceUpdates > 0 &&
        previousDisplayProgress != null;
    final holdForImplausibleJump = shouldHoldImplausibleRouteJump(
      previous: previousDisplayProgress,
      candidate: progress,
      acceptedAtSteps: _lastRouteProgressAcceptedSteps,
      currentSteps: responsiveSteps,
    );
    final holdPrevious = holdForPendingDeviation || holdForImplausibleJump;
    final displayProgress = holdPrevious ? previousDisplayProgress! : progress;
    setState(() {
      _routeProgress = displayProgress;
      _lastRouteTraveledM = displayProgress.traveledM;
      if (!holdPrevious) {
        _lastRouteProgressAcceptedSteps = responsiveSteps;
      }
    });
    _pdrDebugRecorder?.recordRouteProgress(progress);
  }

  /// 현재 간선이 안내 경로에 속하지 않거나 경로에서 확연히 떨어진 상태가
  /// preview 기준 여러 위치 갱신 동안 이어지면 목적지는 유지하고 현 위치에서
  /// 경로만 다시 계산한다.
  ///
  /// 걸음 개수를 임계값으로 쓰면 네이티브 이벤트 한 번에 여러 걸음이 묶여
  /// 들어올 때 한 프레임만으로 이탈이 확정될 수 있다. 시간과 독립 갱신 횟수를
  /// 함께 요구해 교차점 흔들림은 흡수하되 실제 이탈은 보행 중 약 1~2초 안에
  /// 재탐색한다. confirmed 배치가 아니라 주황 preview 걸음을 써서 iOS의
  /// 2.5초 pedometer batch를 세 번 기다리지 않는다.
  void _maybeRerouteAfterDeviation(
    RouteProgress progress,
    CorridorTrackingResult result,
    int? steps,
  ) {
    final strongDeviation = progress.offsetM >= 4 || progress.reacquired;
    final deviated = !progress.onRouteEdge || strongDeviation;
    if (!deviated ||
        result.currentEdgeId == null ||
        result.state == CorridorTrackingState.uncertain) {
      _offRouteEvidenceUpdates = 0;
      _offRouteFirstEvidenceAtMs = null;
      _lastRouteEvaluatedSteps = steps;
      return;
    }
    if (steps == null || steps == _lastRouteEvaluatedSteps) return;
    _lastRouteEvaluatedSteps = steps;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _offRouteFirstEvidenceAtMs ??= nowMs;
    _offRouteEvidenceUpdates++;
    final evidenceDurationMs = nowMs - _offRouteFirstEvidenceAtMs!;
    final requiredUpdates = strongDeviation ? 2 : 3;
    final requiredDurationMs = strongDeviation ? 700 : 1200;
    if (_offRouteEvidenceUpdates < requiredUpdates ||
        evidenceDurationMs < requiredDurationMs ||
        _rerouteInFlight) {
      return;
    }
    if (nowMs - _lastRerouteAtMs < 2000) return;
    unawaited(_rerouteFromCurrentPosition());
  }

  Future<void> _rerouteFromCurrentPosition() async {
    final destination = _routeDestination;
    final destinationNodeId = destination?.nodeId;
    // 층 selector는 사용자가 다른 층을 둘러보는 UI 상태일 뿐 실제 현재 층이
    // 아니다. 다층 안내 중 selector 층을 기준으로 재탐색하면 중간 세그먼트가
    // 단층 경로로 바뀌어 최종 도착처럼 보일 수 있다.
    final floor = _pdrTrailState.anchor?.floorId;
    final graph = _floorGraph;
    final current = _corridorTrackingSession.result?.previewPosition;
    if (destination == null ||
        destinationNodeId == null ||
        floor == null ||
        graph == null ||
        current == null) {
      return;
    }
    final startNodeId = _nearestNodeId(
      graph.nodes,
      current.eastM,
      current.northM,
      excludingNodeId: destinationNodeId,
    );
    if (startNodeId == null) return;

    _rerouteInFlight = true;
    try {
      if (destination.floor == floor) {
        await _computeAndShowSingleFloorRoute(
          floor: floor,
          endNodeId: destinationNodeId,
          explicitOriginNodeId: startNodeId,
          preserveVisibleRoute: true,
        );
      } else {
        await _computeAndShowMultiFloorRoute(
          startFloor: floor,
          endFloor: destination.floor,
          endNodeId: destinationNodeId,
          explicitOriginNodeId: startNodeId,
        );
      }
      _lastRerouteAtMs = DateTime.now().millisecondsSinceEpoch;
      _offRouteEvidenceUpdates = 0;
      _offRouteFirstEvidenceAtMs = null;
      _lastRouteEvaluatedSteps = null;
    } finally {
      _rerouteInFlight = false;
    }
  }

  /// 걸음이 아직 확정되지 않은 PDR 시작 직후에도, 사용자가 선택한 anchor를
  /// 현재 위치 마커로 표시한다. PDR을 켜기 전에는 null이라 도면 중앙에 가짜
  /// 현재 위치가 나타나지 않는다.
  ll.LatLng? get _pdrAnchorLocation {
    final graph = _floorGraph;
    final anchor = _pdrTrailState.anchor;
    if (graph == null || anchor == null || anchor.floorId != _selectedFloor) {
      return null;
    }
    final wgs84 = fitFloorGeoTransform(
      graph.nodes,
    ).apply(anchor.anchorLocalM.eastM, anchor.anchorLocalM.northM);
    return ll.LatLng(wgs84.$1, wgs84.$2);
  }

  List<ll.LatLng> _floorPathToWgs84(List<PdrLocalPoint> path) {
    final graph = _floorGraph;
    if (graph == null || path.isEmpty) {
      return const [];
    }
    final floorToWgs84 = fitFloorGeoTransform(graph.nodes);
    return path
        .map((point) {
          final wgs84 = floorToWgs84.apply(point.eastM, point.northM);
          return ll.LatLng(wgs84.$1, wgs84.$2);
        })
        .toList(growable: false);
  }

  List<ll.LatLng> get _pdrMatchedPathPoints =>
      _floorPathToWgs84(_pdrMatchedFloorPath);

  List<ll.LatLng> get _pdrMatchedPreviewPathPoints =>
      _floorPathToWgs84(_pdrMatchedPreviewFloorPath);

  List<List<ll.LatLng>> get _walkedGuidanceSegments {
    final floor = _selectedFloor;
    if (floor == null) return const [];
    return [
      for (final segment in _guidanceTrailSession.segmentsForFloor(
        floor,
        previewPath: _pdrMatchedPreviewFloorPath,
      ))
        _floorPathToWgs84(segment),
    ];
  }

  List<ll.LatLng> get _pdrConfirmedPathPoints =>
      _floorPathToWgs84(_pdrConfirmedFloorPath);

  List<ll.LatLng> get _pdrRawPathPoints => _floorPathToWgs84(_pdrRawFloorPath);

  List<ll.LatLng> get _pdrRoninPathPoints =>
      _floorPathToWgs84(_pdrRoninFloorPath);

  /// 진단 세션은 **한 번의 길안내**를 단위로 한다.
  ///
  /// PDR이 상시 실행이 된 뒤에는 "PDR 시작~종료"를 세션 경계로 쓸 수 없다.
  /// 앱을 열어둔 내내 쌓이면 품질 표본(900)·tracker 이벤트(4000) 상한에 걸려
  /// 정작 분석하려는 주행 구간이 앞에서부터 잘려 나간다. 경로가 생기는 순간
  /// 새로 시작하고 경로가 사라질 때 닫으면, 파일 하나가 정확히 한 번의 길안내를
  /// 담는다 — v11 경로 지표와 단위가 같아진다.
  void _beginRouteRecordingSession() {
    _pdrDebugRecorder = PdrDebugSessionRecorder();
    _pdrDebugRecorder?.recordRuntime(
      indoorNavigationDriver.currentRuntimeStatus,
    );
    final snapshot = indoorNavigationDriver.currentSnapshot;
    if (snapshot != null) _pdrDebugRecorder?.recordSnapshot(snapshot);
    _pdrDebugRecorder?.recordCalibration(
      indoorNavigationDriver.currentCalibration,
    );
  }

  /// 경로가 해제되면 진단 세션을 닫는다.
  ///
  /// [announceExport]가 true일 때만 내보내기 안내를 띄운다. 예전에는 "PDR 종료"
  /// 버튼이 이 안내의 유일한 트리거였다. 그 버튼이 없어진 지금 길안내가 실제로
  /// 끝나는 지점(_clearRoute)에서 안내하지 않으면, 사용자가 주행을 끝내고 앱을
  /// 닫는 순간 실측 데이터를 꺼낼 기회가 사라진다. 반대로 길안내가 계속되는
  /// 상황(재탐색·목적지 변경)에서 띄우면 완료로 오해하게 된다.
  void _endRouteRecordingSession({bool announceExport = true}) {
    final recorder = _pdrDebugRecorder;
    if (recorder == null) return;
    final snapshot = indoorNavigationDriver.currentSnapshot;
    if (snapshot != null) recorder.recordSnapshot(snapshot);
    recorder.recordRuntime(indoorNavigationDriver.currentRuntimeStatus);
    if (!mounted) return;
    if (announceExport &&
        recorder.hasSnapshot &&
        _debugModeController.enabled) {
      _showPdrMessageWithExport('길안내가 끝났습니다. 진단 JSON을 내보내 분석할 수 있습니다.');
    }
  }

  /// PDR 세션을 [floor]에 맞춘다. 이어서 앵커를 찍어도 되면 true.
  ///
  /// **다른 층에서 이미 돌고 있는 세션을 그냥 재사용하면 안 된다.** 앵커에
  /// 찍히는 층은 세션의 층([IndoorNavigationView.currentFloorId])이고, 위치
  /// 마커·경로는 `anchor.floorId == 지금 보고 있는 층`일 때만 그려진다. 그래서
  /// 1층에서 위치를 지정한 뒤 2층에서 다시 지정하면, 새 앵커가 여전히 1층으로
  /// 기록돼 2층 지도에는 아무것도 나타나지 않았다.
  ///
  /// 어느 경로로 들어와도 앵커를 새로 찍는 것은 **기준점을 새로 잡는 것**이므로,
  /// 이전 기준점 기준의 궤적·복도 보정·경로 진행 상태를 함께 비운다. 남겨두면 새
  /// 기준점에서 이어지지 않은 선이 남고 남은거리가 튄다.
  ///
  /// [announceFailure]는 센서를 못 켠 이유를 사용자에게 알릴지다. 사용자가 직접
  /// "위치 지정"을 누른 경우에만 켠다 — 자동으로 출발지 앵커를 찍는 경로는 조용히
  /// 포기하고 경로만 그린다.
  Future<bool> _bindPdrSessionToFloor(
    String floor, {
    bool announceFailure = false,
  }) async {
    if (indoorNavigationDriver.currentRuntimeStatus.state ==
        PdrRuntimeState.idle) {
      await _startPdrIfIdle();
      if (!mounted) return false;
      if (indoorNavigationDriver.currentRuntimeStatus.state ==
          PdrRuntimeState.idle) {
        if (announceFailure) {
          _showPdrMessage(
            '걸음 센서 권한이 없어 위치를 추적할 수 없습니다. 설정에서 동작·피트니스 권한을 허용해주세요.',
          );
        }
        return false;
      }
    } else if (indoorNavigationDriver.currentFloorId != floor) {
      await indoorNavigationDriver.changeFloor(floorId: floor);
      if (!mounted) return false;
    }
    _pdrDebugRecorder?.recordRuntime(
      indoorNavigationDriver.currentRuntimeStatus,
    );
    setState(() {
      _pdrTrailState.beginNewSession();
      _corridorTrackingSession.reset();
      _routeProgress = null;
      _lastRouteTraveledM = null;
      _lastRouteProgressAcceptedSteps = null;
      _lastRouteEvaluatedSteps = null;
      _offRouteEvidenceUpdates = 0;
      _offRouteFirstEvidenceAtMs = null;
    });
    return true;
  }

  /// 출발지로 고른 매장 자리에 PDR 앵커를 다시 찍어, 현재 위치 아이콘을 그
  /// 매장으로 옮긴다. 근거와 실패 처리는 야외 화면의 동명 함수와 같다.
  Future<void> _anchorAtStoreOrigin({
    required String floor,
    required String nodeId,
    required ll.LatLng storePoint,
  }) async {
    // [_confirmPdrAnchor]가 축 변환(axes)을 [_floorGraph]에서 가져오므로,
    // 앵커를 찍기 전에 그 층 도면이 화면에 올라와 있어야 한다.
    if (floor != _selectedFloor) {
      await _selectFloor(floor);
      if (!mounted) return;
    }
    final graph = _floorGraph;
    if (graph == null || graph.nodes.isEmpty) return;

    // 매장의 입구 노드를 그대로 쓴다. 이미 통로 위에 있어 스냅이 필요 없고,
    // 경로 탐색이 시작하는 지점과도 정확히 같은 자리가 된다.
    final node = graph.nodes.where((n) => n.id == nodeId).firstOrNull;
    final PdrLocalPoint floorPoint;
    if (node != null) {
      floorPoint = PdrLocalPoint(node.xM, node.yM);
    } else {
      final local = fitFloorGeoTransform(
        graph.nodes,
      ).invert(storePoint.latitude, storePoint.longitude);
      if (local == null) return;
      final snapped = FloorMapMatcher(
        graph,
      ).snapToWalkableNetwork(PdrLocalPoint(local.$1, local.$2));
      if (snapped == null) return;
      floorPoint = snapped.point;
    }

    if (!await _bindPdrSessionToFloor(floor)) return;
    await _confirmPdrAnchor(floorPoint, notifyLocationChanged: false);
  }

  /// 지도 탭으로 앵커를 배치하는 경로의 테스트 진입점.
  ///
  /// FloorPlanView는 위젯 테스트에서 실제 탭 좌표를 위경도로 되돌려 주지
  /// 않으므로, 실기기에서 쓰이는 것과 **같은 함수**를 직접 부른다 — 테스트용
  /// 축약 경로를 따로 두면 정작 검증하려는 분기를 우회한다. 야외 화면의
  /// `handleMapClickForTest`와 같은 목적이다.
  @visibleForTesting
  bool handleMapPressForTest(ll.LatLng point) => _onMapPressedForPdr(point);

  bool _onMapPressedForPdr(ll.LatLng point) {
    if (!_placingPdrAnchor) return false;
    final graph = _floorGraph;
    if (graph == null || graph.nodes.isEmpty) return false;
    final local = fitFloorGeoTransform(
      graph.nodes,
    ).invert(point.latitude, point.longitude);
    if (local == null) {
      _showPdrMessage('이 층 좌표를 계산하지 못했습니다.');
      return true;
    }
    final tappedPoint = PdrLocalPoint(local.$1, local.$2);
    final snapped = FloorMapMatcher(graph).snapToWalkableNetwork(tappedPoint);
    if (snapped == null) {
      _showPdrMessage('이 층의 통로 위치를 찾지 못했습니다. 다시 시도해주세요.');
      return true;
    }
    if (snapped.distanceToGraphM > _maxPdrAnchorSnapDistanceM) {
      _showPdrMessage('입구 또는 복도에 더 가깝게 시작 위치를 탭해주세요.');
      return true;
    }
    unawaited(_confirmPdrAnchor(snapped.point));
    return true;
  }

  /// heading이 자리를 잡을 때까지 최대 [_headingSettleTimeout]만큼 기다린다.
  ///
  /// 세션 시작 직후에는 자북 reference가 아직 수렴하지 않았거나 사용자가 몸을
  /// 돌리는 중이라 방향이 흔들린다. 그 상태로 앵커를 확정하면 첫 걸음들이
  /// 틀어진 방향으로 눕는다. 타임아웃되면 그냥 진행한다 — 방향이 계속 흔들리는
  /// 환경(강한 자기 왜곡 등)에서 앵커 확정 자체가 막히면 더 나쁘다.
  Future<bool> _waitForHeadingToSettle() async {
    if (indoorNavigationDriver.isHeadingConverged) return true;
    _showPdrMessage('방향을 잡는 중입니다. 폰을 든 채로 잠시만 기다려주세요.');
    final deadline = DateTime.now().add(_headingSettleTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return false;
      if (indoorNavigationDriver.isHeadingConverged) return true;
    }
    return false;
  }

  /// [notifyLocationChanged]는 "사용자의 현재 위치가 새로 잡혔다"를 상위에
  /// 알릴지다. 기본은 알린다 — 지도 탭처럼 **새 위치가 생긴** 경우이기 때문이다.
  /// 출발지 매장을 따라 찍는 경우([_anchorAtStoreOrigin])만 끈다. 그쪽은 상위가
  /// 방금 정한 출발지를 되짚어 찍는 것이라, 다시 알리면 상위가 그 출발지를
  /// 스스로 버리게 된다.
  Future<void> _confirmPdrAnchor(
    PdrLocalPoint floorPoint, {
    bool notifyLocationChanged = true,
    String? floorId,
  }) async {
    final settled = await _waitForHeadingToSettle();
    if (!mounted) return;
    if (!settled) {
      _showPdrMessage('방향이 아직 흔들립니다. 그대로 시작하되 초반 경로가 틀어질 수 있습니다.');
    }
    final graph = _floorGraph;
    final axes = graph == null
        ? const PdrToFloorAxes.identity()
        : fitPdrToFloorAxes(graph.nodes);
    await indoorNavigationDriver.confirmAnchorByPin(
      floorPointM: floorPoint,
      axes: axes,
      floorId: floorId ?? _selectedFloor,
    );
    if (!mounted) return;
    if (indoorNavigationDriver.currentCalibration.phase ==
        CalibrationPhase.awaitingHeading) {
      final screenDirection = await _askScreenDirection();
      if (screenDirection == null || !mounted) return;
      final floorDirection = floorDirectionForScreenDirection(
        cameraBearingDeg: _mapCameraBearingDeg,
        screenClockwiseOffsetDeg: screenDirection,
        axes: axes,
      );
      await indoorNavigationDriver.confirmAnchorByFloorDirection(
        floorDirection: floorDirection,
      );
    }
    if (!mounted) return;
    _setPlacingAnchor(false);
    if (notifyLocationChanged) widget.onLocationAnchored?.call();
    // 배치가 끝났다는 안내는 따로 띄우지 않는다. 도면에 위치 마커가 바로
    // 찍히고 안내 배너가 사라지는 것으로 이미 결과가 보이는데, 토스트까지
    // 겹치면 방금 지정한 지점을 가린다.
  }

  Future<void> _cancelPdrAnchor() async {
    if (!_placingPdrAnchor) return;
    await indoorNavigationDriver.stopGuidance();
    _pdrDebugRecorder?.recordRuntime(
      indoorNavigationDriver.currentRuntimeStatus,
    );
    if (mounted) _setPlacingAnchor(false);
  }

  Future<double?> _askScreenDirection() {
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('진행 방향 보정'),
        content: const Text(
          '이 기기는 절대 북쪽 기준 heading을 얻지 못했습니다. 현재 휴대폰이 향한 지도 방향을 선택해주세요.',
        ),
        actions: [
          for (final entry in const [
            (label: '위쪽', value: 0.0),
            (label: '오른쪽', value: 90.0),
            (label: '아래쪽', value: 180.0),
            (label: '왼쪽', value: 270.0),
          ])
            TextButton(
              onPressed: () => Navigator.of(context).pop(entry.value),
              child: Text(entry.label),
            ),
        ],
      ),
    );
  }

  void _showPdrMessage(String message) {
    if (!mounted) return;
    showDebugToast(
      context,
      message: message,
      bottomOffset:
          _mapShellBottomChromePx +
          (_hasActiveRoute ? _etaCardHeightPx : 0) +
          12,
    );
  }

  void _showPdrMessageWithExport(String message) {
    if (!mounted) return;
    showDebugToast(
      context,
      message: message,
      bottomOffset:
          _mapShellBottomChromePx +
          (_hasActiveRoute ? _etaCardHeightPx : 0) +
          12,
      actionLabel: 'JSON 공유',
      onAction: () => unawaited(_exportPdrDebugJson()),
    );
  }

  Future<void> _exportPdrDebugJson() async {
    final recorder = _pdrDebugRecorder;
    if (recorder == null || !recorder.hasSnapshot || _exportingPdrDebugJson) {
      _showPdrMessage('내보낼 PDR 세션이 없습니다.');
      return;
    }
    setState(() => _exportingPdrDebugJson = true);
    try {
      final device = await PdrDebugDeviceInfo.load();
      final session = recorder.buildJson(
        buildingId: widget.buildingId,
        selectedFloor: _selectedFloor,
        mapCalibrationVersion: _mapCalibrationVersion,
        graph: _floorGraph,
        device: device,
      );
      await const PdrDebugSessionShare().share(
        session,
        sharePositionOrigin: _pdrSharePositionOrigin(),
      );
    } on Object catch (error) {
      if (mounted) _showPdrMessage('PDR JSON을 내보내지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _exportingPdrDebugJson = false);
    }
  }

  /// iOS 공유 시트는 popover 기준 사각형이 필요하다. 전달하지 않으면
  /// share_plus가 `{0, 0, 0, 0}`을 보내 iOS에서 공유를 거부한다.
  Rect? _pdrSharePositionOrigin() {
    final buttonBox =
        _pdrShareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (buttonBox != null &&
        buttonBox.hasSize &&
        buttonBox.size.isEmpty == false) {
      return buttonBox.localToGlobal(Offset.zero) & buttonBox.size;
    }

    final screenBox = context.findRenderObject() as RenderBox?;
    if (screenBox != null &&
        screenBox.hasSize &&
        screenBox.size.isEmpty == false) {
      return screenBox.localToGlobal(Offset.zero) & screenBox.size;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? _buildError(error)
        : _buildBody();
    return Stack(
      children: [
        Positioned.fill(child: body),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          left: 12,
          bottom: _hasActiveRoute ? _bottomBarLiftPx : 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(
                bottom: _bottomBarInnerBottomPaddingPx,
              ),
              child: DebugModeSettingsButton(
                key: _debugModeSettingsKey,
                controller: _debugModeController,
                onPressed: () =>
                    showDebugModeSettingsSheet(context, _debugModeController),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 40, color: Colors.black45),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _loadBuilding,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final building = _building;
    if (building == null) {
      return const Center(child: Text('건물 정보를 찾을 수 없습니다'));
    }
    final floorPlan = _floorPlan;
    if (floorPlan == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final route = _route;
    final routeDestination = _routeDestination;
    // 거리·시간을 한 번에 계산한다(예전엔 같은 순회를 두 번 돌았다).
    final eta = _etaRemaining(route);
    final routeVisuals = _routeVisuals(route);
    final routeGuidance = _currentRouteGuidance(route);
    final debugEnabled = _debugModeController.enabled;
    final cardinalCalibration =
        debugEnabled && _debugModeController.showCardinalCross
        ? cardinalCalibrationForBuilding(
            widget.buildingId,
            floorPlan: floorPlan,
          )
        : null;
    // 현재 위치 마커와 앵커 위치는 일반 사용자에게도 노출한다 — 하단 바의
    // "위치 지정" 버튼으로 사용자가 자기 위치를 지정한 뒤에는 그 지점이
    // 지도에 보여야 하고, 이후 PDR 스냅샷이 갱신되면 그 실시간 위치도
    // 그대로 이어서 보여야 한다. 디버그 오버레이(그래프 노드/간선, 활성
    // 간선 하이라이트)만 debugEnabled 뒤에 남겨 둔다.
    final pdrCurrent = _pdrCurrentLocation;
    final debugOverlay = debugEnabled
        ? buildDebugMapOverlay(
            _floorGraph,
            showNodes: _debugModeController.showGraphNodes,
            showEdges: _debugModeController.showGraphEdges,
            activeEdgeIds: _pdrMatchedEdgeIds,
          )
        : const DebugMapOverlay();
    // 위치 핀은 "사용자가 지금 있는 곳"만 표현한다. PDR 확정 위치도, 앵커도
    // 이 층에 없다면 아무것도 그리지 않는다 — 예전에는 route.points.first로
    // 폴백했는데, 다층 경로에서 앵커가 다른 층에 있을 때 이 값은 이 층 세그먼트의
    // 시작점(=에스컬레이터/엘리베이터 도착 지점)이라 사용자 위치가 아니다.
    // 그 폴백이 켜지면 "3층 에스컬레이터에 내가 서 있는 것"처럼 보여 오해를
    // 만든다. 층이 다르면 뷰는 그저 다른 층의 지도만 보여주고, 자기 위치가
    // 궁금하면 "위치 지정" 또는 재보정으로 원래 층으로 돌아가면 된다.
    final trackerUncertain =
        _corridorTrackingSession.result?.state ==
        CorridorTrackingState.uncertain;
    final gpsEstimate = _freshGpsIndoorEstimate;
    final currentUsesPdr =
        _pendingTransferMarker == null &&
        pdrCurrent != null &&
        (!trackerUncertain || gpsEstimate == null);
    final current =
        _pendingTransferMarker ??
        (!trackerUncertain ? pdrCurrent : null) ??
        gpsEstimate ??
        pdrCurrent ??
        _pdrAnchorLocation;

    // 지도가 화면 끝까지 그려지지만 위/아래 UI에 실제로 가려지는 두께를 계산해
    // FloorPlanView에 넘긴다. 축소 하한이 이 "가려지지 않는 세로 영역"에 맞춰
    // 잡혀야 하한에 도달했을 때 건물의 위/아래가 오버레이 뒤로 밀리지 않는다.
    // 인포바는 위쪽 대각선 공간만 살짝 차지해 vertical fit에 큰 영향은 없지만,
    // 하한이 아주 살짝 더 넉넉해지도록 top에 포함해 둔다.
    final systemPadding = MediaQuery.paddingOf(context);
    final topOverlay = systemPadding.top + _mapShellTopChromePx;
    final bottomOverlay =
        systemPadding.bottom +
        _mapShellBottomChromePx +
        (_hasActiveRoute ? _etaCardHeightPx : 0);

    return Stack(
      children: [
        FloorPlanView(
          // 건물/층이 바뀔 때 위젯 자체를 다시 만들어야 초기화 상태를 재사용
          // 하지 않으므로 ValueKey를 유지한다. 카메라 조작(회전/중심 이동)은
          // controller가 매번 새로운 state에 자동 attach/detach 하도록 처리한다.
          key: ValueKey('${widget.buildingId}-$_selectedFloor'),
          controller: _floorPlanController,
          buildingId: widget.buildingId,
          floorName: _selectedFloor!,
          floorPlan: floorPlan,
          currentLocation: current,
          currentHeadingDegrees: currentUsesPdr ? _pdrCurrentHeadingDeg : null,
          // 핀은 매장 중심(centroid)이 아니라 실제 도착 노드(경로의 마지막
          // 점 = 매장 입구)에 찍는다. 경로가 아직 계산되기 전 짧은 순간에는
          // 경로 정보가 없으므로 centroid로 폴백해 핀이 아예 안 보이는
          // 상태를 만들지 않는다. 단, 다층 경로에서는 도착지 층을 보고 있을
          // 때만 도착 핀을 표시한다(중간 층은 지나가는 층이라 핀이 없어야 함).
          destination: _destinationPinForCurrentFloor(route, routeDestination),
          routePoints: routeVisuals.remaining,
          // 완료된 "기존 계획선"이 아니라 실제로 걸어온 graph-matched 궤적을
          // 회색으로 그린다. 따라서 재탐색은 파란 미래만 교체한다.
          walkedRouteSegments: _walkedGuidanceSegments,
          transferRoutePoints:
              _multiFloorRoute
                  ?.segmentForFloor(_selectedFloor ?? '')
                  ?.transferPointsToNext ??
              const [],
          pdrPathPoints:
              debugEnabled && _debugModeController.showMapMatchedPdrPath
              ? _pdrMatchedPathPoints
              : const [],
          pdrPreviewPathPoints:
              debugEnabled && _debugModeController.showMapMatchedPdrPath
              ? _pdrMatchedPreviewPathPoints
              : const [],
          pdrConfirmedPathPoints:
              debugEnabled && _debugModeController.showConfirmedPdrPath
              ? _pdrConfirmedPathPoints
              : const [],
          pdrRawPathPoints: debugEnabled && _debugModeController.showRawPdrPath
              ? _pdrRawPathPoints
              : const [],
          pdrRoninPathPoints:
              debugEnabled && _debugModeController.showRoninPdrPath
              ? _pdrRoninPathPoints
              : const [],
          debugMapOverlay: debugOverlay,
          onCameraBearingChanged: _onMapCameraBearingChanged,
          onMapPressed: _onMapPressedForPdr,
          onStoreSelected: (selected) {
            setState(() => _highlightedStoreId = selected.id);
            widget.onStoreTap?.call(
              PoiSearchResult(
                name: selected.name,
                floor: _selectedFloor!,
                point: selected.centroid,
                placeId: selected.id,
                nodeId: selected.entranceNodeId,
                category: selected.category,
                subcategory: selected.subcategory,
              ),
            );
          },
          interactive: _interactive,
          highlightedStoreId: _highlightedStoreId,
          categorySelection: widget.categorySelection,
          focusTarget: _focusTarget,
          focusTick: _focusTick,
          focusBottomSheetFraction: _focusBottomSheetFraction,
          tileRevision: _building?.tileRevision,
          visibleInsets: EdgeInsets.fromLTRB(0, topOverlay, 0, bottomOverlay),
          overlayHitTest: _isTapOnMapOverlay,
        ),

        if (debugEnabled)
          Positioned(
            left: 12,
            top: systemPadding.top + _placingHintTopPx,
            child: ValueListenableBuilder<String?>(
              valueListenable: _altimeterDebugText,
              builder: (context, text, _) => AltimeterDebugChip(text: text),
            ),
          ),

        if (cardinalCalibration != null)
          Positioned.fill(
            child: ValueListenableBuilder<double>(
              valueListenable: _mapCameraBearingNotifier,
              builder: (context, cameraBearingDeg, _) => CardinalGridOverlay(
                northMapBearingDeg: cardinalCalibration.northMapBearingDeg,
                cameraBearingDeg: cameraBearingDeg,
              ),
            ),
          ),

        // 층 선택기는 화면 왼쪽 하단 — 하단 바의 "위치 지정 / 위치 보정" 버튼과
        // 같은 baseline에 놓는다. 그 버튼 열은 SafeArea 바닥에서
        // (padding 14 + ModeSegment 45 + spacer 10 = 69)px 위에 앉기 때문에
        // pill 하단을 같은 오프셋에 맞춰 두 요소가 시각적으로 같은 층에 있게 한다.
        // 경로 ETA가 뜨면 하단 바가 위로 리프트되므로 pill도 같이 올린다.
        if (_selectedFloor != null && building.floors.isNotEmpty)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: 16,
            bottom:
                _floorSelectorBottomOffset +
                (_hasActiveRoute ? _bottomBarLiftPx : 0),
            child: SafeArea(
              top: false,
              child: FloorSelector(
                key: _floorSelectorKey,
                floors: building.floors,
                selectedFloor: _selectedFloor!,
                onSelectFloor: _selectFloor,
              ),
            ),
          ),

        // 경로 기준 진단 배지. 걸으면서 "지금 이 경로에 붙어 있는지"를 바로 볼
        // 수 있어야 실측 인상과 지표가 일치하는지 확인할 수 있다. 디버그 모드
        // 전용이며, 제품 UI에는 남은거리(ETA 카드)만 노출된다.
        if (debugEnabled && _routeProgress != null)
          Positioned(
            top: topOverlay + 8,
            left: 16,
            child: _RouteProgressBadge(progress: _routeProgress!),
          ),

        // PDR 제어는 하단 홈/실내 세그먼트 바로 왼쪽에 같은 baseline으로 둔다.
        // 상단의 장소·카테고리·층 chip과 분리해 좁은 화면에서도 겹치지 않으며,
        // 경로 ETA가 나타나면 홈/실내 바와 함께 같은 높이만큼 올라간다.
        if (debugEnabled)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            right: _pdrControlRightInsetPx,
            bottom: _hasActiveRoute ? _bottomBarLiftPx : 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(
                  bottom: _bottomBarInnerBottomPaddingPx,
                ),
                child: PdrMapControl(
                  key: _pdrControlKey,
                  // PDR이 상시 실행이므로 "정지 후에만 내보내기"라는 조건이
                  // 성립하지 않는다. 스냅샷이 쌓인 세션이 있으면 언제든 꺼낼 수
                  // 있게 한다.
                  canExport: _pdrDebugRecorder?.hasSnapshot ?? false,
                  exporting: _exportingPdrDebugJson,
                  onExport: _exportPdrDebugJson,
                  shareButtonKey: _pdrShareButtonKey,
                ),
              ),
            ),
          ),

        // 앵커 배치 안내는 디버그 모드에서 시작된 PDR이든, 일반 사용자가 하단
        // 바의 "위치 지정" 버튼으로 시작한 흐름이든 동일하게 필요하므로
        // debugEnabled 게이팅을 두지 않는다.
        if (_placingPdrAnchor)
          Positioned(
            top: _placingHintTopPx,
            left: 12,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: _PdrAnchorHint(
                key: _placingHintKey,
                onCancel: _cancelPdrAnchor,
              ),
            ),
          ),

        if (_hasActiveRoute && routeDestination != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: EtaCard(
                  key: _etaCardKey,
                  distanceMeters: eta.distanceM,
                  // 시간은 비용 기준이다 — 엘리베이터 대기·탑승 시간이 여기 들어 있다.
                  minutes: (eta.costM / _walkingSpeedMetersPerSecond / 60)
                      .ceil()
                      .clamp(1, 999),
                  label: _etaLabel(routeDestination),
                  instruction: routeGuidance,
                  onClose: _clearRoute,
                  onClosePointerDown: (position) =>
                      _etaClosePointerDown = position,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 시작 위치를 지도에 놓는 동안에만 보이는 간결한 안내. SnackBar만으로는 손이
/// 지도 위에 올라간 뒤 안내가 사라져 어디를 눌러야 하는지 놓치기 쉬워서, 지도
/// chrome 바로 아래에 남겨 둔다.
class _PdrAnchorHint extends StatelessWidget {
  const _PdrAnchorHint({super.key, required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.97),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          // X는 문구 오른쪽 **상단**에 고정한다. 문구가 두 줄로 접혀도 취소
          // 버튼이 세로 중앙으로 밀려나지 않아 눌러야 할 자리가 흔들리지 않는다.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.touch_app_outlined,
              color: AppColors.indoor,
              size: 21,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(
                  '입구 또는 복도에 시작점을 탭하세요',
                  maxLines: 2,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _HintCancelButton(onPressed: onCancel, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// 안내 배너 오른쪽 상단의 취소(X).
///
/// Material `IconButton`을 쓰지 않는 이유: 기본 최소 탭 영역이 48x48이라
/// 한두 줄짜리 안내 카드 높이를 불필요하게 늘린다. 26x26으로 줄이되 아이콘
/// 보다 넓은 탭 영역은 남긴다. 야외 화면의 동명 위젯과 같은 규격이다.
class _HintCancelButton extends StatelessWidget {
  const _HintCancelButton({required this.onPressed, required this.color});

  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '위치 지정 취소',
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 26,
          height: 26,
          child: Center(
            child: Icon(Icons.close_rounded, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

/// 경로 기준 진행 상태를 한 줄로 보여주는 디버그 배지.
///
/// 이탈 여부는 색으로, 진행·남은거리와 이탈거리는 숫자로 보여준다. 이탈 판정은
/// 간선 동일성으로만 하므로(경로와 나란한 옆 복도도 이탈로 잡힌다), 이탈거리는
/// 판정 근거가 아니라 참고값으로 함께 적는다.
class _RouteProgressBadge extends StatelessWidget {
  const _RouteProgressBadge({required this.progress});

  final RouteProgress progress;

  @override
  Widget build(BuildContext context) {
    final onRoute = progress.onRouteEdge;
    final color = onRoute ? const Color(0xFF188038) : const Color(0xFFD93025);
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              '${onRoute ? '경로 위' : '경로 이탈'} · '
              '진행 ${progress.traveledM.toStringAsFixed(1)}m / '
              '남음 ${progress.remainingM.toStringAsFixed(1)}m · '
              '오차 ${progress.offsetM.toStringAsFixed(1)}m'
              '${progress.reacquired ? ' · 재획득' : ''}'
              '${progress.wrongWay ? ' · 역주행' : ''}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
