import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../models/building_graph.dart';
import '../../../models/floor_graph.dart';
import '../contract/altitude_sample.dart';
import '../contract/pdr_anchor.dart';
import '../contract/raw_motion_activity.dart';
import 'corridor_position_tracker.dart';
import 'corridor_tracking_session.dart';
import 'escalator_transition_detector.dart';
import 'indoor_guidance_position.dart';
import 'indoor_location_estimate.dart';

/// 기압 샘플 한 건이 만들어 낸 층 이동 신호들.
///
/// 셋을 한 번에 돌려주는 이유는 셋이 **서로 다른 시점의 같은 이동**을 가리키기
/// 때문이다. 화면은 순서대로(시작 → 취소 → 확정) 처리해야 층·경로 복원이
/// 어긋나지 않는다.
class EscalatorAltitudeOutcome {
  const EscalatorAltitudeOutcome({
    this.started,
    this.cancelled,
    this.confirmed,
    this.events = const [],
  });

  /// 후보가 열려 목적 층 지도를 여는 시점.
  final EscalatorTransition? started;

  /// 열렸던 후보가 되돌아간 경우. 층·경로를 원래대로 복원해야 한다.
  final EscalatorTransition? cancelled;

  /// 하차가 확정된 시점. 새 앵커를 잡는다.
  final EscalatorTransition? confirmed;

  /// 판정 로그. 레코더가 없어도 세션은 비워서 넘긴다 — 안 그러면 다음 안내
  /// 세션 로그에 지난 판정이 섞인다.
  final List<EscalatorDetectionEvent> events;

  bool get isEmpty =>
      started == null && cancelled == null && confirmed == null;
}

/// 탑승 판정이 가리키는 노드가 **안내가 지목한 탑승점**이면 그 좌표, 아니면 null.
///
/// 판정기는 경로와 무관한 근접만으로도 단계를 올린다. 그 근거로 마커를 고정하면
/// 에스컬레이터 옆을 스쳐 지나가는 사용자의 위치가 그 자리에 붙어 버린다 —
/// 그냥 걷고 있는 사람의 마커를 세우는 것이다. 그래서 세 가지가 모두 맞을
/// 때만 고정한다.
///
/// 1. 앵커가 지금 보고 있는 층에 있다(다른 층 노드에 고정하면 남의 층 좌표다).
/// 2. 이 층 세그먼트가 실제로 **에스컬레이터로** 갈아타는 구간이다.
/// 3. 길찾기가 고른 전이 노드가 판정기가 고른 탑승 노드와 **같다**.
PdrLocalPoint? routeBoardingHoldPoint({
  required String? boardingNodeId,
  required String? anchorFloorId,
  required String? displayedFloorId,
  required MultiFloorRoute? multiFloorRoute,
  required FloorGraph? graph,
}) {
  if (boardingNodeId == null ||
      anchorFloorId == null ||
      anchorFloorId != displayedFloorId) {
    return null;
  }
  final segment = multiFloorRoute?.segmentForFloor(anchorFloorId);
  if (segment == null ||
      segment.transferModeToNext != 'escalator' ||
      segment.transferFromNodeId != boardingNodeId) {
    return null;
  }
  final node = graph?.nodes.where((n) => n.id == boardingNodeId).firstOrNull;
  return node == null ? null : PdrLocalPoint(node.xM, node.yM);
}

/// 실내 안내에서 **"지금 어디에 있는가"** 하나를 소유하는 headless 세션.
///
/// 이 클래스가 생긴 이유는 같은 판단이 두 화면에 따로 구현돼 있었기 때문이다.
/// 실내 탭은 복도 보정 위치를 그렸고, 홈 지도는 같은 tracker를 돌려 놓고도
/// 결과를 읽지 않은 채 앵커를 고정 표시했다. 두 화면이 다른 위치를 그리면
/// 어느 쪽이 맞는지 사용자도 우리도 알 수 없다.
///
/// 세션은 **위젯을 모른다.** 지도 레이어·카메라·도면 로딩은 화면 몫이고,
/// 여기서는 센서 입력을 받아 위치 한 건과 그 출처를 내준다.
///
/// ## 부착(attach)이 왜 필요한가
///
/// 홈 지도에는 "실내 오버레이가 꺼진 상태"가 있다. 예전에는 그 상태에서도
/// 복도 보정이 계속 돌았다 — 화면에 안 보일 뿐 걸음은 트래커에 쌓이고 있었다.
/// 야외를 걸어 다닌 거리가 실내 좌표계에 누적되다가, 다시 실내로 들어오는
/// 순간 엉뚱한 곳에서 시작한다. [attach]/[detach]로 그 구간을 명시적으로 끊는다.
class IndoorGuidanceSession {
  IndoorGuidanceSession({
    DateTime Function()? now,
    int Function()? nowMs,
    EscalatorTransitionDetector? escalator,
  }) : _now = now ?? DateTime.now,
       _nowMs = nowMs ?? _defaultNowMs,
       _escalator = escalator ?? EscalatorTransitionDetector();

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  final DateTime Function() _now;
  final int Function() _nowMs;

  final CorridorTrackingSession _corridor = CorridorTrackingSession();
  final EscalatorTransitionDetector _escalator;

  bool _attached = false;
  String? _buildingId;
  String? _floorId;
  List<String> _floorLabels = const [];
  FloorGraph? _graph;
  PdrAnchor? _anchor;
  PdrSnapshot? _snapshot;
  IndoorLocationEstimate? _estimate;
  MultiFloorRoute? _multiFloorRoute;

  /// 탑승 판정 중 위치를 고정할 지점. 안내가 지목한 탑승점일 때만 채워진다.
  PdrLocalPoint? _boardingHoldPointM;

  bool get isAttached => _attached;
  String? get buildingId => _buildingId;
  String? get floorId => _floorId;

  /// 층 판정기 진단값. 디버그 칩과 레코더가 읽는다.
  EscalatorTransitionDetector get escalator => _escalator;

  /// 탑승점에 고정 중인지. 화면은 이 구간에서 경로 진행률을 갱신하지 않는다.
  PdrLocalPoint? get boardingHoldPointM => _boardingHoldPointM;

  /// 복도 보정 결과 원본. 디버그 궤적과 경로 진행률이 함께 쓴다.
  CorridorTrackingResult? get trackingResult =>
      _attached ? _corridor.result : null;

  CorridorObservation? get lastObservation => _corridor.lastObservation;
  bool get lastWasReset => _corridor.lastWasReset;
  CorridorTrackingSession get corridor => _corridor;

  /// 실내 안내를 켠다. 이미 같은 건물에 붙어 있으면 아무것도 하지 않는다 —
  /// 여기서 무조건 초기화하면 층 오버레이를 다시 그릴 때마다 보정이 리셋된다.
  void attach({required String buildingId}) {
    if (_attached && _buildingId == buildingId) return;
    _attached = true;
    _buildingId = buildingId;
    _resetTracking();
  }

  /// 실내 안내를 끈다. 야외로 나갔거나 오버레이를 닫은 상태다.
  ///
  /// 보정 상태를 **버린다.** 남겨 두면 야외에서 걸은 거리가 다음 진입에
  /// 이월되고, 사용자는 건물에 들어서자마자 엉뚱한 자리에 서 있다.
  void detach() {
    if (!_attached) return;
    _attached = false;
    _buildingId = null;
    _resetTracking();
  }

  /// 탑승점 고정만 푼다.
  ///
  /// 단계 전이가 아니라 화면 쪽 출구(되돌리기·취소 정리)에서 탑승이 끝나는
  /// 경로가 있다. 그 경로가 고정을 안 풀면 마커가 탑승점에 붙은 채 남는다.
  void clearBoardingHold() {
    _boardingHoldPointM = null;
  }

  /// 부착·층·경로는 그대로 두고 **보정만** 처음부터 다시 본다.
  ///
  /// 새 PDR 세션을 시작했거나 앵커를 다시 찍은 경우다. [detach]와 달리 층·
  /// 그래프·경로를 버리지 않는다 — 그것까지 버리면 다음 스냅샷이 올 때까지
  /// 화면이 컨텍스트 없는 상태로 남는다.
  void resetTracking() {
    _corridor.reset();
    _snapshot = null;
    _boardingHoldPointM = null;
  }

  void _resetTracking() {
    _corridor.reset();
    _snapshot = null;
    _anchor = null;
    _floorId = null;
    _graph = null;
    _multiFloorRoute = null;
    _boardingHoldPointM = null;
  }

  /// 지금 보고 있는 층과 그 층의 그래프를 알려 준다.
  ///
  /// 층이 바뀌면 보정과 탑승점 고정을 버린다. 같은 local m 숫자가 층마다 다른
  /// 자리를 가리키므로, 이전 층 상태를 들고 가면 새 층 첫 프레임이 엉뚱한
  /// 복도에 붙는다.
  ///
  /// **층 판정기에는 탑승 중이 아닐 때만 알린다.** 조기 전환 뒤 화면은 목적
  /// 층을 먼저 보여주지만, 판정기는 탑승 층의 baseline과 노드 허가를 하차까지
  /// 유지해야 한다. 이 규칙이 깨지면 긴 에스컬레이터 중간에 0점이 다시 잡혀
  /// 남은 반 층이 또 하나의 층 이동으로 보인다.
  void setContext({
    required String? floorId,
    required FloorGraph? graph,
    List<String>? floorLabels,
  }) {
    if (!_attached) return;
    final floorChanged = floorId != _floorId;
    _floorId = floorId;
    _graph = graph;
    if (floorLabels != null) _floorLabels = floorLabels;
    if (floorChanged) {
      _corridor.reset();
      _snapshot = null;
      _boardingHoldPointM = null;
    }
    if (_escalator.pendingTransition == null) {
      _escalator.updateContext(
        floorLabel: floorId,
        graph: graph,
        floorLabels: _floorLabels,
      );
    }
  }

  /// 지금 안내 중인 다층 경로. 탑승점 고정과 경로 접근 판정이 쓴다.
  void setRoute(MultiFloorRoute? multiFloorRoute) {
    _multiFloorRoute = multiFloorRoute;
    if (multiFloorRoute == null) _boardingHoldPointM = null;
  }

  /// 보정 기준점. 확정 전(`canRenderPosition`이 false)에는 null로 준다.
  void setAnchor(PdrAnchor? anchor) {
    if (!_attached) return;
    _anchor = anchor;
  }

  /// GPS·입구에서 온 절대 위치 추정. 앵커가 없을 때만 화면에 쓰인다.
  ///
  /// 앵커를 **덮지 않는다.** 오래된 GPS가 최신 PDR을 되돌리는 사고를 구조적으로
  /// 막으려면 둘이 다른 자리에 있어야 한다.
  void setEstimate(IndoorLocationEstimate? estimate) {
    _estimate = estimate;
  }

  /// 새 PDR 스냅샷을 보정에 넣는다. 부착 상태가 아니면 **버린다**.
  ///
  /// 앵커가 지금 보고 있는 층에 없으면 보정을 돌리지 않는다. 다른 층 기준점으로
  /// 이 층 복도에 스냅하면 마커가 남의 층 복도를 따라 걸어간다.
  CorridorTrackingResult? onSnapshot(
    PdrSnapshot? snapshot, {
    int? timestampMs,
  }) {
    if (!_attached) return null;
    _snapshot = snapshot;
    final anchor = _anchor;
    if (anchor == null || anchor.floorId != _floorId) return null;
    final atMs = timestampMs ?? _nowMs();
    final result = _corridor.update(
      graph: _graph,
      anchor: anchor,
      snapshot: snapshot,
      timestampMs: atMs,
    );
    if (result == null) return null;
    _feedEscalator(result, snapshot, atMs);
    return result;
  }

  /// 보정 위치를 층 판정기에 먹인다.
  ///
  /// **원시 PDR 좌표가 아니라 보정된 위치를 준다.** 원시 좌표를 주면 앵커
  /// 오차만큼 에스컬레이터 노드 근접 판정이 어긋난다.
  void _feedEscalator(
    CorridorTrackingResult result,
    PdrSnapshot? snapshot,
    int atMs,
  ) {
    final steps = snapshot?.steps ?? 0;
    _escalator.onPosition(
      positionM: result.correctedPosition,
      steps: steps,
      timestampMs: atMs,
    );

    // 안내가 이 층에서 에스컬레이터로 갈아타라고 했으면, 경로가 지목한 탑승
    // 노드를 판정기에 함께 알린다. 붙어 있는 레인 중 어느 것을 타는지는 센서로
    // 가릴 수 없고 길찾기만 안다.
    final floor = _floorId;
    final segment = floor == null
        ? null
        : _multiFloorRoute?.segmentForFloor(floor);
    final route = segment?.route;
    if (segment != null &&
        segment.transferModeToNext == 'escalator' &&
        segment.transferFromNodeId != null &&
        route != null &&
        route.pointsLocalM.isNotEmpty) {
      final routeEnd = route.pointsLocalM.last;
      _escalator.onEscalatorRouteApproach(
        positionM: result.previewPosition,
        routeEndM: PdrLocalPoint(routeEnd.x, routeEnd.y),
        expectedBoardingNodeId: segment.transferFromNodeId!,
        expectedArrivalNodeId: segment.transferToNodeId,
        steps: steps,
        timestampMs: atMs,
      );
    }
  }

  /// 기압 샘플 한 건을 판정기에 넣는다.
  ///
  /// 부착 상태가 아니면 **넣지 않는다.** 야외에서 오르내린 고도가 실내 판정의
  /// 0점을 흔들면, 건물에 들어서자마자 있지도 않은 층 이동이 잡힌다.
  EscalatorAltitudeOutcome onAltitude(AltitudeSample sample) {
    if (!_attached) return const EscalatorAltitudeOutcome();
    final confirmed = _escalator.onAltitude(sample);
    return EscalatorAltitudeOutcome(
      started: _escalator.takeStartedTransition(),
      cancelled: _escalator.takeCancelledTransition(),
      confirmed: confirmed,
      events: _escalator.takeEvents(),
    );
  }

  void onRawMotion(RawMotionActivity activity) {
    if (!_attached) return;
    _escalator.onRawMotion(activity);
  }

  /// 쌓인 단계 전이를 꺼내면서 탑승점 고정을 함께 갱신한다.
  ///
  /// 고정을 **여기 한 곳에서만** 걸고 푼다. 화면이 따로 조건을 세면 판정기가
  /// 멀어짐·타임아웃으로 단계를 취소했을 때 한쪽에 고정이 남는다.
  List<EscalatorPhaseChange> takePhaseChanges() {
    if (!_attached) return const [];
    final changes = _escalator.takePhaseChanges();
    for (final change in changes) {
      switch (change.phase) {
        case EscalatorPhase.boardingDetected:
        case EscalatorPhase.verticalMotionDetected:
          _boardingHoldPointM = _routeBoardingHoldPoint(change);
        case EscalatorPhase.cancelled:
        case EscalatorPhase.failed:
        case EscalatorPhase.idle:
          _boardingHoldPointM = null;
        case EscalatorPhase.midpointReached:
        case EscalatorPhase.landed:
          break;
      }
    }
    return changes;
  }

  PdrLocalPoint? _routeBoardingHoldPoint(EscalatorPhaseChange change) =>
      routeBoardingHoldPoint(
        boardingNodeId: change.boardingNodeId,
        anchorFloorId: _anchor?.floorId,
        displayedFloorId: _floorId,
        multiFloorRoute: _multiFloorRoute,
        graph: _graph,
      );

  /// 지금 화면이 그려야 하는 위치와 그 출처.
  ///
  /// 우선순위가 이 함수의 전부다.
  ///
  /// 1. **보정된 걸음 위치**(tracked) — 앵커가 이 층에 있고 보정 결과가 있다.
  /// 2. **앵커 자리**(anchorOnly) — 앵커는 이 층에 있는데 아직 걸음이 없다.
  /// 3. **추정점**(estimate) — 앵커가 없거나 다른 층이다. 신선한 값만.
  ///
  /// 순서가 뒤집히면 안 되는 이유는 3번이 30초까지 살아 있기 때문이다. 추정을
  /// 먼저 보면, 걸어서 이미 20m를 이동한 사용자를 30초 전 GPS 자리로 되돌린다.
  GuidancePosition? get position {
    if (!_attached) return null;

    final anchor = _anchor;
    final onThisFloor = anchor != null && anchor.floorId == _floorId;

    if (onThisFloor) {
      final result = _corridor.result;
      if (result != null) {
        // 탑승점에 고정 중이면 걸음이 더 세어져도 그 자리다. 에스컬레이터 앞에
        // 선 뒤의 걸음은 발판 위 진동이거나 대기 중 제자리 움직임이라, 그대로
        // 두면 마커가 탑승점을 지나 앞 매장으로 흘러간다.
        return GuidancePosition(
          localM: _boardingHoldPointM ?? result.previewPosition,
          source: GuidancePositionSource.tracked,
          headingDeg: _floorHeadingDeg(anchor),
        );
      }
      return GuidancePosition(
        localM: anchor.anchorLocalM,
        source: GuidancePositionSource.anchorOnly,
      );
    }

    final estimate = _estimate;
    if (estimate == null ||
        estimate.buildingId != _buildingId ||
        estimate.floorId != _floorId ||
        !estimate.isFresh(_now())) {
      return null;
    }
    return GuidancePosition(
      localM: estimate.localM,
      source: GuidancePositionSource.estimate,
      accuracyM: estimate.accuracyMeters,
    );
  }

  /// 마커 원뿔이 쓰는 층 기준 방향.
  ///
  /// 간선 방위(`previewHeadingDeg`)가 아니라 orientation heading을 쓴다. 간선
  /// 방위는 걸음이 있어야 갱신되고 직선 복도에서는 제자리 회전에 반응하지
  /// 않아서, 서서 몸을 돌리면 화면 방향이 얼어붙는다.
  double? _floorHeadingDeg(PdrAnchor anchor) {
    final snapshot = _snapshot;
    if (snapshot == null) return null;
    return FloorCoordinateTransform(
      anchor,
    ).toFloorBearing(snapshot.orientationHeadingDeg);
  }
}
