import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../models/floor_graph.dart';
import '../contract/pdr_anchor.dart';

enum CorridorTrackingState {
  straightTracking,
  turnPending,
  nodeConfirmed,
  uncertain,
}

class CorridorTrackerConfig {
  const CorridorTrackerConfig({
    this.straightStableMs = 2000,
    this.junctionRadiusM = 4,
    this.turnThresholdDeg = 15,
    this.turnObservationMs = 500,
    this.newDirectionHoldMs = 1000,
    this.newEdgeHeadingToleranceDeg = 20,
    this.minimumNewEdgeProgressM = 1.5,
    this.turnTimeoutMs = 4000,
    this.turnDistanceLimitM = 4,
    this.positionCorrectionFraction = 0.25,
    this.maxHeadingCorrectionPerStepDeg = 0.75,
    this.straightHeadingSpreadDeg = 12,
    this.uncertainReacquireMs = 1500,
    this.uncertainReacquireDistanceM = 2,
    this.maxPathPoints = 800,
  });

  final int straightStableMs;
  final double junctionRadiusM;
  final double turnThresholdDeg;
  final int turnObservationMs;
  final int newDirectionHoldMs;
  final double newEdgeHeadingToleranceDeg;
  final double minimumNewEdgeProgressM;
  final int turnTimeoutMs;
  final double turnDistanceLimitM;
  final double positionCorrectionFraction;
  final double maxHeadingCorrectionPerStepDeg;
  final double straightHeadingSpreadDeg;
  final int uncertainReacquireMs;
  final double uncertainReacquireDistanceM;
  final int maxPathPoints;
}

class CorridorObservation {
  const CorridorObservation({
    required this.timestampMs,
    required this.rawConfirmedPosition,
    required this.confirmedSteps,
    required this.confirmedDistanceM,
    required this.rawPreviewPosition,
    required this.previewSteps,
    required this.sensorHeadingDeg,
    required this.hasHeading,
    this.rawConfirmedStepPositions = const [],
  });

  final int timestampMs;
  final PdrLocalPoint rawConfirmedPosition;
  final int confirmedSteps;
  final double confirmedDistanceM;
  final PdrLocalPoint rawPreviewPosition;
  final int previewSteps;
  final double sensorHeadingDeg;
  final bool hasHeading;

  /// 직전 snapshot 이후 초록 경로에 추가된 걸음별 floor 좌표.
  ///
  /// 코어가 stepPeakTimes와 과거 heading으로 이미 복원한 점들이므로, 배치
  /// 수신 시점의 최신 heading 하나로 전체 배치를 다시 그리지 않는다.
  final List<PdrLocalPoint> rawConfirmedStepPositions;
}

class CorridorTrackingResult {
  const CorridorTrackingResult({
    required this.state,
    required this.correctedPosition,
    required this.correctedHeadingDeg,
    required this.headingBiasDeg,
    required this.currentEdgeId,
    required this.pendingEdgeId,
    required this.lastConfirmedNodeId,
    required this.correctedPath,
    required this.rawConfirmedPosition,
    required this.rawPreviewPosition,
  });

  final CorridorTrackingState state;
  final PdrLocalPoint correctedPosition;
  final double correctedHeadingDeg;
  final double headingBiasDeg;
  final String? currentEdgeId;
  final String? pendingEdgeId;
  final String? lastConfirmedNodeId;
  final List<PdrLocalPoint> correctedPath;
  final PdrLocalPoint rawConfirmedPosition;
  final PdrLocalPoint rawPreviewPosition;
}

/// 초록·주황 원본을 수정하지 않고 실제 위치만 graph 제약으로 누적 보정한다.
///
/// 직선에서는 현재 간선을 잠근 채 위치 잔차와 heading bias를 천천히 줄인다.
/// 간선 전환은 연결 노드 근처에서 주황 heading으로 후보를 만든 뒤, 초록
/// confirmed 거리로 노드 도달 가능성과 새 간선 진행거리를 확인한 경우만 한다.
class CorridorPositionTracker {
  CorridorPositionTracker(
    FloorGraph graph, {
    this.config = const CorridorTrackerConfig(),
  }) : _network = _CorridorNetwork(graph);

  final CorridorTrackerConfig config;
  final _CorridorNetwork _network;
  final List<PdrLocalPoint> _correctedPath = [];
  final List<({int atMs, double headingDeg})> _headingWindow = [];

  CorridorTrackingState _state = CorridorTrackingState.uncertain;
  _CorridorEdge? _currentEdge;
  PdrLocalPoint _correctedPosition = PdrLocalPoint.zero;
  PdrLocalPoint _rawConfirmedPosition = PdrLocalPoint.zero;
  PdrLocalPoint _rawPreviewPosition = PdrLocalPoint.zero;
  double _sensorHeadingDeg = 0;
  double _headingBiasDeg = 0;
  int _lastConfirmedSteps = 0;
  double _lastConfirmedDistanceM = 0;
  int _lastPreviewSteps = 0;
  int _straightSinceMs = 0;
  int _lastWalkingAtMs = 0;
  String? _lastConfirmedNodeId;

  _TurnEvidence? _turn;
  String? _liveTurnEdgeId;
  String? _liveTurnNodeId;
  int? _liveTurnSinceMs;
  String? _uncertainCandidateEdgeId;
  int? _uncertainCandidateSinceMs;
  double _uncertainCandidateDistanceM = 0;

  bool get isInitialized => _currentEdge != null;

  CorridorTrackingResult get result => CorridorTrackingResult(
    state: _state,
    correctedPosition: _correctedPosition,
    correctedHeadingDeg: _normalizeBearing(_sensorHeadingDeg + _headingBiasDeg),
    headingBiasDeg: _headingBiasDeg,
    currentEdgeId: _currentEdge?.id,
    pendingEdgeId: _turn?.candidateEdge.id ?? _uncertainCandidateEdgeId,
    lastConfirmedNodeId: _lastConfirmedNodeId,
    correctedPath: List.unmodifiable(_correctedPath),
    rawConfirmedPosition: _rawConfirmedPosition,
    rawPreviewPosition: _rawPreviewPosition,
  );

  void reset({
    required PdrLocalPoint initialPosition,
    required double initialHeadingDeg,
    required int timestampMs,
    int initialConfirmedSteps = 0,
    double initialConfirmedDistanceM = 0,
    int initialPreviewSteps = 0,
  }) {
    final nearest = _network.nearestProjection(initialPosition);
    _currentEdge = nearest?.edge;
    _correctedPosition = nearest?.point ?? initialPosition;
    _rawConfirmedPosition = initialPosition;
    _rawPreviewPosition = initialPosition;
    _sensorHeadingDeg = _normalizeBearing(initialHeadingDeg);
    _headingBiasDeg = 0;
    _lastConfirmedSteps = initialConfirmedSteps;
    _lastConfirmedDistanceM = initialConfirmedDistanceM;
    _lastPreviewSteps = initialPreviewSteps;
    _straightSinceMs = timestampMs;
    _lastWalkingAtMs = timestampMs;
    _lastConfirmedNodeId = null;
    _turn = null;
    _clearLiveTurnCandidate();
    _clearUncertainCandidate();
    _headingWindow
      ..clear()
      ..add((atMs: timestampMs, headingDeg: _sensorHeadingDeg));
    _correctedPath
      ..clear()
      ..add(_correctedPosition);
    _state = nearest == null
        ? CorridorTrackingState.uncertain
        : CorridorTrackingState.straightTracking;
  }

  CorridorTrackingResult update(CorridorObservation observation) {
    if (!isInitialized) {
      reset(
        initialPosition: observation.rawConfirmedPosition,
        initialHeadingDeg: observation.sensorHeadingDeg,
        timestampMs: observation.timestampMs,
      );
    }
    final previousRawConfirmedPosition = _rawConfirmedPosition;
    _rawConfirmedPosition = observation.rawConfirmedPosition;
    _rawPreviewPosition = observation.rawPreviewPosition;
    if (observation.hasHeading && observation.sensorHeadingDeg.isFinite) {
      _sensorHeadingDeg = _normalizeBearing(observation.sensorHeadingDeg);
      _recordHeading(observation.timestampMs, _sensorHeadingDeg);
    }

    final deltaSteps = math.max(
      0,
      observation.confirmedSteps - _lastConfirmedSteps,
    );
    final deltaDistanceM = math.max(
      0.0,
      observation.confirmedDistanceM - _lastConfirmedDistanceM,
    );
    final deltaPreviewSteps = math.max(
      0,
      observation.previewSteps - _lastPreviewSteps,
    );
    if (_state == CorridorTrackingState.nodeConfirmed &&
        (deltaSteps > 0 || deltaPreviewSteps > 0)) {
      _state = CorridorTrackingState.straightTracking;
      _straightSinceMs = observation.timestampMs;
    }
    if (deltaSteps > 0 || deltaPreviewSteps > 0) {
      _lastWalkingAtMs = observation.timestampMs;
    }

    if (deltaPreviewSteps > 0 && observation.hasHeading) {
      _observeRealtimeTurn(observation.timestampMs);
    }

    if (deltaDistanceM > 0 && deltaSteps > 0) {
      switch (_state) {
        case CorridorTrackingState.straightTracking:
          _applyStraightConfirmed(
            atMs: observation.timestampMs,
            deltaSteps: deltaSteps,
            deltaDistanceM: deltaDistanceM,
            previousRawConfirmedPosition: previousRawConfirmedPosition,
            rawConfirmedStepPositions: observation.rawConfirmedStepPositions,
          );
        case CorridorTrackingState.turnPending:
          _applyPendingConfirmed(
            atMs: observation.timestampMs,
            deltaDistanceM: deltaDistanceM,
          );
        case CorridorTrackingState.uncertain:
          _applyUncertainConfirmed(
            atMs: observation.timestampMs,
            deltaDistanceM: deltaDistanceM,
          );
        case CorridorTrackingState.nodeConfirmed:
          break;
      }
    }

    if (_state == CorridorTrackingState.turnPending) {
      final turn = _turn;
      final reachableDistanceLimitM = turn == null
          ? config.turnDistanceLimitM
          : math.max(
              config.turnDistanceLimitM,
              turn.distanceToNodeM + config.minimumNewEdgeProgressM,
            );
      if (turn != null &&
          (observation.timestampMs - turn.startedAtMs >= config.turnTimeoutMs ||
              turn.confirmedDistanceM >= reachableDistanceLimitM)) {
        _state = CorridorTrackingState.uncertain;
        _turn = null;
        _straightSinceMs = observation.timestampMs;
      }
    }

    _lastConfirmedSteps = math.max(
      _lastConfirmedSteps,
      observation.confirmedSteps,
    );
    _lastConfirmedDistanceM = math.max(
      _lastConfirmedDistanceM,
      observation.confirmedDistanceM,
    );
    _lastPreviewSteps = math.max(_lastPreviewSteps, observation.previewSteps);
    return result;
  }

  void _applyStraightConfirmed({
    required int atMs,
    required int deltaSteps,
    required double deltaDistanceM,
    required PdrLocalPoint previousRawConfirmedPosition,
    required List<PdrLocalPoint> rawConfirmedStepPositions,
  }) {
    final edge = _currentEdge;
    if (edge == null) return;
    final correctedHeading = _normalizeBearing(
      _sensorHeadingDeg + _headingBiasDeg,
    );
    final junction = _network.nearestConnectedNodeOn(
      edge,
      _correctedPosition,
      maxDistanceM: config.junctionRadiusM,
    );
    final continuation = junction == null
        ? null
        : _network.bestOutgoing(
            nodeId: junction.node.id,
            excludingEdgeId: edge.id,
            headingDeg: correctedHeading,
            toleranceDeg: config.newEdgeHeadingToleranceDeg,
          );
    final towardJunction =
        junction != null &&
        _headingError(
              correctedHeading,
              edge.bearingTowardNode(junction.node.id),
            ) <=
            config.newEdgeHeadingToleranceDeg;
    final continuesSameDirection =
        junction != null &&
        continuation != null &&
        _headingError(
              edge.bearingTowardNode(junction.node.id),
              continuation.edge.bearingAwayFromNode(junction.node.id),
            ) <=
            config.newEdgeHeadingToleranceDeg;
    if (continuation != null &&
        towardJunction &&
        continuesSameDirection &&
        junction.distanceM <= deltaDistanceM + 0.35) {
      final leftoverM = math.max(0.0, deltaDistanceM - junction.distanceM);
      _confirmNodeTransition(
        node: junction.node,
        edge: continuation.edge,
        progressM: leftoverM,
        atMs: atMs,
      );
      return;
    }

    final rawSegments = <({double headingDeg, double distanceM})>[];
    var rawCursor = previousRawConfirmedPosition;
    var rawTotalM = 0.0;
    for (final rawPoint in rawConfirmedStepPositions) {
      final movement = rawPoint - rawCursor;
      rawCursor = rawPoint;
      if (movement.distance <= 1e-6) continue;
      rawSegments.add((
        headingDeg: pdrBearingForDirection(movement),
        distanceM: movement.distance,
      ));
      rawTotalM += movement.distance;
    }
    if (rawSegments.isEmpty || rawTotalM <= 1e-6) {
      final fallbackSteps = math.max(1, deltaSteps);
      for (var index = 0; index < fallbackSteps; index += 1) {
        rawSegments.add((
          headingDeg: _sensorHeadingDeg,
          distanceM: deltaDistanceM / fallbackSteps,
        ));
      }
      rawTotalM = deltaDistanceM;
    }
    final distanceScale = rawTotalM <= 1e-6 ? 1.0 : deltaDistanceM / rawTotalM;
    for (final segment in rawSegments) {
      _integrateStraightStep(
        atMs: atMs,
        rawHeadingDeg: segment.headingDeg,
        stepDistanceM: segment.distanceM * distanceScale,
      );
    }
  }

  void _integrateStraightStep({
    required int atMs,
    required double rawHeadingDeg,
    required double stepDistanceM,
  }) {
    final edge = _currentEdge;
    if (edge == null || stepDistanceM <= 0) return;
    final correctedHeading = _normalizeBearing(rawHeadingDeg + _headingBiasDeg);
    final radians = correctedHeading * math.pi / 180;
    final integrated = PdrLocalPoint(
      _correctedPosition.eastM + math.sin(radians) * stepDistanceM,
      _correctedPosition.northM + math.cos(radians) * stepDistanceM,
    );
    final projection = edge.project(integrated);
    final farFromJunction =
        _network.nearestJunctionDistance(edge, projection.point) >
        config.junctionRadiusM;
    final stable =
        atMs - _straightSinceMs >= config.straightStableMs &&
        atMs - _lastWalkingAtMs <= 1200 &&
        _headingSpreadDeg <= config.straightHeadingSpreadDeg &&
        farFromJunction;

    if (stable) {
      _correctedPosition = _blend(
        integrated,
        projection.point,
        config.positionCorrectionFraction,
      );
      final targetHeading = edge.closestBearingAt(
        projection.point,
        correctedHeading,
      );
      final requested = _shortestDelta(targetHeading - correctedHeading);
      final maxCorrection = config.maxHeadingCorrectionPerStepDeg;
      _headingBiasDeg = _clampSigned(
        _headingBiasDeg +
            requested.clamp(-maxCorrection, maxCorrection).toDouble(),
        60,
      );
    } else {
      _correctedPosition = integrated;
    }
    _appendCorrected(_correctedPosition);
  }

  void _observeRealtimeTurn(int atMs) {
    final edge = _currentEdge;
    if (edge == null) return;
    final correctedHeading = _normalizeBearing(
      _sensorHeadingDeg + _headingBiasDeg,
    );

    if (_state == CorridorTrackingState.turnPending) {
      final turn = _turn;
      if (turn == null) return;
      final oldDirection = edge.closestBearingAt(
        _correctedPosition,
        correctedHeading,
      );
      if (_headingError(correctedHeading, oldDirection) < 10 &&
          _headingError(
                correctedHeading,
                turn.candidateEdge.bearingAwayFromNode(turn.node.id),
              ) >
              config.newEdgeHeadingToleranceDeg) {
        _state = CorridorTrackingState.straightTracking;
        _turn = null;
        _clearLiveTurnCandidate();
        _straightSinceMs = atMs;
        return;
      }
      final candidate = _network.bestOutgoing(
        nodeId: turn.node.id,
        excludingEdgeId: edge.id,
        headingDeg: correctedHeading,
        toleranceDeg: config.newEdgeHeadingToleranceDeg + 10,
      );
      if (candidate != null && candidate.edge.id != turn.candidateEdge.id) {
        _turn = _TurnEvidence(
          node: turn.node,
          candidateEdge: candidate.edge,
          startedAtMs: turn.startedAtMs,
          candidateSinceMs: atMs,
          distanceToNodeM: turn.distanceToNodeM,
          startedPosition: turn.startedPosition,
        );
      }
      return;
    }

    if (_state == CorridorTrackingState.uncertain) {
      _observeUncertainCandidate(atMs, correctedHeading);
      return;
    }
    if (_state != CorridorTrackingState.straightTracking) return;

    final junction = _network.nearestJunctionOn(
      edge,
      _correctedPosition,
      maxDistanceM: config.junctionRadiusM,
    );
    if (junction == null) {
      _clearLiveTurnCandidate();
      return;
    }
    final currentBearing = edge.bearingTowardNode(junction.node.id);
    if (_headingError(correctedHeading, currentBearing) <
        config.turnThresholdDeg) {
      _clearLiveTurnCandidate();
      return;
    }
    final candidate = _network.bestOutgoing(
      nodeId: junction.node.id,
      excludingEdgeId: edge.id,
      headingDeg: correctedHeading,
      toleranceDeg: config.newEdgeHeadingToleranceDeg + 10,
    );
    if (candidate == null) {
      _clearLiveTurnCandidate();
      return;
    }
    if (_liveTurnEdgeId != candidate.edge.id ||
        _liveTurnNodeId != junction.node.id) {
      _liveTurnEdgeId = candidate.edge.id;
      _liveTurnNodeId = junction.node.id;
      _liveTurnSinceMs = atMs;
      return;
    }
    final liveSince = _liveTurnSinceMs ?? atMs;
    if (atMs - liveSince < config.turnObservationMs) return;
    _turn = _TurnEvidence(
      node: junction.node,
      candidateEdge: candidate.edge,
      startedAtMs: liveSince,
      candidateSinceMs: liveSince,
      distanceToNodeM: junction.distanceM,
      startedPosition: _correctedPosition,
    );
    _clearLiveTurnCandidate();
    _state = CorridorTrackingState.turnPending;
  }

  void _applyPendingConfirmed({
    required int atMs,
    required double deltaDistanceM,
  }) {
    final turn = _turn;
    if (turn == null) return;
    turn.confirmedDistanceM += deltaDistanceM;

    // 확정 전 마커는 기존 간선에서 교차 노드까지만 이동한다. 후보 복도로
    // 미리 들어가거나 임의 노드로 순간이동하지 않는다.
    final oldEdge = _currentEdge;
    if (oldEdge != null) {
      final progressToNode = math.min(
        turn.confirmedDistanceM,
        turn.distanceToNodeM,
      );
      _correctedPosition = oldEdge.pointTowardNode(
        from: turn.startedPosition,
        nodeId: turn.node.id,
        distanceM: progressToNode,
      );
      _appendCorrected(_correctedPosition);
    }

    final newEdgeProgressM = math.max(
      0.0,
      turn.confirmedDistanceM - turn.distanceToNodeM,
    );
    final correctedHeading = _normalizeBearing(
      _sensorHeadingDeg + _headingBiasDeg,
    );
    final headingMatches =
        _headingError(
          correctedHeading,
          turn.candidateEdge.bearingAwayFromNode(turn.node.id),
        ) <=
        config.newEdgeHeadingToleranceDeg;
    final heldLongEnough =
        atMs - turn.candidateSinceMs >= config.newDirectionHoldMs;
    if (headingMatches &&
        heldLongEnough &&
        newEdgeProgressM >= config.minimumNewEdgeProgressM) {
      _confirmNodeTransition(
        node: turn.node,
        edge: turn.candidateEdge,
        progressM: newEdgeProgressM,
        atMs: atMs,
      );
      _turn = null;
    }
  }

  void _applyUncertainConfirmed({
    required int atMs,
    required double deltaDistanceM,
  }) {
    final edge = _currentEdge;
    if (edge == null) return;
    final correctedHeading = _normalizeBearing(
      _sensorHeadingDeg + _headingBiasDeg,
    );
    final radians =
        edge.closestBearingAt(_correctedPosition, correctedHeading) *
        math.pi /
        180;
    final tentative = PdrLocalPoint(
      _correctedPosition.eastM + math.sin(radians) * deltaDistanceM,
      _correctedPosition.northM + math.cos(radians) * deltaDistanceM,
    );
    // 불확실할 때도 현재 간선 투영만 허용한다. 다른 간선이나 노드로는
    // 후보가 확정되기 전까지 절대 옮기지 않는다.
    _correctedPosition = edge.project(tentative).point;
    _appendCorrected(_correctedPosition);
    _uncertainCandidateDistanceM += deltaDistanceM;

    final candidateId = _uncertainCandidateEdgeId;
    final candidateSince = _uncertainCandidateSinceMs;
    if (candidateId == null || candidateSince == null) return;
    final candidate = _network.edgeById(candidateId);
    final junction = _network.nearestJunctionOn(
      edge,
      _correctedPosition,
      maxDistanceM: config.junctionRadiusM,
    );
    if (candidate == null || junction == null) return;
    if (atMs - candidateSince < config.uncertainReacquireMs ||
        _uncertainCandidateDistanceM < config.uncertainReacquireDistanceM) {
      return;
    }
    _confirmNodeTransition(
      node: junction.node,
      edge: candidate,
      progressM: math.max(0, _uncertainCandidateDistanceM - junction.distanceM),
      atMs: atMs,
    );
    _clearUncertainCandidate();
  }

  void _observeUncertainCandidate(int atMs, double headingDeg) {
    final edge = _currentEdge;
    if (edge == null) return;
    final junction = _network.nearestJunctionOn(
      edge,
      _correctedPosition,
      maxDistanceM: config.junctionRadiusM,
    );
    if (junction == null) {
      _clearUncertainCandidate();
      return;
    }
    final candidate = _network.bestOutgoing(
      nodeId: junction.node.id,
      excludingEdgeId: edge.id,
      headingDeg: headingDeg,
      toleranceDeg: config.newEdgeHeadingToleranceDeg,
    );
    if (candidate == null) {
      _clearUncertainCandidate();
      return;
    }
    if (_uncertainCandidateEdgeId == candidate.edge.id) return;
    _uncertainCandidateEdgeId = candidate.edge.id;
    _uncertainCandidateSinceMs = atMs;
    _uncertainCandidateDistanceM = 0;
  }

  void _confirmNodeTransition({
    required _CorridorNode node,
    required _CorridorEdge edge,
    required double progressM,
    required int atMs,
  }) {
    _appendCorrected(node.point);
    _currentEdge = edge;
    _correctedPosition = edge.pointAwayFromNode(
      node.id,
      progressM.clamp(0.0, edge.lengthM).toDouble(),
    );
    _appendCorrected(_correctedPosition);
    _lastConfirmedNodeId = node.id;
    _state = CorridorTrackingState.nodeConfirmed;
    _straightSinceMs = atMs;
    _clearLiveTurnCandidate();
  }

  void _recordHeading(int atMs, double headingDeg) {
    _headingWindow.add((atMs: atMs, headingDeg: headingDeg));
    final oldest = atMs - config.straightStableMs;
    _headingWindow.removeWhere((sample) => sample.atMs < oldest);
  }

  double get _headingSpreadDeg {
    var spread = 0.0;
    for (var left = 0; left < _headingWindow.length; left += 1) {
      for (var right = left + 1; right < _headingWindow.length; right += 1) {
        spread = math.max(
          spread,
          _headingError(
            _headingWindow[left].headingDeg,
            _headingWindow[right].headingDeg,
          ),
        );
      }
    }
    return spread;
  }

  void _appendCorrected(PdrLocalPoint point) {
    if (_correctedPath.isEmpty ||
        (_correctedPath.last - point).distance > 1e-6) {
      _correctedPath.add(point);
      if (_correctedPath.length > config.maxPathPoints) {
        _correctedPath.removeRange(
          0,
          _correctedPath.length - config.maxPathPoints,
        );
      }
    }
  }

  void _clearUncertainCandidate() {
    _uncertainCandidateEdgeId = null;
    _uncertainCandidateSinceMs = null;
    _uncertainCandidateDistanceM = 0;
  }

  void _clearLiveTurnCandidate() {
    _liveTurnEdgeId = null;
    _liveTurnNodeId = null;
    _liveTurnSinceMs = null;
  }
}

class _TurnEvidence {
  _TurnEvidence({
    required this.node,
    required this.candidateEdge,
    required this.startedAtMs,
    required this.candidateSinceMs,
    required this.distanceToNodeM,
    required this.startedPosition,
  });

  final _CorridorNode node;
  final _CorridorEdge candidateEdge;
  final int startedAtMs;
  final int candidateSinceMs;
  final double distanceToNodeM;
  final PdrLocalPoint startedPosition;
  double confirmedDistanceM = 0;
}

class _CorridorNetwork {
  _CorridorNetwork(FloorGraph graph)
    : nodes = {
        for (final node in graph.nodes)
          node.id: _CorridorNode(
            id: node.id,
            point: PdrLocalPoint(node.xM, node.yM),
            type: node.type.toLowerCase(),
          ),
      } {
    for (final graphEdge in graph.edges) {
      final from = nodes[graphEdge.fromNodeId];
      final to = nodes[graphEdge.toNodeId];
      if (from == null || to == null || graphEdge.transferMode != null) {
        continue;
      }
      final geometry = graphEdge.geometryLocalM.length >= 2
          ? graphEdge.geometryLocalM
                .map((point) => PdrLocalPoint(point.x, point.y))
                .toList(growable: false)
          : [from.point, to.point];
      final edge = _CorridorEdge(
        id: graphEdge.id,
        fromNodeId: from.id,
        toNodeId: to.id,
        bidirectional: graphEdge.bidirectional,
        points: geometry,
        accessEdge:
            graphEdge.id.startsWith('store_edge_') ||
            const {'store_entrance', 'poi'}.contains(from.type) ||
            const {'store_entrance', 'poi'}.contains(to.type),
      );
      if (edge.lengthM <= 1e-6) continue;
      edges.add(edge);
      _edgesById[edge.id] = edge;
      _incident.putIfAbsent(from.id, () => []).add(edge);
      _incident.putIfAbsent(to.id, () => []).add(edge);
    }
  }

  final Map<String, _CorridorNode> nodes;
  final List<_CorridorEdge> edges = [];
  final Map<String, _CorridorEdge> _edgesById = {};
  final Map<String, List<_CorridorEdge>> _incident = {};

  _CorridorEdge? edgeById(String id) => _edgesById[id];

  _EdgeProjection? nearestProjection(PdrLocalPoint point) {
    _EdgeProjection? best;
    for (final edge in edges) {
      final projection = edge.project(point);
      if (best == null || projection.distanceM < best.distanceM) {
        best = projection;
      }
    }
    return best;
  }

  _JunctionDistance? nearestJunctionOn(
    _CorridorEdge edge,
    PdrLocalPoint point, {
    required double maxDistanceM,
  }) => _nearestNodeOn(
    edge,
    point,
    maxDistanceM: maxDistanceM,
    accepts: (nodeId) => _isDirectionDecisionNode(edge, nodeId),
  );

  _JunctionDistance? nearestConnectedNodeOn(
    _CorridorEdge edge,
    PdrLocalPoint point, {
    required double maxDistanceM,
  }) => _nearestNodeOn(
    edge,
    point,
    maxDistanceM: maxDistanceM,
    accepts: (nodeId) => (_incident[nodeId]?.length ?? 0) >= 2,
  );

  _JunctionDistance? _nearestNodeOn(
    _CorridorEdge edge,
    PdrLocalPoint point, {
    required double maxDistanceM,
    required bool Function(String nodeId) accepts,
  }) {
    _JunctionDistance? best;
    final projection = edge.project(point);
    for (final nodeId in [edge.fromNodeId, edge.toNodeId]) {
      if (!accepts(nodeId)) continue;
      final node = nodes[nodeId]!;
      final distance = nodeId == edge.fromNodeId
          ? projection.distanceAlongM
          : edge.lengthM - projection.distanceAlongM;
      if (distance > maxDistanceM ||
          best != null && distance >= best.distanceM) {
        continue;
      }
      best = _JunctionDistance(node: node, distanceM: distance);
    }
    return best;
  }

  bool _isDirectionDecisionNode(_CorridorEdge current, String nodeId) {
    final incomingBearing = current.bearingTowardNode(nodeId);
    for (final edge in _incident[nodeId] ?? const []) {
      if (edge.id == current.id || edge.accessEdge) continue;
      if (!edge.bidirectional && edge.fromNodeId != nodeId) continue;
      final outgoingBearing = edge.bearingAwayFromNode(nodeId);
      if (_headingError(incomingBearing, outgoingBearing) > 20) return true;
    }
    return false;
  }

  double nearestJunctionDistance(_CorridorEdge edge, PdrLocalPoint point) =>
      nearestJunctionOn(
        edge,
        point,
        maxDistanceM: double.infinity,
      )?.distanceM ??
      double.infinity;

  _OutgoingEdge? bestOutgoing({
    required String nodeId,
    required String excludingEdgeId,
    required double headingDeg,
    required double toleranceDeg,
  }) {
    _OutgoingEdge? best;
    for (final edge in _incident[nodeId] ?? const []) {
      if (edge.id == excludingEdgeId) continue;
      if (edge.accessEdge) continue;
      if (!edge.bidirectional && edge.fromNodeId != nodeId) continue;
      final bearing = edge.bearingAwayFromNode(nodeId);
      final error = _headingError(headingDeg, bearing);
      if (error > toleranceDeg || best != null && error >= best.errorDeg) {
        continue;
      }
      best = _OutgoingEdge(edge: edge, errorDeg: error);
    }
    return best;
  }
}

class _CorridorNode {
  const _CorridorNode({
    required this.id,
    required this.point,
    required this.type,
  });

  final String id;
  final PdrLocalPoint point;
  final String type;
}

class _CorridorEdge {
  _CorridorEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.bidirectional,
    required this.points,
    required this.accessEdge,
  }) : _lengths = _cumulativeLengths(points);

  final String id;
  final String fromNodeId;
  final String toNodeId;
  final bool bidirectional;
  final List<PdrLocalPoint> points;
  final bool accessEdge;
  final List<double> _lengths;

  double get lengthM => _lengths.last;

  _EdgeProjection project(PdrLocalPoint point) {
    _EdgeProjection? best;
    for (var index = 1; index < points.length; index += 1) {
      final from = points[index - 1];
      final to = points[index];
      final delta = to - from;
      final squared = delta.eastM * delta.eastM + delta.northM * delta.northM;
      if (squared <= 1e-12) continue;
      final rawT =
          ((point.eastM - from.eastM) * delta.eastM +
              (point.northM - from.northM) * delta.northM) /
          squared;
      final t = rawT.clamp(0.0, 1.0).toDouble();
      final projected = PdrLocalPoint(
        from.eastM + delta.eastM * t,
        from.northM + delta.northM * t,
      );
      final segmentLength = math.sqrt(squared);
      final candidate = _EdgeProjection(
        edge: this,
        point: projected,
        distanceM: (point - projected).distance,
        distanceAlongM: _lengths[index - 1] + segmentLength * t,
        tangentBearingDeg: pdrBearingForDirection(delta),
      );
      if (best == null || candidate.distanceM < best.distanceM) {
        best = candidate;
      }
    }
    return best!;
  }

  double closestBearingAt(PdrLocalPoint point, double headingDeg) {
    final projection = project(point);
    final forward = projection.tangentBearingDeg;
    final reverse = _normalizeBearing(forward + 180);
    return _headingError(headingDeg, forward) <=
            _headingError(headingDeg, reverse)
        ? forward
        : reverse;
  }

  double bearingTowardNode(String nodeId) {
    if (nodeId == toNodeId) {
      return pdrBearingForDirection(points.last - points[points.length - 2]);
    }
    return pdrBearingForDirection(points.first - points[1]);
  }

  double bearingAwayFromNode(String nodeId) =>
      _normalizeBearing(bearingTowardNode(nodeId) + 180);

  PdrLocalPoint pointAwayFromNode(String nodeId, double distanceM) =>
      pointAt(nodeId == fromNodeId ? distanceM : lengthM - distanceM);

  PdrLocalPoint pointTowardNode({
    required PdrLocalPoint from,
    required String nodeId,
    required double distanceM,
  }) {
    final start = project(from).distanceAlongM;
    final target = nodeId == toNodeId ? start + distanceM : start - distanceM;
    return pointAt(target.clamp(0.0, lengthM).toDouble());
  }

  PdrLocalPoint pointAt(double distanceM) {
    final target = distanceM.clamp(0.0, lengthM).toDouble();
    for (var index = 1; index < _lengths.length; index += 1) {
      if (target > _lengths[index]) continue;
      final span = _lengths[index] - _lengths[index - 1];
      final t = span <= 1e-12 ? 0.0 : (target - _lengths[index - 1]) / span;
      final from = points[index - 1];
      final to = points[index];
      return PdrLocalPoint(
        from.eastM + (to.eastM - from.eastM) * t,
        from.northM + (to.northM - from.northM) * t,
      );
    }
    return points.last;
  }
}

class _EdgeProjection {
  const _EdgeProjection({
    required this.edge,
    required this.point,
    required this.distanceM,
    required this.distanceAlongM,
    required this.tangentBearingDeg,
  });

  final _CorridorEdge edge;
  final PdrLocalPoint point;
  final double distanceM;
  final double distanceAlongM;
  final double tangentBearingDeg;
}

class _JunctionDistance {
  const _JunctionDistance({required this.node, required this.distanceM});

  final _CorridorNode node;
  final double distanceM;
}

class _OutgoingEdge {
  const _OutgoingEdge({required this.edge, required this.errorDeg});

  final _CorridorEdge edge;
  final double errorDeg;
}

List<double> _cumulativeLengths(List<PdrLocalPoint> points) {
  final result = <double>[0];
  for (var index = 1; index < points.length; index += 1) {
    result.add(result.last + (points[index] - points[index - 1]).distance);
  }
  return result;
}

PdrLocalPoint _blend(PdrLocalPoint from, PdrLocalPoint to, double fraction) =>
    PdrLocalPoint(
      from.eastM + (to.eastM - from.eastM) * fraction,
      from.northM + (to.northM - from.northM) * fraction,
    );

double _normalizeBearing(double value) {
  final normalized = value % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}

double _shortestDelta(double value) {
  final normalized = (value + 180) % 360;
  return (normalized < 0 ? normalized + 360 : normalized) - 180;
}

double _headingError(double left, double right) =>
    _shortestDelta(left - right).abs();

double _clampSigned(double value, double limit) =>
    value.clamp(-limit, limit).toDouble();
