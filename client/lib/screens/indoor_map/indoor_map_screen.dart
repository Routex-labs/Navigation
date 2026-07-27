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
import '../../domain/multi_floor_router.dart';
import '../../models/building.dart';
import '../../models/building_graph.dart';
import '../../models/floor_graph.dart';
import '../../models/floor_plan.dart';
import '../../models/indoor_route.dart';
import '../../models/poi_search_result.dart';
import '../../theme/app_theme.dart';
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

// 위치 지정 안내를 상단 chrome 아래에 놓기 위한 오프셋. MapShellScreen의
// 검색창(top 0)과 그 아래 카테고리 chip 열(top 78, 높이 ≈32) 밑으로 내려야
// 안내가 chip에 가려지지 않는다. SafeArea와 함께 써서 노치 기기에서 chip 열이
// 상태바만큼 내려앉는 것까지 따라간다.
// 야외 화면의 동명 상수와 같은 값이어야 두 화면에서 안내가 같은 자리에 뜬다.
const _placingHintTopPx = 132.0;

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
const _floorSelectorBottomOffset =
    _bottomBarInnerBottomPaddingPx + 45.0 + 10.0;

/// 실내 지도 본문(층 평면도 + 경로/매장 오버레이). 검색창·길찾기·건물 전환 같은
/// 공통 UI는 [MapShellScreen]이 상단/하단 바로 얹으므로 여기서는 다루지 않는다.
class IndoorMapBody extends StatefulWidget {
  const IndoorMapBody({
    super.key,
    required this.buildingId,
    this.onRouteVisibleChanged,
    this.onStoreTap,
    this.onPlacingLocationChanged,
    this.outerOverlayKeys = const [],
  });

  final String buildingId;

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
  StreamSubscription<PdrSnapshot>? _pdrSnapshotSub;
  StreamSubscription<CalibrationStatus>? _pdrCalibrationSub;
  bool _placingPdrAnchor = false;
  PdrDebugSessionRecorder? _pdrDebugRecorder;

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

  /// 백엔드 연결 실패 시 사용자에게 보여줄 메시지. null이면 정상 상태.
  /// 이게 없으면 fetch 예외가 조용히 삼켜져 로딩 스피너가 영원히 멈추지 않는다.
  String? _error;

  @override
  void initState() {
    super.initState();
    _debugModeController.addListener(_onDebugModeChanged);
    _pdrTrailState = DebugPdrTrailState.fromCurrent(
      snapshot: indoorNavigationDriver.currentSnapshot,
      calibration: indoorNavigationDriver.currentCalibration,
    );
    _pdrSnapshotSub = indoorNavigationDriver.snapshots.listen((snapshot) {
      _pdrDebugRecorder?.recordSnapshot(snapshot);
      if (mounted) setState(() => _pdrTrailState.recordSnapshot(snapshot));
    });
    _pdrCalibrationSub = indoorNavigationDriver.calibration.listen((status) {
      if (mounted) {
        setState(() {
          _pdrDebugRecorder?.recordCalibration(status);
          _pdrTrailState.recordCalibration(status);
        });
        if (status.phase == CalibrationPhase.calibrated ||
            status.phase == CalibrationPhase.uncalibrated) {
          _setPlacingAnchor(false);
        }
      }
    });
    _loadBuilding();
  }

  @override
  void dispose() {
    _pdrSnapshotSub?.cancel();
    _pdrCalibrationSub?.cancel();
    // 앱 전역 인스턴스라 dispose하지 않는다 — 여기서 버리면 야외 지도가
    // 같은 컨트롤러를 계속 구독하고 있다가 notifyListeners에서 죽는다.
    _debugModeController.removeListener(_onDebugModeChanged);
    _mapCameraBearingNotifier.dispose();
    super.dispose();
  }

  void _onDebugModeChanged() {
    final enabled = _debugModeController.enabled;
    if (!enabled &&
        indoorNavigationDriver.currentRuntimeStatus.state !=
            PdrRuntimeState.idle) {
      unawaited(_stopPdrWhenDebugModeTurnsOff());
    }
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

  Future<void> _stopPdrWhenDebugModeTurnsOff() async {
    if (indoorNavigationDriver.currentRuntimeStatus.state ==
        PdrRuntimeState.idle) {
      return;
    }
    await indoorNavigationDriver.stopGuidance();
    if (mounted) _setPlacingAnchor(false);
  }

  @override
  void didUpdateWidget(covariant IndoorMapBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.buildingId != widget.buildingId) {
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
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '지도를 불러오지 못했습니다. 서버 연결을 확인해주세요.');
    }
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
      _highlightedStoreId = null;
    });
    if (hadRouteVisible != _hasActiveRoute) {
      widget.onRouteVisibleChanged?.call(_hasActiveRoute);
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
  /// PDR이 아직 켜지지 않았으면 이 층으로 세션을 새로 시작한 뒤 앵커 대기
  /// 상태로 넘어가고, 이미 켜져 있으면 (다른 층으로 갈 때처럼) 앵커만 다시
  /// 잡도록 대기 상태로만 돌린다. 실제 탭 처리는 기존 [_onMapPressedForPdr]가
  /// 그대로 맡는다.
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
    if (indoorNavigationDriver.currentRuntimeStatus.state ==
        PdrRuntimeState.idle) {
      setState(() {
        _pdrTrailState.beginNewSession();
      });
      _pdrDebugRecorder = PdrDebugSessionRecorder();
      _pdrDebugRecorder?.recordRuntime(
        indoorNavigationDriver.currentRuntimeStatus,
      );
      await indoorNavigationDriver.startGuidance(floorId: floor);
      _pdrDebugRecorder?.recordRuntime(
        indoorNavigationDriver.currentRuntimeStatus,
      );
      if (!mounted) return;
    }
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
  }

  /// 같은 층 안에서 계산한 경로를 지도에 얹는다. 기존 흐름과 동일.
  Future<void> _computeAndShowSingleFloorRoute({
    required String floor,
    required String endNodeId,
    String? explicitOriginNodeId,
  }) async {
    if (floor != _selectedFloor) {
      await _selectFloor(floor);
      if (!mounted) return;
    }
    final floorPlan = _floorPlan;
    if (floorPlan == null) return;

    setState(() {
      // 새 목적지를 받을 때마다 초기화해서, 이번 경로가 계산되면 지도가
      // 전체 경로에 맞춰 다시 줌아웃되게 한다(FloorPlanView의 null→값 전환).
      _route = null;
      _multiFloorRoute = null;
    });

    final startNodeId = explicitOriginNodeId ??
        _pickStartNodeIdOnFloor(floor, excludingNodeId: endNodeId);
    if (startNodeId == null) {
      _showPdrMessage('출발 위치를 먼저 지정해주세요. 하단 "위치 지정" 버튼으로 이 층 위에 시작점을 탭하면 됩니다.');
      widget.onRouteVisibleChanged?.call(false);
      return;
    }
    final route = await buildingRepository.getShortestRoute(
      widget.buildingId,
      floor,
      startNodeId,
      endNodeId,
    );
    if (!mounted) return;
    if (route == null) {
      setState(() => _route = null);
      widget.onRouteVisibleChanged?.call(false);
      _showPdrMessage('경로를 찾지 못했습니다. 다른 매장을 골라보거나 출발지를 다시 지정해주세요.');
      return;
    }
    setState(() => _route = route);
    widget.onRouteVisibleChanged?.call(true);
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

    final startNodeId = explicitOriginNodeId ??
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

    final route = computeMultiFloorRoute(buildingGraph, startNodeId, endNodeId);
    if (!mounted) return;
    if (route == null || route.isEmpty) {
      setState(() {
        _route = null;
        _multiFloorRoute = null;
      });
      widget.onRouteVisibleChanged?.call(false);
      _showPdrMessage('층 간 경로를 찾지 못했습니다. 엘리베이터/에스컬레이터 연결을 확인해주세요.');
      return;
    }

    // 다층 경로 상태로 확정. 현재 표시 중인 층이 세그먼트를 가지고 있으면
    // 그 세그먼트를 화면에 그리고, 아니면 상단 층 selector로 갈아탈 때
    // _selectFloor가 그 층 세그먼트를 자동으로 얹는다.
    setState(() {
      _multiFloorRoute = route;
      _route = route.segmentForFloor(_selectedFloor ?? '')?.route;
    });
    widget.onRouteVisibleChanged?.call(true);

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
  String? _pickStartNodeIdOnFloor(
    String floorName, {
    String? excludingNodeId,
  }) {
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
      anchor.anchorLocalM.eastM,
      anchor.anchorLocalM.northM,
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
    });
    widget.onRouteVisibleChanged?.call(false);
  }

  /// ETA 카드가 지금 화면에 노출돼야 하는지. 단일 층 경로는 이 층에 실제
  /// 폴리라인이 있을 때만 노출하지만, 다층 경로는 어느 층을 보고 있든 계속
  /// 노출한다 — 사용자가 "여기서 어디로 얼마 걸어가야 하는지" 상시 알기 위함.
  bool get _hasActiveRoute =>
      _multiFloorRoute != null || _route != null;

  /// ETA에 쓸 거리. 다층 경로면 층 전체 합, 단일 층이면 그 층 세그먼트 거리.
  double _etaDistanceMeters(IndoorRoute? currentFloorRoute) {
    final multi = _multiFloorRoute;
    if (multi != null) return multi.totalDistanceMeters;
    return currentFloorRoute?.distanceMeters ?? 0;
  }

  /// ETA 라벨. 다층 경로에서는 어떤 층/이동수단으로 가는지 요약을 덧붙여
  /// 사용자가 "지금 이 층에 안 그려진 이유"를 이해할 수 있게 한다.
  String _etaLabel(PoiSearchResult destination) {
    final multi = _multiFloorRoute;
    if (multi == null) return '${destination.name}까지';
    final buffer = StringBuffer('${destination.name}까지');
    for (var index = 0; index < multi.segments.length; index++) {
      final segment = multi.segments[index];
      buffer.write(index == 0 ? ' · ${segment.floorName}' : ' → ${segment.floorName}');
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
    return snapshot.preview.path
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

  /// confirmed PDR path를 floor graph의 통행 간선에 스냅한 결과다. 매 snapshot
  /// 전체를 시간순으로 다시 매칭해 matcher의 간선 전환 히스테리시스도 유지한다.
  List<PdrLocalPoint> get _pdrMatchedFloorPath {
    final graph = _floorGraph;
    final confirmed = _pdrConfirmedFloorPath;
    if (graph == null || confirmed.isEmpty) return const [];
    // 단순 스냅 점들을 직선으로 잇지 않는다. 간선이 바뀌는 경우에는 반드시
    // 두 점 사이의 graph 경로(복도·교차점)를 펼친다.
    return FloorMapMatcher(graph).matchRoutedPath(confirmed);
  }

  Set<String> get _pdrMatchedEdgeIds {
    final graph = _floorGraph;
    final confirmed = _pdrConfirmedFloorPath;
    if (graph == null || !_hasMeaningfulPdrMovement(confirmed)) return const {};
    return FloorMapMatcher(
      graph,
    ).matchPath(confirmed).map((point) => point.edgeId).toSet();
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
    final path = _pdrMatchedFloorPath;
    if (graph == null || path.isEmpty) return null;
    final current = path.last;
    final wgs84 = fitFloorGeoTransform(
      graph.nodes,
    ).apply(current.eastM, current.northM);
    return ll.LatLng(wgs84.$1, wgs84.$2);
  }

  double? get _pdrCurrentHeadingDeg {
    final snapshot = _pdrTrailState.snapshot;
    final anchor = _pdrTrailState.anchor;
    if (snapshot == null || anchor == null || !snapshot.hasHeading) return null;
    return normalizePdrBearing(snapshot.walkingHeadingDeg + anchor.rotationDeg);
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

  List<ll.LatLng> get _pdrConfirmedPathPoints =>
      _floorPathToWgs84(_pdrConfirmedFloorPath);

  List<ll.LatLng> get _pdrRawPathPoints => _floorPathToWgs84(_pdrRawFloorPath);

  List<ll.LatLng> get _pdrRoninPathPoints =>
      _floorPathToWgs84(_pdrRoninFloorPath);

  Future<void> _togglePdr() async {
    final floor = _selectedFloor;
    final graph = _floorGraph;
    if (floor == null ||
        graph == null ||
        graph.nodes.isEmpty ||
        graph.edges.isEmpty) {
      _showPdrMessage('이 층은 PDR 좌표 변환용 navigation graph가 아직 없습니다.');
      return;
    }
    if (indoorNavigationDriver.currentRuntimeStatus.state !=
        PdrRuntimeState.idle) {
      final recorder = _pdrDebugRecorder;
      final snapshot = indoorNavigationDriver.currentSnapshot;
      if (snapshot != null) recorder?.recordSnapshot(snapshot);
      await indoorNavigationDriver.stopGuidance();
      recorder?.recordRuntime(indoorNavigationDriver.currentRuntimeStatus);
      recorder?.recordPedometerFinalize(
        indoorNavigationDriver.lastPedometerFinalizeInfo,
      );
      if (mounted) {
        _setPlacingAnchor(false);
        if (recorder?.hasSnapshot ?? false) {
          _showPdrMessageWithExport('PDR 세션이 종료됐습니다. JSON으로 내보내 분석할 수 있습니다.');
        }
      }
      return;
    }
    setState(() {
      _pdrTrailState.beginNewSession();
    });
    _pdrDebugRecorder = PdrDebugSessionRecorder();
    _pdrDebugRecorder?.recordRuntime(
      indoorNavigationDriver.currentRuntimeStatus,
    );
    await indoorNavigationDriver.startGuidance(floorId: floor);
    _pdrDebugRecorder?.recordRuntime(
      indoorNavigationDriver.currentRuntimeStatus,
    );
    if (!mounted) return;
    _setPlacingAnchor(true);
    _showPdrMessage('현재 서 있는 위치를 지도에서 한 번 탭해 PDR 시작점을 맞춰주세요.');
  }

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

  Future<void> _confirmPdrAnchor(PdrLocalPoint floorPoint) async {
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
    final pdrActive =
        indoorNavigationDriver.currentRuntimeStatus.state !=
        PdrRuntimeState.idle;
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
    final current = pdrCurrent ?? _pdrAnchorLocation;

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
          currentHeadingDegrees: pdrCurrent == null
              ? null
              : _pdrCurrentHeadingDeg,
          // 핀은 매장 중심(centroid)이 아니라 실제 도착 노드(경로의 마지막
          // 점 = 매장 입구)에 찍는다. 경로가 아직 계산되기 전 짧은 순간에는
          // 경로 정보가 없으므로 centroid로 폴백해 핀이 아예 안 보이는
          // 상태를 만들지 않는다. 단, 다층 경로에서는 도착지 층을 보고 있을
          // 때만 도착 핀을 표시한다(중간 층은 지나가는 층이라 핀이 없어야 함).
          destination: _destinationPinForCurrentFloor(route, routeDestination),
          routePoints: route?.points ?? const [],
          pdrPathPoints:
              debugEnabled && _debugModeController.showMapMatchedPdrPath
              ? _pdrMatchedPathPoints
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
                nodeId: selected.entranceNodeId,
                category: selected.category,
                subcategory: selected.subcategory,
              ),
            );
          },
          interactive: _interactive,
          highlightedStoreId: _highlightedStoreId,
          visibleInsets: EdgeInsets.fromLTRB(0, topOverlay, 0, bottomOverlay),
          overlayHitTest: _isTapOnMapOverlay,
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
            bottom: _floorSelectorBottomOffset +
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
                  active: pdrActive,
                  onPressed: _togglePdr,
                  canExport:
                      !pdrActive && (_pdrDebugRecorder?.hasSnapshot ?? false),
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
                  distanceMeters: _etaDistanceMeters(route),
                  minutes: (_etaDistanceMeters(route) /
                          _walkingSpeedMetersPerSecond /
                          60)
                      .ceil()
                      .clamp(1, 999),
                  label: _etaLabel(routeDestination),
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
