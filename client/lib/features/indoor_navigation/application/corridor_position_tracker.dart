import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../models/floor_graph.dart';
import '../contract/pdr_anchor.dart';

/// 보정 결과의 확신도.
///
/// 예전 구현의 상태기(직선/회전대기/노드확정/불확실) 이름을 유지하지만 의미가
/// 다르다. 지금은 상태가 동작을 바꾸지 않는다 — 빔이 항상 모든 가설을 들고
/// 있고, 이 값은 **그 빔이 지금 얼마나 갈렸는지**를 표시할 뿐이다.
enum CorridorTrackingState {
  /// 1등 가설이 뚜렷하다.
  straightTracking,

  /// 1·2등이 다른 간선인데 점수 차가 작다. 표시는 공통 지점에서 멈춘다.
  turnPending,

  /// 이번 갱신에서 1등 가설이 노드를 넘었다.
  nodeConfirmed,

  /// 모든 가설이 그래프로 설명되지 않는다(막다른 곳 등).
  uncertain,
}

class CorridorTrackerConfig {
  const CorridorTrackerConfig({
    this.beamWidth = 24,
    this.progressBucketM = 1.5,
    this.transitionPenaltyDegM = 3,
    this.deadEndPenaltyDeg = 90,
    this.reverseTriggerDeg = 115,
    this.absoluteErrorWeight = 0.25,
    this.costHorizonM = 25,
    this.maxSegmentErrorDeg = 60,
    this.positionalWeightDegPerM = 1.0,
    this.positionalToleranceM = 6,
    this.positionalMaxOffsetM = 12,
    this.leaderSwitchMarginDeg = 2.5,
    this.ambiguousMarginDeg = 6,
    this.maxHeadingCorrectionPerStepDeg = 0.75,
    this.headingBiasLimitDeg = 60,
    this.headingBiasMaxErrorDeg = 50,
    this.maxTransitionsPerSegment = 3,
    this.maxPathPoints = 800,
  });

  /// 동시에 유지하는 가설 수. 교차점이 촘촘한 층에서 정답이 살아남을 여유.
  final int beamWidth;

  /// 같은 간선·같은 방향에서 이 간격 안의 가설은 하나로 합친다.
  final double progressBucketM;

  /// 노드를 넘을 때마다 더하는 비용(도·m). 근거 없는 간선 갈아타기를 막되,
  /// 실제 회전을 이기지 못할 만큼 작아야 한다.
  final double transitionPenaltyDegM;

  /// 그래프로 설명되지 않은 이동 1m당 비용(도). 막다른 가설을 죽이지 않고
  /// 크게 벌점만 줘서, 다른 가설이 없을 때도 위치가 멈추지 않게 한다.
  final double deadEndPenaltyDeg;

  /// 관측 방향이 현재 진행 방향과 이만큼 어긋나면 유턴 가설을 함께 만든다.
  final double reverseTriggerDeg;

  /// 비용에서 절대 방위 오차가 차지하는 비중. 나머지는 형태(방위 변화) 오차다.
  ///
  /// 형태를 더 크게 보는 이유: 시작 heading이 틀어져 있어도 회전의 순서와
  /// 크기는 그대로 남기 때문이다. 다만 형태만 보면 전역 회전에 완전히
  /// 무감각해져서 **정반대 방향**도 똑같이 좋은 설명이 된다. 절대 항은 그걸
  /// 막는 최소한의 닻이다.
  ///
  /// heading이 늘 틀어져 있다고 가정하면 안 된다 — 맞는 세션이 더 많다.
  /// 틀어진 경우는 [headingBiasMaxErrorDeg] 아래의 bias 학습이 흡수하고,
  /// 그동안은 형태 항이 버틴다.
  final double absoluteErrorWeight;

  /// 원본 위치에서 벗어난 1m당 더하는 비용(도/m).
  ///
  /// 방위·형태만으로는 **나란히 놓인 두 복도**를 구분할 수 없다. 실측에서
  /// y=131.1 복도와 9m 북쪽의 y=141.5 복도가 둘 다 동서 방향이라, 위치 항이
  /// 없을 때 엉뚱한 쪽으로 올라가 그대로 눌러앉았다. 구 map matcher가 주
  /// 신호로 쓰던 근접도를 여기서 되살린다.
  final double positionalWeightDegPerM;

  /// 이 거리 안의 어긋남은 벌하지 않는다.
  ///
  /// 넉넉해야 한다. PDR 원본은 누적 드리프트를 안고 가며(실측 106m 왕복에서
  /// 폐합오차 13.8m), 좁게 잡으면 시간이 갈수록 **정답 가설**이 더 크게
  /// 벌점을 먹는다. 나란한 복도 간격(실측 9m)보다 작기만 하면 된다.
  final double positionalToleranceM;

  /// 위치 벌점이 방위 항을 완전히 눌러 버리지 않게 하는 상한.
  final double positionalMaxOffsetM;

  /// 비용이 기억하는 이동 거리(m). 이보다 오래된 증거는 지수적으로 잊는다.
  ///
  /// 없으면 비용이 세션 전체 평균이 되어, 후반에는 누적 거리에 눌려 새 증거가
  /// 순위를 못 바꾼다. 실측에서 130m를 걸은 뒤 마지막 12m를 서쪽으로 갔는데도
  /// 1등이 초반에 고른 간선에 붙박여 확정 위치가 0.5m만 움직였다. 최근 구간을
  /// 더 무겁게 봐야 "지금 어디를 걷고 있는가"에 반응한다.
  final double costHorizonM;

  /// 한 걸음이 낼 수 있는 최대 비용(도). 그 이상은 잘라낸다.
  ///
  /// 안드로이드 실측에서 heading이 직선 복도 위에서도 ±35° 흔들렸다. 이런
  /// 튀는 한 걸음이 비용을 독점하면, 실제로는 없는 회전을 그래프에서 찾아
  /// 엉뚱한 간선으로 갈아탄다. 포화시키면 "많이 틀렸다"까지만 반영된다.
  final double maxSegmentErrorDeg;

  /// 표시 중인 간선을 다른 가설이 이만큼 이겨야 1등을 넘겨준다.
  ///
  /// 없으면 점수가 근소하게 오갈 때마다 화면 위치가 복도 사이를 오간다.
  final double leaderSwitchMarginDeg;

  /// 1·2등 평균 오차가 이 안이면 갈렸다고 본다.
  final double ambiguousMarginDeg;

  final double maxHeadingCorrectionPerStepDeg;
  final double headingBiasLimitDeg;

  /// 이 각도보다 크게 틀어진 상태에서는 bias를 학습하지 않는다. 엉뚱한 간선에
  /// 붙어 있는 동안 bias까지 오염되는 것을 막는다.
  ///
  /// 넉넉해야 한다. 시작 heading 오차는 **세션마다 달라지는 미지수**다(같은
  /// 기기에서도 켤 때마다 다르다). 실측 한 세션에서 복도 대비 28° 넘게
  /// 틀어진 채로 "수렴"한 적이 있다 — 수렴은 흔들림이 작다는 뜻이지 방향이
  /// 맞다는 뜻이 아니다. 이 값이 작으면 정작 보정이 필요한 세션에서 bias가
  /// 영원히 0에 머문다.
  final double headingBiasMaxErrorDeg;

  final int maxTransitionsPerSegment;
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
    this.rawPreviewTailPositions = const [],
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

  /// 아직 초록으로 확정되지 않은 최근 주황 경로의 floor 좌표.
  ///
  /// 첫 점은 tail 직전 위치이며 이후 점마다 한 걸음의 이동 벡터를 만든다.
  /// 확정 상태에는 반영하지 않고 화면용 preview에만 사용한다.
  final List<PdrLocalPoint> rawPreviewTailPositions;
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
    required this.previewPosition,
    required this.previewHeadingDeg,
    required this.previewPath,
    required this.previewCandidateEdgeIds,
    required this.previewIsAmbiguous,
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
  final PdrLocalPoint previewPosition;
  final double previewHeadingDeg;
  final List<PdrLocalPoint> previewPath;
  final List<String> previewCandidateEdgeIds;
  final bool previewIsAmbiguous;
  final PdrLocalPoint rawConfirmedPosition;
  final PdrLocalPoint rawPreviewPosition;
}

/// 초록·주황 원본을 수정하지 않고 실제 위치만 graph 제약으로 보정한다.
///
/// **빔 서치**로 동작한다. 하나의 "현재 간선"을 잠그는 대신, 서로 다른 간선
/// 위에 있는 가설 여러 개를 동시에 들고 다니면서 걸음마다 점수를 매기고,
/// 언제든 1등이 바뀔 수 있게 둔다. 1등이 바뀌면 그 가설이 들고 있던 경로가
/// 그대로 화면 경로가 되므로, 최근 구간이 통째로 다시 그려진다.
///
/// 이전 구현은 간선을 잠그고 노드에서만 엄격한 증거로 전환하는 탐욕적
/// 상태기였다. 시간적 일관성은 얻었지만 회전을 한 번 놓치면 되돌릴 방법이
/// 없어서, 실측에서 교차점에 28초 멈춰 있거나 한 복도를 계속 미끄러졌다.
/// 빔은 놓친 회전을 "그 가설이 아직 살아 있다"는 형태로 해결한다.
///
/// 위치는 절대 멈추지 않는다. 어떤 가설도 그래프로 설명되지 않으면 벌점을
/// 주되 진행은 시키므로, 걸은 거리가 통째로 사라지지 않는다.
class CorridorPositionTracker {
  CorridorPositionTracker(
    FloorGraph graph, {
    this.config = const CorridorTrackerConfig(),
  }) : _network = _CorridorNetwork(graph);

  final CorridorTrackerConfig config;
  final _CorridorNetwork _network;

  final List<PdrLocalPoint> _correctedPath = [];
  final List<PdrLocalPoint> _previewPath = [];

  List<_Hypothesis> _beam = const [];

  CorridorTrackingState _state = CorridorTrackingState.uncertain;
  PdrLocalPoint _correctedPosition = PdrLocalPoint.zero;
  PdrLocalPoint _previewPosition = PdrLocalPoint.zero;
  double _previewHeadingDeg = 0;
  List<String> _previewCandidateEdgeIds = const [];
  bool _previewIsAmbiguous = false;
  PdrLocalPoint _rawConfirmedPosition = PdrLocalPoint.zero;
  PdrLocalPoint _rawPreviewPosition = PdrLocalPoint.zero;
  double _sensorHeadingDeg = 0;
  double _headingBiasDeg = 0;
  int _lastConfirmedSteps = 0;
  double _lastConfirmedDistanceM = 0;
  int _lastPreviewSteps = 0;
  String? _pendingEdgeId;
  String? _lastConfirmedNodeId;
  String? _leaderEdgeId;
  int _leaderSign = 1;

  /// 확정 위치에서 preview까지의 경로 길이(m). 뒤로 줄지 않게 지킨다.
  double _previewLeadM = 0;

  /// 이번 갱신에서 확정 위치가 나아간 거리(m).
  double _confirmedAdvanceM = 0;

  bool get isInitialized => _beam.isNotEmpty;

  _Hypothesis? get _best => _beam.isEmpty ? null : _beam.first;

  CorridorTrackingResult get result => CorridorTrackingResult(
    state: _state,
    correctedPosition: _correctedPosition,
    correctedHeadingDeg:
        _best?.edge.bearingForTravel(_best!.progressM, _best!.travelSign) ??
        _normalizeBearing(_sensorHeadingDeg + _headingBiasDeg),
    headingBiasDeg: _headingBiasDeg,
    currentEdgeId: _best?.edge.id,
    currentEdgeProgressM: _best?.progressM ?? 0,
    travelDirectionSign: _best?.travelSign ?? 1,
    pendingEdgeId: _pendingEdgeId,
    lastConfirmedNodeId: _lastConfirmedNodeId,
    correctedPath: List.unmodifiable(_correctedPath),
    previewPosition: _previewPosition,
    previewHeadingDeg: _previewHeadingDeg,
    previewPath: List.unmodifiable(_previewPath),
    previewCandidateEdgeIds: List.unmodifiable(_previewCandidateEdgeIds),
    previewIsAmbiguous: _previewIsAmbiguous,
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
    _sensorHeadingDeg = _normalizeBearing(initialHeadingDeg);
    _headingBiasDeg = 0;
    _lastConfirmedSteps = initialConfirmedSteps;
    _lastConfirmedDistanceM = initialConfirmedDistanceM;
    _lastPreviewSteps = initialPreviewSteps;
    _rawConfirmedPosition = initialPosition;
    _rawPreviewPosition = initialPosition;
    _lastConfirmedNodeId = null;
    _pendingEdgeId = null;
    _leaderEdgeId = null;
    _leaderSign = 1;
    _previewLeadM = 0;
    _confirmedAdvanceM = 0;

    // 시작 방향을 하나로 못 박지 않는다. 첫 걸음의 방위는 복도에 거의 수직인
    // 경우가 많고(실측에서 176.9°), 그것으로 진행 부호를 잠그면 6° 차이로
    // 역주행이 확정된다. 대신 근처 간선의 양방향을 모두 씨앗으로 깔고 걸음이
    // 쌓이면서 걸러지게 둔다.
    _beam = _seedHypotheses(initialPosition, initialHeadingDeg);
    _correctedPosition = _best == null
        ? initialPosition
        : _best!.edge.pointAt(_best!.progressM);
    _correctedPath
      ..clear()
      ..add(_correctedPosition);
    _state = _beam.isEmpty
        ? CorridorTrackingState.uncertain
        : CorridorTrackingState.straightTracking;
    _resetPreviewToConfirmed();
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
    }

    final deltaSteps = math.max(
      0,
      observation.confirmedSteps - _lastConfirmedSteps,
    );
    final deltaDistanceM = math.max(
      0.0,
      observation.confirmedDistanceM - _lastConfirmedDistanceM,
    );

    final previousCorrected = _correctedPosition;
    _confirmedAdvanceM = 0;
    if (deltaSteps > 0 && deltaDistanceM > 0) {
      final segments = _rawSegments(
        deltaSteps: deltaSteps,
        deltaDistanceM: deltaDistanceM,
        previousRawConfirmedPosition: previousRawConfirmedPosition,
        rawConfirmedStepPositions: observation.rawConfirmedStepPositions,
      );
      final transitionsBefore = _best?.transitions ?? 0;
      for (final segment in segments) {
        _advanceBeam(segment);
      }
      _updateHeadingBias();
      _publishConfirmed(transitionsBefore: transitionsBefore);
      _confirmedAdvanceM = (_correctedPosition - previousCorrected).distance;
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
    _rebuildPreview(observation.rawPreviewTailPositions);
    return result;
  }

  // ── 빔 ──

  List<_Hypothesis> _seedHypotheses(
    PdrLocalPoint position,
    double headingDeg,
  ) {
    final seeds = <_Hypothesis>[];
    for (final projection in _network.nearbyProjections(position, radiusM: 8)) {
      for (final sign in const [1, -1]) {
        if (sign < 0 && !projection.edge.bidirectional) continue;
        seeds.add(
          _Hypothesis(
            edge: projection.edge,
            progressM: projection.distanceAlongM,
            travelSign: sign,
            path: [projection.point],
            // 시작 위치 오차를 비용에 넣어, 멀리 떨어진 복도에서 시작한
            // 가설이 초반부터 불리하게 둔다.
            cost: projection.distanceM * 6,
            matchedM: 0,
          ),
        );
      }
    }
    if (seeds.isEmpty) return const [];
    return _prune(seeds);
  }

  void _advanceBeam(
    ({double headingDeg, double distanceM, PdrLocalPoint rawPoint}) segment,
  ) {
    final observed = _normalizeBearing(segment.headingDeg + _headingBiasDeg);
    final next = <_Hypothesis>[];
    for (final hypothesis in _beam) {
      next.addAll(
        _advance(hypothesis, observed, segment.distanceM, segment.rawPoint),
      );
      // 복도 한가운데서 되돌아오는 경우, 노드를 거치지 않으므로 전이만으로는
      // 표현되지 않는다. 관측이 진행 방향과 크게 어긋날 때만 반대 부호 가설을
      // 함께 만들어 비용이 판정하게 한다.
      final currentBearing = hypothesis.edge.bearingForTravel(
        hypothesis.progressM,
        hypothesis.travelSign,
      );
      if (hypothesis.edge.bidirectional &&
          _headingError(observed, currentBearing) >= config.reverseTriggerDeg) {
        next.addAll(
          _advance(
            hypothesis.reversed(),
            observed,
            segment.distanceM,
            segment.rawPoint,
          ),
        );
      }
    }
    if (next.isEmpty) return;
    _beam = _prune(next);
  }

  List<_Hypothesis> _advance(
    _Hypothesis hypothesis,
    double observedHeadingDeg,
    double remainingM,
    PdrLocalPoint rawPoint, {
    int depth = 0,
  }) {
    if (remainingM <= 1e-6) return [hypothesis];
    final edge = hypothesis.edge;
    final distanceToEnd = hypothesis.travelSign > 0
        ? edge.lengthM - hypothesis.progressM
        : hypothesis.progressM;
    final appliedM = math.min(remainingM, distanceToEnd);
    final graphHeading = edge.bearingForTravel(
      hypothesis.progressM,
      hypothesis.travelSign,
    );
    final advanced = hypothesis.advance(
      observedHeadingDeg: observedHeadingDeg,
      graphHeadingDeg: graphHeading,
      distanceM: appliedM,
      absoluteWeight: config.absoluteErrorWeight,
      maxSegmentErrorDeg: config.maxSegmentErrorDeg,
      rawPoint: rawPoint,
      positionalWeightDegPerM: config.positionalWeightDegPerM,
      positionalToleranceM: config.positionalToleranceM,
      positionalMaxOffsetM: config.positionalMaxOffsetM,
      maxPathPoints: config.maxPathPoints,
      costHorizonM: config.costHorizonM,
    );
    if (remainingM <= distanceToEnd + 1e-6) return [advanced];

    final leftoverM = remainingM - appliedM;
    final nodeId = edge.nodeAtTravelEnd(hypothesis.travelSign);
    final node = _network.nodes[nodeId];
    if (node == null || depth >= config.maxTransitionsPerSegment) {
      return [advanced.withDeadEnd(leftoverM, config.deadEndPenaltyDeg)];
    }
    // 같은 간선으로 되돌아가는 선택지도 남긴다. 막다른 복도 끝에서 유턴하는
    // 것은 정상적인 보행이고, 이걸 빼면 그 지점에서 가설이 전멸한다.
    final options = _network.recoveryOptionsFromNode(nodeId);
    if (options.isEmpty) {
      return [advanced.withDeadEnd(leftoverM, config.deadEndPenaltyDeg)];
    }
    final branched = <_Hypothesis>[];
    for (final option in options) {
      branched.addAll(
        _advance(
          advanced.enter(
            option,
            nodeId: nodeId,
            nodePoint: node.point,
            penaltyDegM: config.transitionPenaltyDegM,
          ),
          observedHeadingDeg,
          leftoverM,
          rawPoint,
          depth: depth + 1,
        ),
      );
    }
    return branched;
  }

  /// 같은 자리에 몰린 가설을 합치고 상위 [CorridorTrackerConfig.beamWidth]만 남긴다.
  ///
  /// 합치지 않으면 빔이 "같은 간선 위 1cm 차이" 복제본으로 가득 차서, 정작
  /// 다른 복도에 있는 정답 가설이 밀려난다.
  List<_Hypothesis> _prune(List<_Hypothesis> candidates) {
    final best = <String, _Hypothesis>{};
    for (final candidate in candidates) {
      final bucket = (candidate.progressM / config.progressBucketM).round();
      final key = '${candidate.edge.id}|${candidate.travelSign}|$bucket';
      final existing = best[key];
      if (existing == null || candidate.meanErrorDeg < existing.meanErrorDeg) {
        best[key] = candidate;
      }
    }
    final sorted = best.values.toList(growable: false)
      ..sort((left, right) => left.meanErrorDeg.compareTo(right.meanErrorDeg));
    return sorted.take(config.beamWidth).toList(growable: false);
  }

  /// 표시용 1등을 고른다. 근소한 점수 차로 화면이 복도 사이를 오가지 않게,
  /// 지금 보여 주고 있는 간선을 [CorridorTrackerConfig.leaderSwitchMarginDeg]
  /// 만큼 이겨야 넘겨준다.
  ///
  /// 1등이 노드를 넘어가면 이전 간선의 가설은 빔에서 사라지므로 자연히 새
  /// 간선으로 넘어간다 — 그 전환은 붙어 있는 간선이라 위치가 튀지 않는다.
  void _electLeader() {
    if (_beam.isEmpty) return;
    final globalBest = _beam.first;
    final heldId = _leaderEdgeId;
    if (heldId == null) {
      _leaderEdgeId = globalBest.edge.id;
      _leaderSign = globalBest.travelSign;
      return;
    }
    _Hypothesis? held;
    for (final hypothesis in _beam) {
      if (hypothesis.edge.id == heldId &&
          hypothesis.travelSign == _leaderSign) {
        held = hypothesis;
        break;
      }
    }
    if (held == null ||
        globalBest.meanErrorDeg <
            held.meanErrorDeg - config.leaderSwitchMarginDeg) {
      _leaderEdgeId = globalBest.edge.id;
      _leaderSign = globalBest.travelSign;
      return;
    }
    if (!identical(held, globalBest)) {
      _beam = [held, ..._beam.where((h) => !identical(h, held))];
    }
  }

  void _publishConfirmed({required int transitionsBefore}) {
    _electLeader();
    final best = _best;
    if (best == null) return;
    _correctedPosition = best.edge.pointAt(best.progressM);
    // 1등 가설이 **자기 이력 전체**를 들고 있으므로 그대로 쓴다.
    //
    // 예전에는 윈도우 밖을 따로 커밋해 두고 `커밋분 + 현재 윈도우`로 이어
    // 붙였는데, 1등이 바뀌면 두 조각이 서로 다른 복도에 있어서 이음매가
    // 지도를 가로지르는 직선으로 그려졌다(실측에서 29점 중 21구간이 2m 초과
    // 점프, 합계 102.5m). 한 가설의 경로는 정의상 그래프를 따라가므로
    // 이음매가 없다. 서로 수렴한 가설은 _prune이 합치면서 옛 갈래를 지운다.
    _correctedPath
      ..clear()
      ..addAll(best.path);
    _lastConfirmedNodeId = best.lastNodeId;

    final runnerUp = _beam.length > 1 ? _beam[1] : null;
    final ambiguous =
        runnerUp != null &&
        runnerUp.edge.id != best.edge.id &&
        runnerUp.meanErrorDeg - best.meanErrorDeg < config.ambiguousMarginDeg;
    _pendingEdgeId = ambiguous ? runnerUp.edge.id : null;
    if (best.unmatchedM > 0.5) {
      _state = CorridorTrackingState.uncertain;
    } else if (best.transitions > transitionsBefore) {
      _state = CorridorTrackingState.nodeConfirmed;
    } else if (ambiguous) {
      _state = CorridorTrackingState.turnPending;
    } else {
      _state = CorridorTrackingState.straightTracking;
    }
  }

  /// 1등 가설이 뚜렷할 때만 heading bias를 조금씩 복도 방향으로 당긴다.
  void _updateHeadingBias() {
    final best = _best;
    if (best == null || best.unmatchedM > 0.5) return;
    final target = best.edge.bearingForTravel(best.progressM, best.travelSign);
    final corrected = _normalizeBearing(_sensorHeadingDeg + _headingBiasDeg);
    final requested = _shortestDelta(target - corrected);
    if (requested.abs() > config.headingBiasMaxErrorDeg) return;
    final maxCorrection = config.maxHeadingCorrectionPerStepDeg;
    _headingBiasDeg = _clampSigned(
      _headingBiasDeg + requested.clamp(-maxCorrection, maxCorrection),
      config.headingBiasLimitDeg,
    );
  }

  List<({double headingDeg, double distanceM, PdrLocalPoint rawPoint})>
  _rawSegments({
    required int deltaSteps,
    required double deltaDistanceM,
    required PdrLocalPoint previousRawConfirmedPosition,
    required List<PdrLocalPoint> rawConfirmedStepPositions,
  }) {
    final rawSegments =
        <({double headingDeg, double distanceM, PdrLocalPoint rawPoint})>[];
    var rawCursor = previousRawConfirmedPosition;
    var rawTotalM = 0.0;
    for (final rawPoint in rawConfirmedStepPositions) {
      final movement = rawPoint - rawCursor;
      rawCursor = rawPoint;
      if (movement.distance <= 1e-6) continue;
      rawSegments.add((
        headingDeg: pdrBearingForDirection(movement),
        distanceM: movement.distance,
        rawPoint: rawPoint,
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
            rawPoint: _rawConfirmedPosition,
          ),
      ];
    }
    final distanceScale = deltaDistanceM / rawTotalM;
    return [
      for (final segment in rawSegments)
        (
          headingDeg: segment.headingDeg,
          distanceM: segment.distanceM * distanceScale,
          rawPoint: segment.rawPoint,
        ),
    ];
  }

  // ── preview ──

  /// 확정 빔을 그대로 이어 주황 꼬리만 더 태운다.
  ///
  /// 예전에는 매번 "확정 위치 + 현재 주황 선행분"으로 처음부터 다시 만들었다.
  /// 확정 배치가 도착하면 선행 걸음 수가 갑자기 줄어(19→8) preview가 8m 뒤로
  /// 재계산됐고, 그게 화면에서 보이던 역주행이었다. 지금은 확정 빔이 이미
  /// 그 걸음들을 소비한 상태라 꼬리만 짧아질 뿐 기준점이 뒤로 가지 않는다.
  void _rebuildPreview(List<PdrLocalPoint> rawPreviewTailPositions) {
    final best = _best;
    if (best == null) {
      _resetPreviewToConfirmed();
      return;
    }
    // 씨앗은 **표시 중인 1등 하나뿐**이다. 빔 전체를 씨앗으로 쓰면 확정 쪽
    // 후보 경쟁이 그대로 preview 위치로 새어 나와, 화면이 복도 사이를 오간다.
    // 여기서 갈리는 것은 "이 앞 분기에서 어디로 가는가"만이어야 한다.
    var candidates = [best.forPreview()];
    for (var index = 1; index < rawPreviewTailPositions.length; index += 1) {
      final movement =
          rawPreviewTailPositions[index] - rawPreviewTailPositions[index - 1];
      if (movement.distance <= 1e-6) continue;
      final observed = _normalizeBearing(
        pdrBearingForDirection(movement) + _headingBiasDeg,
      );
      final next = <_Hypothesis>[];
      for (final hypothesis in candidates) {
        next.addAll(
          _advance(
            hypothesis,
            observed,
            movement.distance,
            rawPreviewTailPositions[index],
          ),
        );
      }
      if (next.isEmpty) break;
      candidates = _prune(next);
    }
    if (candidates.isEmpty) {
      _resetPreviewToConfirmed();
      return;
    }

    final leader = candidates.first;
    final runnerUp = candidates.length > 1 ? candidates[1] : null;
    // 모호 판정에 히스테리시스를 준다. 단일 임계값을 쓰면 점수가 그 근처에서
    // 오갈 때마다 "분기에서 대기 <-> 꼬리 끝까지 전진"이 번갈아 일어나서,
    // preview가 꼬리 길이만큼(실측 4.6m) 앞뒤로 진동한다.
    final gapDeg = runnerUp == null || runnerUp.edge.id == leader.edge.id
        ? double.infinity
        : runnerUp.meanErrorDeg - leader.meanErrorDeg;
    final exitThreshold = config.ambiguousMarginDeg * 2;
    _previewIsAmbiguous = _previewIsAmbiguous
        ? gapDeg < exitThreshold
        : gapDeg < config.ambiguousMarginDeg;

    // 선행분(확정 위치에서 preview까지의 길이)은 **뒤로 줄지 않는다**.
    //
    // 갈렸을 때 공통 지점까지만 전진시키면 옳지만, 그 공통 지점은 프레임마다
    // 조금씩 바뀌어서 preview가 앞뒤로 진동한다(실측 3m 초과 28건). 반대로
    // 아예 얼려 두면 모호가 안 풀릴 때 옛 자리에 영원히 남는다(실측 214개 중
    // 189개가 같은 좌표, 실제 위치에서 40m). 선행분을 단조로 두면 둘 다
    // 피한다 — 확정이 따라온 만큼만 줄어들고, 앞으로는 자유롭게 늘어난다.
    final leaderPath = leader.path.isEmpty ? [_correctedPosition] : leader.path;
    final fullLeadM = _pathLength(leaderPath);
    final targetLeadM = _previewIsAmbiguous && runnerUp != null
        ? _pathLength(_commonPrefix(leaderPath, runnerUp.path))
        : fullLeadM;
    _previewLeadM = math
        .max(targetLeadM, _previewLeadM - _confirmedAdvanceM)
        .clamp(0.0, fullLeadM)
        .toDouble();
    _previewPath
      ..clear()
      ..addAll(_truncateToLength(leaderPath, _previewLeadM));
    _previewPosition = _previewPath.last;
    _previewHeadingDeg = _previewIsAmbiguous
        ? result.correctedHeadingDeg
        : leader.edge.bearingForTravel(leader.progressM, leader.travelSign);
    final seen = <String>{};
    _previewCandidateEdgeIds = [
      for (final candidate in candidates)
        if (seen.add(candidate.edge.id)) candidate.edge.id,
    ];
  }

  static double _pathLength(List<PdrLocalPoint> path) {
    var total = 0.0;
    for (var index = 1; index < path.length; index += 1) {
      total += (path[index] - path[index - 1]).distance;
    }
    return total;
  }

  /// 경로 앞에서부터 [lengthM]만큼만 남긴다. 마지막 점은 정확히 그 지점이다.
  static List<PdrLocalPoint> _truncateToLength(
    List<PdrLocalPoint> path,
    double lengthM,
  ) {
    if (path.isEmpty) return path;
    final kept = <PdrLocalPoint>[path.first];
    var remaining = lengthM;
    for (var index = 1; index < path.length; index += 1) {
      final step = (path[index] - path[index - 1]).distance;
      if (step <= 1e-9) continue;
      if (remaining >= step) {
        kept.add(path[index]);
        remaining -= step;
        continue;
      }
      if (remaining > 1e-6) {
        final t = remaining / step;
        kept.add(
          PdrLocalPoint(
            path[index - 1].eastM +
                (path[index].eastM - path[index - 1].eastM) * t,
            path[index - 1].northM +
                (path[index].northM - path[index - 1].northM) * t,
          ),
        );
      }
      break;
    }
    return kept;
  }

  static List<PdrLocalPoint> _commonPrefix(
    List<PdrLocalPoint> left,
    List<PdrLocalPoint> right,
  ) {
    final shared = <PdrLocalPoint>[];
    final limit = math.min(left.length, right.length);
    for (var index = 0; index < limit; index += 1) {
      if ((left[index] - right[index]).distance > 0.05) break;
      shared.add(left[index]);
    }
    return shared;
  }

  void _resetPreviewToConfirmed() {
    _previewPosition = _correctedPosition;
    _previewHeadingDeg = result.correctedHeadingDeg;
    _previewPath
      ..clear()
      ..add(_correctedPosition);
    _previewCandidateEdgeIds = const [];
    _previewIsAmbiguous = false;
    _previewLeadM = 0;
  }
}

/// 빔의 한 가설. 어느 간선 위 어디를, 어느 방향으로 걷고 있다는 한 가지 설명.
class _Hypothesis {
  const _Hypothesis({
    required this.edge,
    required this.progressM,
    required this.travelSign,
    required this.path,
    required this.cost,
    required this.matchedM,
    this.unmatchedM = 0,
    this.previousObservedHeadingDeg,
    this.previousGraphHeadingDeg,
    this.transitions = 0,
    this.lastNodeId,
  });

  final _CorridorEdge edge;
  final double progressM;
  final int travelSign;
  final List<PdrLocalPoint> path;

  /// 누적 가중 오차(도·m).
  final double cost;

  /// 비용을 매긴 총 이동 거리(m).
  final double matchedM;

  /// 그래프로 설명하지 못한 이동 거리(m).
  final double unmatchedM;

  final double? previousObservedHeadingDeg;
  final double? previousGraphHeadingDeg;
  final int transitions;
  final String? lastNodeId;

  /// 가설끼리 비교하는 값. 같은 걸음을 먹었으므로 거리 정규화만으로 공평하다.
  double get meanErrorDeg => matchedM <= 1e-6 ? cost : cost / matchedM;

  _Hypothesis reversed() => _copy(travelSign: -travelSign);

  /// preview 분기용 사본. 경로를 **현재 위치 한 점으로 리셋**한다.
  ///
  /// 윈도우 이력(최대 30m)을 그대로 들고 가면 두 preview 후보의 공통 prefix가
  /// 그 이력 전체가 되어, 분기 대기 지점이 현재 위치보다 뒤로 잡힌다. 그러면
  /// 모호해질 때마다 preview가 꼬리 길이만큼 뒤로 튄다.
  _Hypothesis forPreview() => _copy(path: [edge.pointAt(progressM)]);


  _Hypothesis advance({
    required double observedHeadingDeg,
    required double graphHeadingDeg,
    required double distanceM,
    required double absoluteWeight,
    required double maxSegmentErrorDeg,
    required PdrLocalPoint rawPoint,
    required double positionalWeightDegPerM,
    required double positionalToleranceM,
    required double positionalMaxOffsetM,
    required int maxPathPoints,
    required double costHorizonM,
  }) {
    if (distanceM <= 1e-6) return this;
    final absoluteError = _headingError(observedHeadingDeg, graphHeadingDeg);
    final previousObserved = previousObservedHeadingDeg;
    final previousGraph = previousGraphHeadingDeg;
    // 형태 오차: 관측의 방위 변화와 그래프의 방위 변화가 얼마나 다른가.
    // heading에 상수 bias가 껴 있어도 이 값은 살아남는다.
    final shapeError = previousObserved == null || previousGraph == null
        ? absoluteError
        : _headingError(
            _shortestDelta(observedHeadingDeg - previousObserved),
            _shortestDelta(graphHeadingDeg - previousGraph),
          );
    final combined = math.min(
      maxSegmentErrorDeg,
      absoluteError * absoluteWeight + shapeError * (1 - absoluteWeight),
    );
    final nextProgress = (progressM + travelSign * distanceM)
        .clamp(0.0, edge.lengthM)
        .toDouble();
    final nextPoint = edge.pointAt(nextProgress);
    // 나란한 복도를 가르는 유일한 신호. 원본이 늘 조금씩 흐르므로 허용치
    // 안쪽은 공짜로 두고, 상한을 씌워 방위 항을 완전히 덮지 않게 한다.
    final offsetM = ((nextPoint - rawPoint).distance - positionalToleranceM)
        .clamp(0.0, positionalMaxOffsetM)
        .toDouble();
    final nextPath = path.length >= maxPathPoints
        ? [...path.skip(path.length - maxPathPoints + 1), nextPoint]
        : [...path, nextPoint];
    // 오래된 증거를 지수적으로 잊는다. 그래야 후반에도 최근 구간이 순위를
    // 바꿀 수 있다.
    final decay = math.exp(-distanceM / costHorizonM);
    return _copy(
      progressM: nextProgress,
      path: nextPath,
      cost:
          cost * decay +
          combined * distanceM +
          offsetM * positionalWeightDegPerM * distanceM,
      matchedM: matchedM * decay + distanceM,
      unmatchedM: unmatchedM * decay,
      previousObservedHeadingDeg: observedHeadingDeg,
      previousGraphHeadingDeg: graphHeadingDeg,
    );
  }

  _Hypothesis enter(
    _RecoveryOption option, {
    required String nodeId,
    required PdrLocalPoint nodePoint,
    required double penaltyDegM,
  }) => _Hypothesis(
    edge: option.edge,
    progressM: option.travelSign > 0 ? 0 : option.edge.lengthM,
    travelSign: option.travelSign,
    path: [...path, nodePoint],
    cost: cost + penaltyDegM,
    matchedM: matchedM,
    unmatchedM: unmatchedM,
    previousObservedHeadingDeg: previousObservedHeadingDeg,
    previousGraphHeadingDeg: previousGraphHeadingDeg,
    transitions: transitions + 1,
    lastNodeId: nodeId,
  );

  /// 그래프로 더 갈 수 없는 이동. 가설을 죽이지 않고 벌점만 준다.
  _Hypothesis withDeadEnd(double distanceM, double penaltyDeg) => _copy(
    cost: cost + penaltyDeg * distanceM,
    matchedM: matchedM + distanceM,
    unmatchedM: unmatchedM + distanceM,
  );

  /// 노드 전이 비용도 같은 지평선으로 잊는다.

  _Hypothesis _copy({
    double? progressM,
    int? travelSign,
    List<PdrLocalPoint>? path,
    double? cost,
    double? matchedM,
    double? unmatchedM,
    double? previousObservedHeadingDeg,
    double? previousGraphHeadingDeg,
  }) => _Hypothesis(
    edge: edge,
    progressM: progressM ?? this.progressM,
    travelSign: travelSign ?? this.travelSign,
    path: path ?? this.path,
    cost: cost ?? this.cost,
    matchedM: matchedM ?? this.matchedM,
    unmatchedM: unmatchedM ?? this.unmatchedM,
    previousObservedHeadingDeg:
        previousObservedHeadingDeg ?? this.previousObservedHeadingDeg,
    previousGraphHeadingDeg:
        previousGraphHeadingDeg ?? this.previousGraphHeadingDeg,
    transitions: transitions,
    lastNodeId: lastNodeId,
  );
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

  /// [radiusM] 안에 있는 모든 간선의 투영점. 빔의 시작 씨앗을 만든다.
  ///
  /// 가장 가까운 하나만 고르면 시작 위치가 평행 복도 사이에 있을 때 그 선택이
  /// 곧 최종 답이 된다. 후보를 다 깔고 걸음으로 걸러내는 편이 안전하다.
  List<_EdgeProjection> nearbyProjections(
    PdrLocalPoint point, {
    required double radiusM,
  }) {
    final found = <_EdgeProjection>[];
    for (final edge in edges) {
      if (edge.accessEdge) continue;
      final projection = edge.project(point);
      if (projection.distanceM <= radiusM) found.add(projection);
    }
    if (found.isEmpty) {
      final nearest = nearestProjection(point);
      if (nearest != null) found.add(nearest);
    }
    found.sort((left, right) => left.distanceM.compareTo(right.distanceM));
    return found;
  }

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
