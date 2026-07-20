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
import '../../models/building.dart';
import '../../models/floor_graph.dart';
import '../../models/floor_plan.dart';
import '../../models/indoor_route.dart';
import '../../models/poi_search_result.dart';
import '../../theme/app_theme.dart';
import '../../widgets/eta_card.dart';
import '../../widgets/floor_plan_view.dart';

const _walkingSpeedMetersPerSecond = 1.2;

// MapShellScreen이 지도 위에 얹는 상단 검색바/하단 홈-실내 버튼바가 지도를
// 가리는 두께. 축소 하한 계산이 "실제 보이는 영역" 기준으로 되려면 이만큼
// 잘라서 뷰포트로 넘겨야 한다. 각 위젯의 SafeArea 안쪽 padding + Material
// 내용 높이(48px IconButton, 44px 모드 세그먼트 등)를 합해 눈으로 재본 값.
const _mapShellTopChromePx = 68.0;
const _mapShellBottomChromePx = 112.0;

// IndoorMapBody 자신이 얹는 오버레이(층/건물명 인포바, 경로 ETA 카드) 높이.
// 인포바는 top=78 지점에 있고, 위쪽 여백을 포함해 약 30px 세로를 차지한다.
const _indoorInfoBarBottomPx = 30.0 + 78.0;
const _etaCardHeightPx = 130.0;

// 사용자가 매장 내부/건물 밖을 탭했을 때 멀리 떨어진 복도로 강제 스냅하지
// 않기 위한 상한이다. 입구나 매장 앞을 누르는 정상적인 경우에는 충분히
// 여유를 두되, 잘못 눌러 건물 반대편에서 PDR이 시작하는 일은 막는다.
const _maxPdrAnchorSnapDistanceM = 12.0;

// MapShellScreen이 route 표시 시 MapBottomBar(홈/실내 세그먼트)를 위로 리프트
// 하는 양. PDR 버튼도 이 값만큼 같이 올라야 홈/실내 버튼과 세로 정렬이 유지된다.
// map_shell_screen.dart의 _etaBarLiftHeight와 동일해야 한다.
const _bottomBarLiftPx = 92.0;

// MapBottomBar 내부의 하단 패딩(홈/실내 세그먼트 하단 여백). PDR 버튼을
// 같은 하단 여백으로 붙여야 두 버튼이 시각적으로 같은 baseline에 놓인다.
const _bottomBarInnerBottomPaddingPx = 14.0;

/// 실내 지도 본문(층 평면도 + 경로/매장 오버레이). 검색창·길찾기·건물 전환 같은
/// 공통 UI는 [MapShellScreen]이 상단/하단 바로 얹으므로 여기서는 다루지 않는다.
class IndoorMapBody extends StatefulWidget {
  const IndoorMapBody({
    super.key,
    required this.buildingId,
    this.onRouteVisibleChanged,
    this.onStoreTap,
    this.outerOverlayKeys = const [],
  });

  final String buildingId;

  /// ETA 카드가 화면 최하단에 새로 나타나거나 사라질 때 호출된다.
  /// 상위(MapShellScreen)가 이 값으로 하단 공용 바를 그 위로 띄운다.
  final ValueChanged<bool>? onRouteVisibleChanged;

  /// 지도 위 매장 폴리곤을 탭하면 호출된다. 상위(MapShellScreen)가 검색
  /// 결과를 탭했을 때와 똑같이 매장 정보 시트를 띄운다.
  final ValueChanged<PoiSearchResult>? onStoreTap;

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
  PoiSearchResult? _routeDestination;
  bool _interactive = true;

  // 지도 위에 얹은 오버레이(층 selector, PDR 버튼 등) 영역을 map click 처리기
  // 에서 배제하기 위한 GlobalKey들. MapLibre PlatformView가 Flutter gesture
  // arena를 우회하는 문제 때문에 오버레이 위 탭도 뒤의 매장까지 함께 클릭되는
  // 문제를 여기서 명시적으로 걸러낸다.
  final _floorSelectorKey = GlobalKey();
  final _pdrControlKey = GlobalKey();
  final _debugModeSettingsKey = GlobalKey();

  /// [globalPoint]가 지도 위 오버레이 영역 안이면 true — 그 좌표의 지도 탭은
  /// 매장 선택 처리를 건너뛰어야 한다. 자체 오버레이(층 selector, PDR)와
  /// 상위가 넘겨준 outer 오버레이(검색창·저장 장소·하단 바 등)를 모두 검사한다.
  bool _isTapOnMapOverlay(Offset globalPoint) {
    for (final key in [
      _floorSelectorKey,
      _pdrControlKey,
      _debugModeSettingsKey,
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
  bool _exportingPdrDebugJson = false;
  double _mapCameraBearingDeg = 0;
  final ValueNotifier<double> _mapCameraBearingNotifier = ValueNotifier(0);
  final GlobalKey _pdrShareButtonKey = GlobalKey();
  late final DebugModeController _debugModeController;

  /// 검색·길찾기 시트가 지도 위에 떠 있는 동안 지도 제스처를 꺼서, 시트를
  /// 마우스 휠로 스크롤할 때 그 아래 지도까지 같이 움직이지 않게 한다.
  void setInteractive(bool value) {
    if (_interactive == value) return;
    setState(() => _interactive = value);
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
    _debugModeController = DebugModeController()
      ..addListener(_onDebugModeChanged);
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
          if (status.phase == CalibrationPhase.calibrated ||
              status.phase == CalibrationPhase.uncalibrated) {
            _placingPdrAnchor = false;
          }
        });
      }
    });
    _loadBuilding();
  }

  @override
  void dispose() {
    _pdrSnapshotSub?.cancel();
    _pdrCalibrationSub?.cancel();
    _debugModeController
      ..removeListener(_onDebugModeChanged)
      ..dispose();
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
    if (mounted) setState(() => _placingPdrAnchor = false);
  }

  @override
  void didUpdateWidget(covariant IndoorMapBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.buildingId != widget.buildingId) {
      _route = null;
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
    final hadRoute = _route != null;
    setState(() {
      _selectedFloor = floor;
      _floorPlan = null;
      _floorGraph = null;
      _mapCalibrationVersion = 'unversioned';
      // 층을 바꾸면 이전 경로는 다른 층 지도 위에 남아 있어도 의미가 없다.
      _route = null;
      _routeDestination = null;
      _highlightedStoreId = null;
    });
    if (hadRoute) widget.onRouteVisibleChanged?.call(false);
    if (indoorNavigationDriver.currentRuntimeStatus.state !=
        PdrRuntimeState.idle) {
      await indoorNavigationDriver.changeFloor(floorId: floor);
      if (mounted) setState(() => _placingPdrAnchor = true);
    }
    await _loadFloorPlan(floor);
  }

  /// 위치 보정 버튼. 실제 PDR 위치 연동 전까지는 별도로 보정할 상태가 없어
  /// 재조회만 트리거하는 자리표시자다 — PDR이 붙으면 이 자리에서 재보정한다.
  Future<void> recalibrate() async {
    final floor = _selectedFloor;
    if (floor != null) await _loadFloorPlan(floor);
  }

  /// 길찾기 시트에서 도착지를 고르면 호출된다. 목적지가 다른 층이면 그 층으로
  /// 먼저 전환한 뒤 최단 경로(다익스트라)를 조회해 지도 위에 표시한다.
  ///
  /// [origin]을 주면(매장 정보 시트의 "출발지로 설정") 그 매장의 입구 노드를
  /// 시작점으로 쓰고, 없으면 기존처럼 현재 위치에서 가장 가까운 매장 입구를
  /// 자동으로 고른다.
  Future<void> showRouteTo(
    PoiSearchResult destination, {
    PoiSearchResult? origin,
  }) async {
    if (destination.floor != _selectedFloor) {
      await _selectFloor(destination.floor);
      await _loadFloorPlan(destination.floor);
    }
    if (!mounted) return;
    final floorPlan = _floorPlan;
    if (floorPlan == null) return;
    setState(() {
      _routeDestination = destination;
      // 새 목적지를 받을 때마다 초기화해서, 이번 경로가 계산되면 지도가
      // 전체 경로에 맞춰 다시 줌아웃되게 한다(FloorPlanView의 null→값 전환).
      _route = null;
    });

    final endNodeId = destination.nodeId;
    final startNodeId =
        origin?.nodeId ??
        _pickStartNodeId(floorPlan, excludingNodeId: endNodeId);
    if (endNodeId == null) return;
    if (startNodeId == null) {
      _showPdrMessage('출발 위치를 먼저 지정해주세요. PDR 시작 후 입구 또는 복도를 탭하면 됩니다.');
      return;
    }

    final route = await buildingRepository.getShortestRoute(
      widget.buildingId,
      destination.floor,
      startNodeId,
      endNodeId,
    );
    if (!mounted) return;
    setState(() => _route = route);
    widget.onRouteVisibleChanged?.call(route != null);
  }

  /// PDR anchor 또는 확정 PDR 위치에서 가장 가까운 매장 입구 노드를 고른다.
  /// 위치를 모르는 상태에서 도면 중심을 출발점으로 추정하지 않는다.
  String? _pickStartNodeId(FloorPlan floorPlan, {String? excludingNodeId}) {
    final origin = _pdrCurrentLocation ?? _pdrAnchorLocation;
    if (origin == null) return null;
    StorePolygon? nearest;
    double? nearestDistance;
    for (final store in floorPlan.stores) {
      final nodeId = store.entranceNodeId;
      if (nodeId == null || nodeId == excludingNodeId) continue;
      final distance = wgs84DistanceMeters(origin, store.centroid);
      if (nearestDistance == null || distance < nearestDistance) {
        nearestDistance = distance;
        nearest = store;
      }
    }
    return nearest?.entranceNodeId;
  }

  void _clearRoute() {
    setState(() {
      _route = null;
      _routeDestination = null;
    });
    widget.onRouteVisibleChanged?.call(false);
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
      if (mounted) {
        setState(() => _placingPdrAnchor = false);
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
    setState(() => _placingPdrAnchor = true);
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

  Future<void> _confirmPdrAnchor(PdrLocalPoint floorPoint) async {
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
    setState(() => _placingPdrAnchor = false);
    _showPdrMessage('시작점을 통로에 맞췄습니다. 이동 경로는 통로 그래프를 따라 표시됩니다.');
  }

  Future<void> _cancelPdrAnchor() async {
    if (!_placingPdrAnchor) return;
    await indoorNavigationDriver.stopGuidance();
    _pdrDebugRecorder?.recordRuntime(
      indoorNavigationDriver.currentRuntimeStatus,
    );
    if (mounted) setState(() => _placingPdrAnchor = false);
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
          (_route != null ? _etaCardHeightPx : 0) +
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
          (_route != null ? _etaCardHeightPx : 0) +
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
          bottom: _route != null ? _bottomBarLiftPx : 0,
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
    final pdrCurrent = debugEnabled ? _pdrCurrentLocation : null;
    final debugOverlay = debugEnabled
        ? buildDebugMapOverlay(
            _floorGraph,
            showNodes: _debugModeController.showGraphNodes,
            showEdges: _debugModeController.showGraphEdges,
            activeEdgeIds: _pdrMatchedEdgeIds,
          )
        : const DebugMapOverlay();
    // PDR anchor 또는 실제 route가 없을 때 도면 중심을 가짜 현재 위치로
    // 그리지 않는다. 실내 PDR은 시작 위치를 모르면 절대 위치를 알 수 없다.
    final current =
        pdrCurrent ??
        (debugEnabled ? _pdrAnchorLocation : null) ??
        ((route != null && route.points.isNotEmpty)
            ? route.points.first
            : null);

    // 지도가 화면 끝까지 그려지지만 위/아래 UI에 실제로 가려지는 두께를 계산해
    // FloorPlanView에 넘긴다. 축소 하한이 이 "가려지지 않는 세로 영역"에 맞춰
    // 잡혀야 하한에 도달했을 때 건물의 위/아래가 오버레이 뒤로 밀리지 않는다.
    // 인포바는 위쪽 대각선 공간만 살짝 차지해 vertical fit에 큰 영향은 없지만,
    // 하한이 아주 살짝 더 넉넉해지도록 top에 포함해 둔다.
    final systemPadding = MediaQuery.paddingOf(context);
    final topOverlay =
        systemPadding.top + _mapShellTopChromePx + _indoorInfoBarBottomPx;
    final bottomOverlay =
        systemPadding.bottom +
        _mapShellBottomChromePx +
        (route != null ? _etaCardHeightPx : 0);

    return Stack(
      children: [
        FloorPlanView(
          key: ValueKey('${widget.buildingId}-$_selectedFloor'),
          buildingId: widget.buildingId,
          floorName: _selectedFloor!,
          floorPlan: floorPlan,
          currentLocation: current,
          currentHeadingDegrees: pdrCurrent == null
              ? null
              : _pdrCurrentHeadingDeg,
          destination: routeDestination?.point,
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

        // 모바일에서 status bar 높이만큼 아래로 내려온 검색창(MapTopBar) 밑에
        // 층 chip이 깔리지 않도록 SafeArea로 감싼다. 웹/데스크톱은 SafeArea.top이
        // 0이라 기존 위치가 그대로 유지된다. 같은 이유로 _FavoritesPill,
        // _PdrMapControl 등 다른 상단 오버레이도 모두 SafeArea를 쓰고 있다.
        Positioned(
          top: 78,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: _IndoorInfoBar(
              building: building,
              selectedFloor: _selectedFloor,
              onSelectFloor: _selectFloor,
              floorSelectorKey: _floorSelectorKey,
            ),
          ),
        ),

        // PDR 제어는 검색창 아래의 장소·층 선택 chip과 같은 줄에 둔다.
        // 하단에는 디버그 설정 진입점만 남겨 일반 지도 chrome과 역할을 나눈다.
        if (debugEnabled)
          Positioned(
            top: 78,
            left: 92,
            child: SafeArea(
              bottom: false,
              child: _PdrMapControl(
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

        if (debugEnabled && _placingPdrAnchor)
          Positioned(
            top: 130,
            left: 12,
            right: 12,
            child: SafeArea(child: _PdrAnchorHint(onCancel: _cancelPdrAnchor)),
          ),

        if (route != null && routeDestination != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: EtaCard(
                  distanceMeters: route.distanceMeters,
                  minutes:
                      (route.distanceMeters / _walkingSpeedMetersPerSecond / 60)
                          .ceil()
                          .clamp(1, 999),
                  label: '${routeDestination.name}까지',
                  onClose: _clearRoute,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 지도 톤을 해치지 않는 compact PDR 시작/종료 제어. 강한 파란 큰 버튼 대신
/// 실제 지도 앱처럼 흰 surface 위에 상태 색만 얹어, 지도와 현재 위치가
/// 시각적으로 우선되게 한다.
class _PdrMapControl extends StatelessWidget {
  const _PdrMapControl({
    super.key,
    required this.active,
    required this.onPressed,
    required this.canExport,
    required this.exporting,
    required this.onExport,
    required this.shareButtonKey,
  });

  final bool active;
  final VoidCallback onPressed;
  final bool canExport;
  final bool exporting;
  final VoidCallback onExport;
  final GlobalKey shareButtonKey;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFD93025) : AppColors.indoor;
    return Tooltip(
      message: active ? 'PDR 종료' : 'PDR 시작',
      child: Material(
        color: Colors.white.withValues(alpha: 0.96),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.16),
        shape: StadiumBorder(
          side: BorderSide(color: color.withValues(alpha: active ? 0.36 : 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onPressed,
              customBorder: const StadiumBorder(),
              child: Padding(
                padding: EdgeInsets.fromLTRB(10, 8, canExport ? 7 : 13, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        active
                            ? Icons.stop_rounded
                            : Icons.directions_walk_rounded,
                        size: 17,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      active ? 'PDR 종료' : 'PDR 시작',
                      style: TextStyle(
                        color: active
                            ? const Color(0xFFB3261E)
                            : const Color(0xFF202124),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (canExport) ...[
              Container(width: 1, height: 24, color: const Color(0xFFE0E3E7)),
              IconButton(
                key: shareButtonKey,
                tooltip: 'PDR 디버그 JSON 공유',
                onPressed: exporting ? null : onExport,
                icon: exporting
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share_rounded, size: 20),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 시작 위치를 지도에 놓는 동안에만 보이는 간결한 안내. SnackBar만으로는 손이
/// 지도 위에 올라간 뒤 안내가 사라져 어디를 눌러야 하는지 놓치기 쉬워서, 지도
/// chrome 바로 아래에 남겨 둔다.
class _PdrAnchorHint extends StatelessWidget {
  const _PdrAnchorHint({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.97),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            const Icon(
              Icons.touch_app_outlined,
              color: AppColors.indoor,
              size: 21,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '입구 또는 복도에 시작점을 탭하세요',
                maxLines: 2,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'PDR 취소',
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

/// 건물명 + 현재 층 + (여러 층이면) 층 전환 칩을 묶은 오버레이 정보 바.
/// 예전에는 이 내용이 전용 Scaffold 상단바였지만, 검색/길찾기/건물전환은
/// 이제 [MapShellScreen]의 공용 상단바가 맡으므로 여기서는 "지금 보고
/// 있는 건물/층이 어디인지"만 알려주는 보조 역할만 한다.
class _IndoorInfoBar extends StatelessWidget {
  const _IndoorInfoBar({
    required this.building,
    required this.selectedFloor,
    required this.onSelectFloor,
    this.floorSelectorKey,
  });

  final Building building;
  final String? selectedFloor;
  final ValueChanged<String> onSelectFloor;

  /// _FloorSelector에 붙일 GlobalKey. 부모(IndoorMapBody)가 이 key로 selector
  /// 의 화면 영역을 알아내 지도 클릭 이벤트에서 제외하는 데 쓴다.
  final GlobalKey? floorSelectorKey;

  @override
  Widget build(BuildContext context) {
    final floors = building.floors;
    final selectedFloor = this.selectedFloor;
    if (floors.isEmpty || selectedFloor == null) {
      return const SizedBox.shrink();
    }
    // 검색창 오른쪽 아래에 정렬된 층 selector만 남긴다. 건물 이름 라벨은
    // 지도 위 chrome을 최소화하고자 제거했다 — 이미 건물 전환 시트에서
    // 어느 건물인지 확인할 수 있다.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Align(
        alignment: Alignment.topRight,
        child: _FloorSelector(
          key: floorSelectorKey,
          floors: floors,
          selectedFloor: selectedFloor,
          onSelectFloor: onSelectFloor,
        ),
      ),
    );
  }
}

/// 검색창 오른쪽 아래에 놓이는 접이식 층 선택기. 기본 상태에서는 현재 층
/// 한 개만 chip으로 뜨고, 누르면 나머지 층이 세로로 펼쳐진다. 다른 층을
/// 고르거나 바깥을 탭하면 다시 접힌다.
///
/// 층이 하나뿐이면 접고 펴는 의미가 없으므로 단순 표시용 chip만 보인다.
class _FloorSelector extends StatefulWidget {
  const _FloorSelector({
    super.key,
    required this.floors,
    required this.selectedFloor,
    required this.onSelectFloor,
  });

  final List<String> floors;
  final String selectedFloor;
  final ValueChanged<String> onSelectFloor;

  @override
  State<_FloorSelector> createState() => _FloorSelectorState();
}

class _FloorSelectorState extends State<_FloorSelector> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  void _pick(String floor) {
    if (floor != widget.selectedFloor) widget.onSelectFloor(floor);
    setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedFloor;
    final floors = widget.floors;
    if (floors.length <= 1) {
      return _FloorChip(label: selected, active: true, onTap: () {});
    }
    // 다른 층은 selected를 뺀 채 백엔드가 준 순서(위층 → 아래층, 엘리베이터
    // 버튼판과 동일)로 세로로 떨어뜨린다.
    final others = floors.where((f) => f != selected).toList(growable: false);
    // 12개 층(6F~B6)이면 전부 펼쳤을 때 화면 밖으로 넘친다. 펼침 영역은 화면
    // 높이의 절반으로 묶고 그 안에서 스크롤시킨다.
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.5;
    return TapRegion(
      onTapOutside: (_) {
        if (_expanded) setState(() => _expanded = false);
      },
      // MapLibre가 PlatformView라, 지도 위 Flutter 오버레이를 탭해도 그 아래
      // 네이티브 지도의 onMapClick이 그대로 함께 발화해 뒤에 있는 매장이
      // 같이 눌리는 문제가 있다. 이 GestureDetector로 selector 영역의 모든
      // 탭을 opaque로 흡수해서 새어나가지 않게 한다. 내부 chip InkWell은
      // nested라 자기 tap을 그대로 받고, chip 사이 간격이나 stadium 외곽
      // 모서리의 빈 공간만 여기가 소비한다.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        // IntrinsicWidth + crossAxisAlignment.stretch로 Column의 폭을 trigger
        // chip(화살표까지 포함해 가장 넓다)에 맞추고, 아래 옵션 chip들이 그
        // 폭으로 늘어나 모든 chip 크기가 동일해 보이게 한다.
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FloorChip(
                label: selected,
                active: true,
                onTap: _toggle,
                // 접힘 상태에서는 아래로 펼칠 수 있음을 표시하고, 펼침 상태에서는
                // 다시 접을 수 있음을 표시한다. 색은 active chip 톤에 맞춰 흰색.
                trailing: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              if (_expanded)
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxListHeight),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final floor in others) ...[
                          const SizedBox(height: 6),
                          _FloorChip(
                            label: floor,
                            active: false,
                            onTap: () => _pick(floor),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloorChip extends StatelessWidget {
  const _FloorChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  /// 층 라벨 오른쪽에 붙일 아이콘 등의 위젯. 드롭다운 trigger에서
  /// expand_more/expand_less 아이콘을 붙이는 데 쓴다.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // Material에 shape를 지정하고 clipBehavior: antiAlias를 주면 InkWell
    // splash/hover/focus 하이라이트가 stadium 밖으로 새지 않고 chip 모양
    // 안에서 잘려서 그려진다. 이전 구현(BoxDecoration 위 InkWell)에서는
    // 클릭·포커스 시 아주 살짝 네모난 하이라이트 상자가 비쳤다.
    final shape = StadiumBorder(
      side: BorderSide(
        color: active ? AppColors.indoor : const Color(0x14000000),
        width: 1.5,
      ),
    );
    return SizedBox(
      height: 30,
      child: Material(
        color: active ? AppColors.indoor : Colors.white,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        elevation: active ? 3 : 1.5,
        shadowColor: active
            ? AppColors.indoor.withValues(alpha: 0.38)
            : Colors.black.withValues(alpha: 0.16),
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Padding(
            // trailing이 있는 trigger chip은 텍스트를 왼쪽, 화살표를 오른쪽
            // 가장자리에 붙여 드롭다운 형태를 명확히 하고, 옵션 chip은 늘어난
            // 폭 안에서 텍스트를 가운데 정렬해 균형을 잡는다.
            padding: EdgeInsets.symmetric(
              horizontal: trailing == null ? 12 : 12,
            ),
            child: trailing == null
                ? Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : AppColors.muted,
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : AppColors.muted,
                        ),
                      ),
                      trailing!,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
