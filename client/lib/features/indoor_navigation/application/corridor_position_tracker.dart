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
    this.maximumConfirmationProgressM = 2.5,
    this.turnTimeoutMs = 4000,
    this.turnDistanceLimitM = 4,
    this.maxHeadingCorrectionPerStepDeg = 0.75,
    this.straightHeadingSpreadDeg = 12,
    this.uncertainReacquireMs = 1500,
    this.uncertainReacquireDistanceM = 2,
    this.recoveryWindowMs = 6000,
    this.recoveryWindowDistanceM = 6,
    this.recoveryCandidateMarginDeg = 8,
    this.maxPathPoints = 800,
  });

  final int straightStableMs;
  final double junctionRadiusM;
  final double turnThresholdDeg;
  final int turnObservationMs;
  final int newDirectionHoldMs;
  final double newEdgeHeadingToleranceDeg;
  final double minimumNewEdgeProgressM;
  final double maximumConfirmationProgressM;
  final int turnTimeoutMs;
  final double turnDistanceLimitM;
  final double maxHeadingCorrectionPerStepDeg;
  final double straightHeadingSpreadDeg;
  final int uncertainReacquireMs;
  final double uncertainReacquireDistanceM;
  final int recoveryWindowMs;
  final double recoveryWindowDistanceM;
  final double recoveryCandidateMarginDeg;
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
    required this.currentEdgeProgressM,
    required this.travelDirectionSign,
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
  final double currentEdgeProgressM;
  final int travelDirectionSign;
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
  final List<_RecoverySegment> _recoverySegments = [];

  CorridorTrackingState _state = CorridorTrackingState.uncertain;
  _CorridorEdge? _currentEdge;
  double _currentProgressM = 0;
  int _travelSign = 1;
  bool _travelDirectionLocked = false;
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
  String? _uncertainCandidateNodeId;
  int _uncertainCandidateTravelSign = 1;
  int? _uncertainCandidateSinceMs;
  double _uncertainCandidateDistanceM = 0;

  bool get isInitialized => _currentEdge != null;

  CorridorTrackingResult get result => CorridorTrackingResult(
    state: _state,
    correctedPosition: _correctedPosition,
    correctedHeadingDeg:
        _currentEdge?.bearingForTravel(_currentProgressM, _travelSign) ??
        _normalizeBearing(_sensorHeadingDeg + _headingBiasDeg),
    headingBiasDeg: _headingBiasDeg,
    currentEdgeId: _currentEdge?.id,
    currentEdgeProgressM: _currentProgressM,
    travelDirectionSign: _travelSign,
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
    final nearest = _network.nearestProjection(
      initialPosition,
      headingDeg: initialHeadingDeg,
    );
    _currentEdge = nearest?.edge;
    _currentProgressM = nearest?.distanceAlongM ?? 0;
    _travelSign = nearest?.edge.directionSignForHeading(initialHeadingDeg) ?? 1;
    _travelDirectionLocked = false;
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
    _recoverySegments.clear();
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
            deltaSteps: deltaSteps,
            deltaDistanceM: deltaDistanceM,
            previousRawConfirmedPosition: previousRawConfirmedPosition,
            rawConfirmedStepPositions: observation.rawConfirmedStepPositions,
          );
        case CorridorTrackingState.uncertain:
          _applyUncertainConfirmed(
            atMs: observation.timestampMs,
            deltaSteps: deltaSteps,
            deltaDistanceM: deltaDistanceM,
            previousRawConfirmedPosition: previousRawConfirmedPosition,
            rawConfirmedStepPositions: observation.rawConfirmedStepPositions,
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
        _enterUncertain(observation.timestampMs);
        _turn = null;
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
    for (final segment in _rawSegments(
      deltaSteps: deltaSteps,
      deltaDistanceM: deltaDistanceM,
      previousRawConfirmedPosition: previousRawConfirmedPosition,
      rawConfirmedStepPositions: rawConfirmedStepPositions,
    )) {
      _integrateStraightStep(
        atMs: atMs,
        rawHeadingDeg: segment.headingDeg,
        stepDistanceM: segment.distanceM,
      );
      if (_state != CorridorTrackingState.straightTracking) break;
    }
  }

  void _integrateStraightStep({
    required int atMs,
    required double rawHeadingDeg,
    required double stepDistanceM,
  }) {
    final edge = _currentEdge;
    if (edge == null || stepDistanceM <= 0) return;
    if (!_travelDirectionLocked) {
      _travelSign = edge.directionSignForHeading(rawHeadingDeg);
      _travelDirectionLocked = true;
    }
    final targetHeading = edge.bearingForTravel(_currentProgressM, _travelSign);
    final farFromJunction =
        _network.nearestJunctionDistance(edge, _correctedPosition) >
        config.junctionRadiusM;
    final stable =
        atMs - _straightSinceMs >= config.straightStableMs &&
        atMs - _lastWalkingAtMs <= 1200 &&
        _headingSpreadDeg <= config.straightHeadingSpreadDeg &&
        farFromJunction;

    if (stable) {
      final correctedRawHeading = _normalizeBearing(
        rawHeadingDeg + _headingBiasDeg,
      );
      final requested = _shortestDelta(targetHeading - correctedRawHeading);
      final maxCorrection = config.maxHeadingCorrectionPerStepDeg;
      _headingBiasDeg = _clampSigned(
        _headingBiasDeg +
            requested.clamp(-maxCorrection, maxCorrection).toDouble(),
        60,
      );
    }
    _advanceStraightOnGraph(
      distanceM: stepDistanceM,
      rawHeadingDeg: rawHeadingDeg,
      atMs: atMs,
    );
  }

  void _advanceStraightOnGraph({
    required double distanceM,
    required double rawHeadingDeg,
    required int atMs,
  }) {
    var remainingM = distanceM;
    var transitions = 0;
    while (remainingM > 1e-6 && transitions < 16) {
      final edge = _currentEdge;
      if (edge == null) return;
      final distanceToEnd = _travelSign > 0
          ? edge.lengthM - _currentProgressM
          : _currentProgressM;
      if (remainingM <= distanceToEnd + 1e-6) {
        _currentProgressM = (_currentProgressM + _travelSign * remainingM)
            .clamp(0.0, edge.lengthM)
            .toDouble();
        _correctedPosition = edge.pointAt(_currentProgressM);
        _appendCorrected(_correctedPosition);
        return;
      }

      _currentProgressM = _travelSign > 0 ? edge.lengthM : 0;
      _correctedPosition = edge.pointAt(_currentProgressM);
      _appendCorrected(_correctedPosition);
      remainingM = math.max(0, remainingM - distanceToEnd);
      final nodeId = edge.nodeAtTravelEnd(_travelSign);
      final incomingBearing = edge.bearingTowardNode(nodeId);
      final continuation = _network.bestStraightContinuation(
        nodeId: nodeId,
        excludingEdgeId: edge.id,
        incomingBearingDeg: incomingBearing,
        toleranceDeg: config.newEdgeHeadingToleranceDeg,
      );
      if (continuation == null ||
          _headingError(
                _normalizeBearing(rawHeadingDeg + _headingBiasDeg),
                continuation.edge.bearingAwayFromNode(nodeId),
              ) >
              config.newEdgeHeadingToleranceDeg + 25) {
        _enterUncertain(atMs);
        return;
      }

      _currentEdge = continuation.edge;
      _travelSign = continuation.edge.travelSignAwayFromNode(nodeId);
      _travelDirectionLocked = true;
      _currentProgressM = _travelSign > 0 ? 0 : continuation.edge.lengthM;
      _correctedPosition = continuation.edge.pointAt(_currentProgressM);
      transitions += 1;
    }
  }

  List<({double headingDeg, double distanceM})> _rawSegments({
    required int deltaSteps,
    required double deltaDistanceM,
    required PdrLocalPoint previousRawConfirmedPosition,
    required List<PdrLocalPoint> rawConfirmedStepPositions,
  }) {
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
      return [
        for (var index = 0; index < fallbackSteps; index += 1)
          (
            headingDeg: _sensorHeadingDeg,
            distanceM: deltaDistanceM / fallbackSteps,
          ),
      ];
    }
    final distanceScale = deltaDistanceM / rawTotalM;
    return [
      for (final segment in rawSegments)
        (
          headingDeg: segment.headingDeg,
          distanceM: segment.distanceM * distanceScale,
        ),
    ];
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
      final oldDirection = edge.bearingForTravel(
        _currentProgressM,
        _travelSign,
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
        final replacement = _TurnEvidence(
          node: turn.node,
          candidateEdge: candidate.edge,
          startedAtMs: turn.startedAtMs,
          candidateSinceMs: atMs,
          distanceToNodeM: turn.distanceToNodeM,
          startedProgressM: turn.startedProgressM,
          oldTravelSign: turn.oldTravelSign,
        )..confirmedDistanceM = turn.confirmedDistanceM;
        _turn = replacement;
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
    if (edge.nodeAtTravelEnd(_travelSign) != junction.node.id) {
      _clearLiveTurnCandidate();
      return;
    }
    final currentBearing = edge.bearingTowardNode(junction.node.id);
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
    final candidateBearing = candidate.edge.bearingAwayFromNode(
      junction.node.id,
    );
    if (_headingError(currentBearing, candidateBearing) <
        config.turnThresholdDeg) {
      _clearLiveTurnCandidate();
      return;
    }
    if (_liveTurnEdgeId != candidate.edge.id ||
        _liveTurnNodeId != junction.node.id) {
      if (_recentHeadingChangeDeg(atMs) < config.turnThresholdDeg) {
        _clearLiveTurnCandidate();
        return;
      }
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
      startedProgressM: _currentProgressM,
      oldTravelSign: _travelSign,
    );
    _clearLiveTurnCandidate();
    _state = CorridorTrackingState.turnPending;
  }

  void _applyPendingConfirmed({
    required int atMs,
    required int deltaSteps,
    required double deltaDistanceM,
    required PdrLocalPoint previousRawConfirmedPosition,
    required List<PdrLocalPoint> rawConfirmedStepPositions,
  }) {
    final turn = _turn;
    if (turn == null) return;
    final candidateBearing = turn.candidateEdge.bearingAwayFromNode(
      turn.node.id,
    );
    for (final segment in _rawSegments(
      deltaSteps: deltaSteps,
      deltaDistanceM: deltaDistanceM,
      previousRawConfirmedPosition: previousRawConfirmedPosition,
      rawConfirmedStepPositions: rawConfirmedStepPositions,
    )) {
      final beforeM = turn.confirmedDistanceM;
      turn.confirmedDistanceM += segment.distanceM;
      final afterNodeBeforeM = math.max(beforeM, turn.distanceToNodeM);
      final afterNodeAfterM = math.max(
        turn.confirmedDistanceM,
        turn.distanceToNodeM,
      );
      final candidateDistanceM = afterNodeAfterM - afterNodeBeforeM;
      if (candidateDistanceM <= 0) continue;
      final segmentHeading = _normalizeBearing(
        segment.headingDeg + _headingBiasDeg,
      );
      if (_headingError(segmentHeading, candidateBearing) <=
          config.newEdgeHeadingToleranceDeg) {
        turn.alignedNewEdgeDistanceM += candidateDistanceM;
      } else {
        turn.alignedNewEdgeDistanceM = 0;
      }
    }

    // 확정 전 마커는 기존 간선에서 교차 노드까지만 이동한다. 후보 복도로
    // 미리 들어가거나 임의 노드로 순간이동하지 않는다.
    final oldEdge = _currentEdge;
    if (oldEdge != null) {
      final progressToNode = math.min(
        turn.confirmedDistanceM,
        turn.distanceToNodeM,
      );
      _currentProgressM =
          (turn.startedProgressM + turn.oldTravelSign * progressToNode)
              .clamp(0.0, oldEdge.lengthM)
              .toDouble();
      _correctedPosition = oldEdge.pointAt(_currentProgressM);
      _appendCorrected(_correctedPosition);
    }

    final newEdgeProgressM = math.max(
      0.0,
      turn.confirmedDistanceM - turn.distanceToNodeM,
    );
    final heldLongEnough =
        atMs - turn.candidateSinceMs >= config.newDirectionHoldMs;
    if (heldLongEnough &&
        newEdgeProgressM >= config.minimumNewEdgeProgressM &&
        turn.alignedNewEdgeDistanceM >= config.minimumNewEdgeProgressM) {
      _confirmNodeTransition(
        node: turn.node,
        edge: turn.candidateEdge,
        progressM: math.min(
          newEdgeProgressM,
          config.maximumConfirmationProgressM,
        ),
        atMs: atMs,
      );
      _turn = null;
    }
  }

  void _applyUncertainConfirmed({
    required int atMs,
    required int deltaSteps,
    required double deltaDistanceM,
    required PdrLocalPoint previousRawConfirmedPosition,
    required List<PdrLocalPoint> rawConfirmedStepPositions,
  }) {
    final edge = _currentEdge;
    if (edge == null) return;

    final segments = _rawSegments(
      deltaSteps: deltaSteps,
      deltaDistanceM: deltaDistanceM,
      previousRawConfirmedPosition: previousRawConfirmedPosition,
      rawConfirmedStepPositions: rawConfirmedStepPositions,
    );
    for (final segment in segments) {
      _recordRecoverySegment(
        atMs: atMs,
        headingDeg: _normalizeBearing(segment.headingDeg + _headingBiasDeg),
        distanceM: segment.distanceM,
      );
    }
    _observeUncertainCandidate(
      atMs,
      _normalizeBearing(_sensorHeadingDeg + _headingBiasDeg),
    );

    final candidateId = _uncertainCandidateEdgeId;
    final candidateSince = _uncertainCandidateSinceMs;
    if (candidateId == null || candidateSince == null) return;
    final candidate = _network.edgeById(candidateId);
    if (candidate == null) return;
    for (final segment in segments) {
      final candidateProgressM = _uncertainCandidateTravelSign > 0
          ? 0.0
          : candidate.lengthM;
      final candidateBearing = candidate.bearingForTravel(
        candidate == edge ? _currentProgressM : candidateProgressM,
        _uncertainCandidateTravelSign,
      );
      final segmentHeading = _normalizeBearing(
        segment.headingDeg + _headingBiasDeg,
      );
      if (_headingError(segmentHeading, candidateBearing) >
          config.newEdgeHeadingToleranceDeg) {
        _uncertainCandidateDistanceM = 0;
        continue;
      }
      _uncertainCandidateDistanceM += segment.distanceM;
      if (candidate == edge &&
          _uncertainCandidateNodeId == null &&
          _uncertainCandidateTravelSign == _travelSign) {
        final next =
            (_currentProgressM +
                    _uncertainCandidateTravelSign * segment.distanceM)
                .clamp(0.0, edge.lengthM)
                .toDouble();
        _currentProgressM = next;
        _correctedPosition = edge.pointAt(next);
        _appendCorrected(_correctedPosition);
      }
    }
    if (atMs - candidateSince < config.uncertainReacquireMs ||
        _uncertainCandidateDistanceM < config.uncertainReacquireDistanceM) {
      return;
    }
    if (candidate == edge && _uncertainCandidateNodeId == null) {
      if (_uncertainCandidateTravelSign != _travelSign) {
        _travelSign = _uncertainCandidateTravelSign;
        _travelDirectionLocked = true;
        _currentProgressM =
            (_currentProgressM +
                    _travelSign *
                        math.min(
                          _uncertainCandidateDistanceM,
                          config.maximumConfirmationProgressM,
                        ))
                .clamp(0.0, edge.lengthM)
                .toDouble();
        _correctedPosition = edge.pointAt(_currentProgressM);
        _appendCorrected(_correctedPosition);
      }
      _state = CorridorTrackingState.straightTracking;
      _straightSinceMs = atMs;
      _clearUncertainCandidate();
      _recoverySegments.clear();
      return;
    }
    final nodeId = _uncertainCandidateNodeId;
    final node = nodeId == null ? null : _network.nodes[nodeId];
    if (node == null) return;
    _confirmNodeTransition(
      node: node,
      edge: candidate,
      progressM: math.min(
        _uncertainCandidateDistanceM,
        config.maximumConfirmationProgressM,
      ),
      atMs: atMs,
    );
    _clearUncertainCandidate();
  }

  void _observeUncertainCandidate(int atMs, double headingDeg) {
    final edge = _currentEdge;
    if (edge == null) return;
    final nodeId = edge.nodeAtTravelEnd(_travelSign);
    final distanceToNodeM = _travelSign > 0
        ? edge.lengthM - _currentProgressM
        : _currentProgressM;
    if (distanceToNodeM <= 0.35) {
      final candidate = _bestRecoveryCandidate(
        _network.recoveryOptionsFromNode(nodeId),
        currentHeadingDeg: headingDeg,
      );
      if (candidate == null) {
        if (_uncertainCandidateEdgeId != null && _recoverySegments.isEmpty) {
          return;
        }
        _clearUncertainCandidate();
        return;
      }
      if (_shouldKeepUnverifiedCandidate(candidate)) return;
      _setUncertainCandidate(
        edgeId: candidate.edge.id,
        nodeId: nodeId,
        travelSign: candidate.travelSign,
        atMs: atMs,
      );
      return;
    }

    final candidates = <_RecoveryOption>[
      _RecoveryOption(
        edge: edge,
        travelSign: _travelSign,
        bearingDeg: edge.bearingForTravel(_currentProgressM, _travelSign),
      ),
      if (edge.bidirectional)
        _RecoveryOption(
          edge: edge,
          travelSign: -_travelSign,
          bearingDeg: edge.bearingForTravel(_currentProgressM, -_travelSign),
        ),
    ];
    final candidate = _bestRecoveryCandidate(
      candidates,
      currentHeadingDeg: headingDeg,
    );
    if (candidate == null) {
      if (_uncertainCandidateEdgeId != null && _recoverySegments.isEmpty) {
        return;
      }
      _clearUncertainCandidate();
      return;
    }
    if (_shouldKeepUnverifiedCandidate(candidate)) return;
    _setUncertainCandidate(
      edgeId: candidate.edge.id,
      nodeId: null,
      travelSign: candidate.travelSign,
      atMs: atMs,
    );
  }

  bool _shouldKeepUnverifiedCandidate(_RecoveryOption replacement) =>
      _uncertainCandidateEdgeId != null &&
      _recoverySegments.isEmpty &&
      (_uncertainCandidateEdgeId != replacement.edge.id ||
          _uncertainCandidateTravelSign != replacement.travelSign);

  _RecoveryOption? _bestRecoveryCandidate(
    List<_RecoveryOption> candidates, {
    required double currentHeadingDeg,
  }) {
    if (candidates.isEmpty) return null;
    final scored = <({double errorDeg, _RecoveryOption option})>[];
    for (final option in candidates) {
      // 최신 heading 한 번의 스파이크보다 초록 배치에서 복원한 최근 이동
      // 형태가 우세하도록 실시간 표본은 짧은 걸음 절반보다 작게 가중한다.
      const realtimeWeightM = 0.35;
      var weightedError =
          _headingError(currentHeadingDeg, option.bearingDeg) * realtimeWeightM;
      var weightM = realtimeWeightM;
      for (final segment in _recoverySegments) {
        weightedError +=
            _headingError(segment.headingDeg, option.bearingDeg) *
            segment.distanceM;
        weightM += segment.distanceM;
      }
      scored.add((errorDeg: weightedError / weightM, option: option));
    }
    scored.sort((left, right) => left.errorDeg.compareTo(right.errorDeg));
    final best = scored.first;
    if (best.errorDeg > config.newEdgeHeadingToleranceDeg) return null;
    if (scored.length > 1 &&
        scored[1].errorDeg - best.errorDeg <
            config.recoveryCandidateMarginDeg) {
      return null;
    }
    return best.option;
  }

  void _recordRecoverySegment({
    required int atMs,
    required double headingDeg,
    required double distanceM,
  }) {
    if (distanceM <= 0) return;
    _recoverySegments.add(
      _RecoverySegment(
        atMs: atMs,
        headingDeg: headingDeg,
        distanceM: distanceM,
      ),
    );
    final oldestAtMs = atMs - config.recoveryWindowMs;
    _recoverySegments.removeWhere((segment) => segment.atMs < oldestAtMs);
    var totalM = _recoverySegments.fold<double>(
      0,
      (sum, segment) => sum + segment.distanceM,
    );
    while (_recoverySegments.length > 1 &&
        totalM > config.recoveryWindowDistanceM) {
      totalM -= _recoverySegments.removeAt(0).distanceM;
    }
  }

  void _setUncertainCandidate({
    required String edgeId,
    required String? nodeId,
    required int travelSign,
    required int atMs,
  }) {
    if (_uncertainCandidateEdgeId == edgeId &&
        _uncertainCandidateNodeId == nodeId &&
        _uncertainCandidateTravelSign == travelSign) {
      return;
    }
    _uncertainCandidateEdgeId = edgeId;
    _uncertainCandidateNodeId = nodeId;
    _uncertainCandidateTravelSign = travelSign;
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
    _travelSign = edge.travelSignAwayFromNode(node.id);
    _travelDirectionLocked = true;
    final boundedProgressM = progressM.clamp(0.0, edge.lengthM).toDouble();
    _currentProgressM = _travelSign > 0
        ? boundedProgressM
        : edge.lengthM - boundedProgressM;
    _correctedPosition = edge.pointAt(_currentProgressM);
    _appendCorrected(_correctedPosition);
    _lastConfirmedNodeId = node.id;
    _state = CorridorTrackingState.nodeConfirmed;
    _straightSinceMs = atMs;
    _clearLiveTurnCandidate();
    _recoverySegments.clear();
  }

  void _enterUncertain(int atMs) {
    _state = CorridorTrackingState.uncertain;
    _straightSinceMs = atMs;
    _clearUncertainCandidate();
    _recoverySegments.clear();
  }

  void _recordHeading(int atMs, double headingDeg) {
    _headingWindow.add((atMs: atMs, headingDeg: headingDeg));
    final oldest = atMs - config.straightStableMs;
    _headingWindow.removeWhere((sample) => sample.atMs < oldest);
  }

  double _recentHeadingChangeDeg(int atMs) {
    ({int atMs, double headingDeg})? baseline;
    for (final sample in _headingWindow) {
      final ageMs = atMs - sample.atMs;
      if (ageMs < config.turnObservationMs || ageMs > 1200) continue;
      baseline = sample;
      break;
    }
    return baseline == null
        ? 0
        : _headingError(_sensorHeadingDeg, baseline.headingDeg);
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
    _uncertainCandidateNodeId = null;
    _uncertainCandidateTravelSign = 1;
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
    required this.startedProgressM,
    required this.oldTravelSign,
  });

  final _CorridorNode node;
  final _CorridorEdge candidateEdge;
  final int startedAtMs;
  final int candidateSinceMs;
  final double distanceToNodeM;
  final double startedProgressM;
  final int oldTravelSign;
  double confirmedDistanceM = 0;
  double alignedNewEdgeDistanceM = 0;
}

class _RecoverySegment {
  const _RecoverySegment({
    required this.atMs,
    required this.headingDeg,
    required this.distanceM,
  });

  final int atMs;
  final double headingDeg;
  final double distanceM;
}

class _RecoveryOption {
  const _RecoveryOption({
    required this.edge,
    required this.travelSign,
    required this.bearingDeg,
  });

  final _CorridorEdge edge;
  final int travelSign;
  final double bearingDeg;
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

  _EdgeProjection? nearestProjection(
    PdrLocalPoint point, {
    double? headingDeg,
  }) {
    _EdgeProjection? best;
    for (final edge in edges) {
      final projection = edge.project(point);
      final closer =
          best == null || projection.distanceM < best.distanceM - 0.1;
      final nearTie =
          best != null &&
          (projection.distanceM - best.distanceM).abs() <= 0.1 &&
          headingDeg != null;
      final headingBetter =
          nearTie &&
          _headingError(
                headingDeg,
                edge.bearingForTravel(
                  projection.distanceAlongM,
                  edge.directionSignForHeading(headingDeg),
                ),
              ) <
              _headingError(
                headingDeg,
                best.edge.bearingForTravel(
                  best.distanceAlongM,
                  best.edge.directionSignForHeading(headingDeg),
                ),
              );
      if (closer || headingBetter) {
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

  _OutgoingEdge? bestStraightContinuation({
    required String nodeId,
    required String excludingEdgeId,
    required double incomingBearingDeg,
    required double toleranceDeg,
  }) => bestOutgoing(
    nodeId: nodeId,
    excludingEdgeId: excludingEdgeId,
    headingDeg: incomingBearingDeg,
    toleranceDeg: toleranceDeg,
  );

  List<_RecoveryOption> recoveryOptionsFromNode(String nodeId) => [
    for (final edge in _incident[nodeId] ?? const [])
      if (!edge.accessEdge && (edge.bidirectional || edge.fromNodeId == nodeId))
        _RecoveryOption(
          edge: edge,
          travelSign: edge.travelSignAwayFromNode(nodeId),
          bearingDeg: edge.bearingAwayFromNode(nodeId),
        ),
  ];
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

  int directionSignForHeading(double headingDeg) {
    if (!bidirectional) return 1;
    final forward = bearingForTravel(0, 1);
    final reverse = _normalizeBearing(forward + 180);
    return _headingError(headingDeg, forward) <=
            _headingError(headingDeg, reverse)
        ? 1
        : -1;
  }

  int travelSignAwayFromNode(String nodeId) => nodeId == fromNodeId ? 1 : -1;

  String nodeAtTravelEnd(int travelSign) =>
      travelSign > 0 ? toNodeId : fromNodeId;

  double bearingForTravel(double distanceAlongM, int travelSign) {
    final tangent = tangentBearingAt(distanceAlongM);
    return travelSign > 0 ? tangent : _normalizeBearing(tangent + 180);
  }

  double tangentBearingAt(double distanceAlongM) {
    final target = distanceAlongM.clamp(0.0, lengthM).toDouble();
    for (var index = 1; index < _lengths.length; index += 1) {
      if (target > _lengths[index] && index < _lengths.length - 1) continue;
      return pdrBearingForDirection(points[index] - points[index - 1]);
    }
    return pdrBearingForDirection(points.last - points[points.length - 2]);
  }

  double bearingTowardNode(String nodeId) {
    if (nodeId == toNodeId) {
      return pdrBearingForDirection(points.last - points[points.length - 2]);
    }
    return pdrBearingForDirection(points.first - points[1]);
  }

  double bearingAwayFromNode(String nodeId) =>
      _normalizeBearing(bearingTowardNode(nodeId) + 180);

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
