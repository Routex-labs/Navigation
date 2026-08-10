import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../models/floor_graph.dart';
import '../contract/pdr_anchor.dart';
import 'corridor_position_tracker.dart';
import 'corridor_tracking_session.dart';
import 'indoor_guidance_position.dart';
import 'indoor_location_estimate.dart';

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
  IndoorGuidanceSession({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  final CorridorTrackingSession _corridor = CorridorTrackingSession();

  bool _attached = false;
  String? _buildingId;
  String? _floorId;
  FloorGraph? _graph;
  PdrAnchor? _anchor;
  PdrSnapshot? _snapshot;
  IndoorLocationEstimate? _estimate;

  bool get isAttached => _attached;
  String? get buildingId => _buildingId;
  String? get floorId => _floorId;

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

  void _resetTracking() {
    _corridor.reset();
    _snapshot = null;
    _anchor = null;
    _floorId = null;
    _graph = null;
  }

  /// 지금 보고 있는 층과 그 층의 그래프를 알려 준다.
  ///
  /// 층이 바뀌면 보정을 버린다. 같은 local m 숫자가 층마다 다른 자리를
  /// 가리키므로, 이전 층 상태를 들고 가면 새 층 첫 프레임이 엉뚱한 복도에
  /// 붙는다.
  void setContext({required String? floorId, required FloorGraph? graph}) {
    if (!_attached) return;
    final floorChanged = floorId != _floorId;
    _floorId = floorId;
    _graph = graph;
    if (floorChanged) {
      _corridor.reset();
      _snapshot = null;
    }
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
    required int timestampMs,
  }) {
    if (!_attached) return null;
    _snapshot = snapshot;
    final anchor = _anchor;
    if (anchor == null || anchor.floorId != _floorId) return null;
    return _corridor.update(
      graph: _graph,
      anchor: anchor,
      snapshot: snapshot,
      timestampMs: timestampMs,
    );
  }

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
        return GuidancePosition(
          localM: result.previewPosition,
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
