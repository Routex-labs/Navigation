import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../domain/guidance/corridor_tracking.dart';
import '../../../models/building/floor_graph.dart';
import '../contract/pdr_anchor.dart';

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
    this.seedRadiusM = 5,
    this.seedPenaltyDegM = 25,
    this.positionalWeightDegPerM = 0.5,
    this.positionalToleranceM = 6,
    this.positionalMaxOffsetM = 12,
    this.leaderSwitchMarginDeg = 2.5,
    this.ambiguousMarginDeg = 6,
    this.maxHeadingCorrectionPerStepDeg = 0.75,
    this.headingBiasLimitDeg = 60,
    this.headingBiasMaxErrorDeg = 50,
    this.maxTransitionsPerSegment = 3,
    this.maxPathPoints = 800,
    this.maxTrackedPreviewPeaks = 512,
    this.optimisticReconcileMarginM = 2,
    this.junctionZoneRadiusM = 3.5,
    this.junctionZoneEdgeLengthRatio = 0.4,
    this.junctionShortcutPenaltyDegM = 4,
    this.junctionLeaderSwitchMarginDeg = 0.5,
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

  /// 시작 시 씨앗을 까는 반경(m). 사용자가 찍은 위치를 믿는 범위다.
  final double seedRadiusM;

  /// 시작 위치에서 1m 떨어진 씨앗에 매기는 **영구** 벌점(도·m).
  ///
  /// 이 벌점만은 [costHorizonM]으로 잊지 않는다. 잊으면 시작 지점 옆에 나란히
  /// 있던, 실제로는 한 번도 지나간 적 없는 복도의 씨앗이 25m 뒤에 공짜가 되어
  /// 원본 드리프트만으로 1등이 된다. 간선 전이로 도달한 가설과 달리 이 씨앗은
  /// 그래프 연결로 정당화된 적이 없으므로 끝까지 불리해야 한다.
  final double seedPenaltyDegM;

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

  /// optimistic beam이 "이미 태운 걸음"으로 기억하는 peak 식별자 수 상한.
  ///
  /// 확정 시간창을 지난 식별자는 어차피 다시 들어오지 않으므로 먼저 버린다.
  /// 이 상한은 시각이 없어 합성 식별자를 쓰는 세션의 안전장치다.
  final int maxTrackedPreviewPeaks;

  /// 확정 1등에서 optimistic cursor까지 그래프로 도달 가능한지 볼 때 선행분에
  /// 더해 주는 여유(m). 노드 좌표와 보행 거리의 미세한 차이를 흡수한다.
  final double optimisticReconcileMarginM;

  /// 방향 선택이 생기는 graph node 앞뒤로 회전을 허용하는 구간의 반경(m).
  ///
  /// 사람은 node 좌표를 정확히 밟지 않는다. 넓은 코너에서는 안쪽을 잘라 2~3m
  /// 일찍 꺾고, 짐을 들었거나 사람을 피하면 2~3m 지나서 꺾는다. node 통과를
  /// 기다렸다가 후보를 열면 그 사이 걸음이 전부 직진 가설에만 쌓여, 실제로
  /// 꺾은 사람의 마커가 코너에 붙어 버린다.
  ///
  /// 이 값은 **표시·상태 완충 구간**이지 없는 geometry를 만드는 장치가 아니다.
  /// 후보는 언제나 해당 node에 실제로 연결된 간선뿐이다.
  final double junctionZoneRadiusM;

  /// 짧은 간선에서 반경이 간선을 통째로 삼키지 않게 하는 비율 상한.
  ///
  /// 3m 간선이 연달아 붙은 구간에서 반경 3m를 그대로 쓰면 모든 노드가 항상
  /// 전환 구간이 되어, 전환 구간이라는 개념 자체가 무의미해진다.
  final double junctionZoneEdgeLengthRatio;

  /// 전환 구간에서 node로 당겨 붙일 때 남은 거리 1m당 물리는 벌점(도·m).
  ///
  /// 조기/지연 회전 가설은 아직 걷지 않은(또는 이미 지나친) 거리를 건너뛴다.
  /// 그 건너뛴 만큼 불리하게 두면, 방향 증거가 여러 걸음 이어질 때만 이긴다.
  final double junctionShortcutPenaltyDegM;

  /// 전환 구간 안에서 **연결된** 간선으로 1등을 넘겨줄 때의 완화된 여유(도).
  ///
  /// [leaderSwitchMarginDeg]는 평균 오차 기준이라 누적 보행 거리(약 25m)를
  /// 곱하면 60도·m가 넘는 관성이 된다. 직선 복도에서 화면이 복도 사이를 오가는
  /// 것을 막는 데는 옳지만, **회전이 예정된 지점**에서는 정상 회전조차 대여섯
  /// 걸음 늦게 반영된다. 전환 구간에서 연결된 간선으로 넘어가는 경우에만
  /// 관성을 줄인다 — 연결되지 않은 평행 간선에는 여전히 원래 여유를 쓴다.
  final double junctionLeaderSwitchMarginDeg;
}

/// 실시간 preview 걸음 하나.
///
/// [peakId]가 **적용 식별자**다. 같은 걸음이 preview로 한 번, confirmed 배치로
/// 다시 한 번 보고돼도 optimistic cursor는 이 값으로 중복을 걸러 한 번만
/// 전진한다. 배치 크기를 어떻게 잘라도 표시 위치 시계열이 같아지는 근거다.
class TimedPreviewStep {
  const TimedPreviewStep({required this.peakId, required this.rawPoint});

  final int peakId;
  final PdrLocalPoint rawPoint;
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
    this.rawPreviewTailPeakTimesMs = const [],
    this.confirmedThroughMs,
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

  /// [rawPreviewTailPositions]와 **같은 인덱스**의 accepted peak 시각.
  ///
  /// 비어 있거나 길이가 다르면 세션 안에서만 유효한 합성 식별자로 폴백한다
  /// ([CorridorTrackingResult.previewPeakIdsSynthetic]가 true가 된다).
  final List<int?> rawPreviewTailPeakTimesMs;

  /// 확정 배치가 소비한 시간창의 끝. 이 시각 이하의 preview peak는 이미
  /// 확정으로 넘어갔으므로 optimistic cursor를 다시 전진시키지 않는다.
  final int? confirmedThroughMs;

  /// tail 직전 위치. 첫 preview 걸음의 이동 벡터 기준점이다.
  PdrLocalPoint? get previewTailOriginM =>
      rawPreviewTailPositions.isEmpty ? null : rawPreviewTailPositions.first;

  /// tail을 식별자가 붙은 걸음 목록으로 편다.
  ///
  /// 시각이 없으면 누적 preview 걸음 번호로 합성한다. 누적값이라 단조 증가하고
  /// 배치 구성과 무관하므로, 시각이 없는 Android·옛 fixture에서도 같은 걸음이
  /// 두 번 적용되지 않는다. 실제 시각과 섞이지 않게 음수로 만든다.
  List<TimedPreviewStep> get timedPreviewSteps {
    final points = rawPreviewTailPositions;
    if (points.length < 2) return const [];
    final times = rawPreviewTailPeakTimesMs.length == points.length
        ? rawPreviewTailPeakTimesMs
        : const <int?>[];
    final movementCount = points.length - 1;
    return [
      for (var index = 1; index < points.length; index += 1)
        TimedPreviewStep(
          peakId:
              (times.isEmpty ? null : times[index]) ??
              -(previewSteps - (movementCount - index) + 1),
          rawPoint: points[index],
        ),
    ];
  }

  /// tail 안에 시각이 빠진 걸음이 있는지. 진단 warning의 근거다.
  bool get hasSyntheticPreviewPeakIds {
    final points = rawPreviewTailPositions;
    if (points.length < 2) return false;
    if (rawPreviewTailPeakTimesMs.length != points.length) return true;
    for (var index = 1; index < points.length; index += 1) {
      if (rawPreviewTailPeakTimesMs[index] == null) return true;
    }
    return false;
  }
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
    required this.confirmedDisplacementM,
    required this.optimisticLeadM,
    required this.optimisticEdgeId,
    required this.optimisticEdgeProgressM,
    required this.previewPeakIdsSynthetic,
    required this.junctionNodeId,
    required this.junctionDistanceM,
    required this.junctionCandidateEdgeIds,
    required this.leaderRelocated,
    this.optimisticStepAdvances = const [],
  });

  final CorridorTrackingState state;
  final PdrLocalPoint correctedPosition;

  /// 지금 걷고 있다고 보는 **간선의 방위**. 경로 진행·역주행 판정의 기준이다.
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

  /// 이번 확정 배치 전후 보정 위치의 직선거리. 대표 가설 교체로 생긴 위치
  /// 재해석까지 포함할 수 있어 실제 보행 거리와는 구분한다.
  final double confirmedDisplacementM;

  /// 확정 cursor에서 optimistic cursor까지 그래프 경로 길이(m).
  ///
  /// 선행분을 따로 "안정화"하지 않는다. optimistic beam이 실제로 태운 거리에서
  /// 확정 보행 거리를 뺀 값이라, 배치가 도착해도 정의상 뒤로 가지 않는다.
  final double optimisticLeadM;

  /// optimistic cursor가 올라타 있는 간선과 그 위 진행 거리.
  final String? optimisticEdgeId;
  final double optimisticEdgeProgressM;

  /// preview peak 식별자를 accepted peak 시각이 아니라 걸음 번호로 합성했는지.
  final bool previewPeakIdsSynthetic;

  /// 지금 통과 중인 회전 허용 구간의 graph node. 구간 밖이면 null.
  final String? junctionNodeId;

  /// [junctionNodeId]까지(또는 그 node에서) 남은 거리(m).
  final double junctionDistanceM;

  /// 그 node에 **실제로 연결된** 간선 후보. 없는 길은 여기에 나타나지 않는다.
  final List<String> junctionCandidateEdgeIds;

  /// 회전 허용 구간 안인지. 재탐색을 잠시 유예할지 판단하는 신호다.
  bool get isInJunctionZone => junctionNodeId != null;

  /// 보정 위치 변화가 이번 확정 보행 거리로 설명되지 않는 대표 가설 재배치인지.
  final bool leaderRelocated;

  /// 이번 update에서 처음 적용된 preview peak별 이동 사건.
  final List<OptimisticStepAdvance> optimisticStepAdvances;
}

/// 초록·주황 원본을 수정하지 않고 실제 위치만 graph 제약으로 보정한다.
///
/// **빔 서치**다 — 간선 하나를 잠그는 대신 가설 여럿을 동시에 들고 걸음마다 점수를
/// 매겨 언제든 1등이 바뀔 수 있게 둔다. 이전의 탐욕적 상태기는 회전을 한 번 놓치면
/// 되돌릴 수 없어 실측에서 교차점에 28초 멈춰 있었다.
///
/// 위치는 절대 멈추지 않는다 — 어떤 가설도 설명되지 않으면 벌점을 주되 진행시켜
/// 걸은 거리가 통째로 사라지지 않게 한다.
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

  /// 화면 위치를 들고 있는 두 번째 빔. 확정 빔과 **따로** 산다.
  ///
  /// 매 snapshot마다 확정 1등에서 다시 만들지 않는다. 새 accel peak가 생긴
  /// 즉시 한 번 전진하고, 그 뒤 확정 배치가 같은 peak를 확인하더라도 다시
  /// 전진하거나 뒤로 가지 않는다.
  List<_Hypothesis> _optimisticBeam = const [];

  /// optimistic beam에 이미 태운 preview peak 식별자(오래된 것부터).
  final List<int> _appliedPreviewPeakIds = [];
  final Set<int> _appliedPreviewPeakIdSet = {};

  /// optimistic·confirmed가 각각 태운 누적 보행 거리(m).
  double _optimisticTraveledM = 0;
  double _confirmedTraveledM = 0;
  bool _previewPeakIdsSynthetic = false;

  /// 직전 확정 배치의 마지막 걸음 방위(bias 적용 전). preview 없이 배치로만
  /// 들어온 걸음을 optimistic beam에 태울 때 쓴다.
  double? _lastConfirmedSegmentHeadingDeg;

  String? _junctionNodeId;
  double _junctionDistanceM = double.infinity;
  List<String> _junctionCandidateEdgeIds = const [];

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

  /// 이번 갱신에서 확정 위치가 나아간 거리(m).
  double _confirmedAdvanceM = 0;
  bool _leaderRelocated = false;
  final List<OptimisticStepAdvance> _optimisticStepAdvances = [];

  bool get isInitialized => _beam.isNotEmpty;

  _Hypothesis? get _best => _beam.isEmpty ? null : _beam.first;

  _Hypothesis? get _optimisticBest =>
      _optimisticBeam.isEmpty ? null : _optimisticBeam.first;

  double get _optimisticLeadM =>
      math.max(0.0, _optimisticTraveledM - _confirmedTraveledM);

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
    confirmedDisplacementM: _confirmedAdvanceM,
    optimisticLeadM: _optimisticLeadM,
    optimisticEdgeId: _optimisticBest?.edge.id,
    optimisticEdgeProgressM: _optimisticBest?.progressM ?? 0,
    previewPeakIdsSynthetic: _previewPeakIdsSynthetic,
    junctionNodeId: _junctionNodeId,
    junctionDistanceM: _junctionDistanceM,
    junctionCandidateEdgeIds: List.unmodifiable(_junctionCandidateEdgeIds),
    leaderRelocated: _leaderRelocated,
    optimisticStepAdvances: List.unmodifiable(_optimisticStepAdvances),
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
    _confirmedAdvanceM = 0;
    _leaderRelocated = false;
    _optimisticStepAdvances.clear();
    _lastConfirmedSegmentHeadingDeg = null;
    // 두 beam과 식별자 상태를 함께 초기화한다. 하나만 남기면 새 세션의 첫
    // peak가 "이미 태운 걸음"으로 걸러진다.
    _appliedPreviewPeakIds.clear();
    _appliedPreviewPeakIdSet.clear();
    _optimisticBeam = const [];
    _confirmedTraveledM = initialConfirmedDistanceM;
    _optimisticTraveledM = initialConfirmedDistanceM;
    _previewPeakIdsSynthetic = false;

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
    _updateJunctionState();
  }

  CorridorTrackingResult update(CorridorObservation observation) {
    if (!isInitialized) {
      reset(
        initialPosition: observation.rawConfirmedPosition,
        initialHeadingDeg: observation.sensorHeadingDeg,
        timestampMs: observation.timestampMs,
      );
    }
    _optimisticStepAdvances.clear();
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
    _leaderRelocated = false;
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
        _lastConfirmedSegmentHeadingDeg = segment.headingDeg;
      }
      _updateHeadingBias();
      _publishConfirmed(transitionsBefore: transitionsBefore);
      _confirmedAdvanceM = (_correctedPosition - previousCorrected).distance;
      // 그래프를 따라 실제로 걸었다면 두 끝점의 직선거리는 보행 경로 길이를
      // 넘을 수 없다. 0.5m 여유를 넘는 차이는 빔 1등 교체로 위치 해석이
      // 재배치된 것이다.
      _leaderRelocated = _confirmedAdvanceM > deltaDistanceM + 0.5;
    }

    _lastConfirmedSteps = math.max(
      _lastConfirmedSteps,
      observation.confirmedSteps,
    );
    _lastConfirmedDistanceM = math.max(
      _lastConfirmedDistanceM,
      observation.confirmedDistanceM,
    );
    _confirmedTraveledM = _lastConfirmedDistanceM;
    _lastPreviewSteps = math.max(_lastPreviewSteps, observation.previewSteps);

    // 확정 → optimistic 순서를 지킨다. 확정이 다른 복도로 옮겨 갔는지 먼저
    // 판단해야, 이번 프레임의 새 peak를 어느 cursor 위에 태울지가 정해진다.
    _reconcileOptimistic();
    _applyPreviewPeaks(observation);
    _catchUpOptimisticToConfirmed();
    _forgetAcknowledgedPeakIds(observation.confirmedThroughMs);
    _publishPreview();
    _updateJunctionState();
    return result;
  }

  // ── 빔 ──

  List<_Hypothesis> _seedHypotheses(PdrLocalPoint position, double headingDeg) {
    final seeds = <_Hypothesis>[];
    for (final projection in _network.nearbyProjections(
      position,
      radiusM: config.seedRadiusM,
    )) {
      for (final sign in const [1, -1]) {
        if (sign < 0 && !projection.edge.bidirectional) continue;
        seeds.add(
          _Hypothesis(
            edge: projection.edge,
            progressM: projection.distanceAlongM,
            travelSign: sign,
            path: [projection.point],
            cost: 0,
            matchedM: 0,
            // 잊히지 않는 벌점. 시작 지점에서 먼 씨앗일수록 끝까지 불리하다.
            seedPenaltyDegM: projection.distanceM * config.seedPenaltyDegM,
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
      offEdgeSlackLimitM: config.junctionZoneRadiusM,
    );
    if (remainingM <= distanceToEnd + 1e-6) {
      // 노드를 아직 넘지 않았다. 여기서 끝내면 회전 후보는 노드를 지난 뒤에야
      // 열리고, 그 사이 걸음이 전부 직진 가설에만 쌓인다. 전환 구간 안이면
      // **연결된** 간선 후보를 미리·아직 열어 둔다.
      final alternatives = depth == 0
          ? _junctionAlternatives(advanced, observedHeadingDeg, rawPoint)
          : const <_Hypothesis>[];
      return alternatives.isEmpty ? [advanced] : [advanced, ...alternatives];
    }

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
            rawPoint: rawPoint,
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

  /// 전환 구간 안에서 열어 둘 회전 가설.
  ///
  /// 두 방향 모두 같은 규칙이다.
  ///
  /// - **빠른 회전**: 진행 방향 끝 노드까지 반경 안이면, 아직 노드를 밟지
  ///   않았어도 연결된 outgoing 후보를 만든다.
  /// - **늦은 회전**: 방금 지나온 노드에서 반경 안이면, 그 노드의 다른 연결
  ///   간선 후보를 아직 살려 둔다.
  ///
  /// 두 경우 모두 위치가 노드까지 [건너뛴] 거리에 비례해 벌점을 물고, 관측
  /// 방향이 그쪽을 실제로 지지할 때만 만들어진다. 걸음이 없으면 이 함수 자체가
  /// 호출되지 않으므로(제자리 heading 회전은 [_advance]로 들어오지 않는다)
  /// 휴대폰만 돌려서 간선이 바뀌는 일은 없다.
  List<_Hypothesis> _junctionAlternatives(
    _Hypothesis advanced,
    double observedHeadingDeg,
    PdrLocalPoint rawPoint,
  ) {
    final edge = advanced.edge;
    final endNodeId = edge.nodeAtTravelEnd(advanced.travelSign);
    final startNodeId = edge.nodeAtTravelEnd(-advanced.travelSign);
    final distanceToEndM = advanced.travelSign > 0
        ? edge.lengthM - advanced.progressM
        : advanced.progressM;
    final distanceFromStartM = edge.lengthM - distanceToEndM;
    final currentBearing = edge.bearingForTravel(
      advanced.progressM,
      advanced.travelSign,
    );

    final alternatives = <_Hypothesis>[];
    void openAt(String nodeId, double rawSkipM, {required bool ahead}) {
      // 회전 중에는 이 간선을 따라 걷고 있지 않다. 그 구간만큼 창을 되돌린다.
      final skipM = math.max(0.0, rawSkipM - advanced.offEdgeDistanceM);
      if (skipM <= 1e-6 || skipM > _junctionZoneRadiusM(edge)) return;
      if (!_network.isDirectionDecisionNode(edge, nodeId)) return;
      final node = _network.nodes[nodeId];
      if (node == null) return;
      for (final option in _network.recoveryOptionsFromNode(nodeId)) {
        if (option.edge.id == edge.id) continue;
        if (skipM > _junctionZoneRadiusM(option.edge)) continue;
        // 관측이 지금 간선보다 이쪽을 더 잘 설명할 때만 후보를 연다.
        if (_headingError(observedHeadingDeg, option.bearingDeg) >=
            _headingError(observedHeadingDeg, currentBearing)) {
          continue;
        }
        alternatives.add(
          advanced.enter(
            option,
            nodeId: nodeId,
            nodePoint: node.point,
            rawPoint: rawPoint,
            penaltyDegM:
                config.transitionPenaltyDegM +
                skipM * config.junctionShortcutPenaltyDegM,
            turnedGraphHeadingDeg: option.bearingDeg,
            approachPath: ahead
                ? edge.pointsBetween(
                    advanced.progressM,
                    advanced.travelSign > 0 ? edge.lengthM : 0,
                  )
                : const [],
            trimTailM: ahead ? 0 : rawSkipM,
          ),
        );
      }
    }

    openAt(endNodeId, distanceToEndM, ahead: true);
    // 지나온 쪽은 **방금 그 노드를 통해 들어온 가설**만 되돌린다. 그러지 않으면
    // 모든 간선의 시작 노드가 항상 후보를 열어 빔이 분기로 가득 찬다.
    if (advanced.lastNodeId == startNodeId) {
      openAt(startNodeId, distanceFromStartM, ahead: false);
    }
    return alternatives;
  }

  /// 표시 중인 가설이 전환 구간 안이고 도전자가 그 node에 **연결된** 간선인가.
  ///
  /// 여기서만 1등 교체 관성을 줄인다. 연결되지 않은 평행 간선은 아무리 가까워도
  /// 이 조건을 통과하지 못한다.
  bool _isJunctionTurn(_Hypothesis held, _Hypothesis challenger) {
    if (held.edge.id == challenger.edge.id) return false;
    final junction = _network.nearestJunctionOn(
      held.edge,
      held.edge.pointAt(held.progressM),
      maxDistanceM: _junctionZoneRadiusM(held.edge) + held.offEdgeDistanceM,
    );
    if (junction == null) return false;
    return _network
        .recoveryOptionsFromNode(junction.node.id)
        .any((option) => option.edge.id == challenger.edge.id);
  }

  /// 이 간선에서 쓸 전환 구간 반경. 짧은 간선을 통째로 삼키지 않게 제한한다.
  double _junctionZoneRadiusM(_CorridorEdge edge) => math.min(
    config.junctionZoneRadiusM,
    edge.lengthM * config.junctionZoneEdgeLengthRatio,
  );

  /// 지금 표시 위치가 어느 전환 구간 안인지 갱신한다. 재탐색 유예의 근거다.
  void _updateJunctionState() {
    final leader = _optimisticBest ?? _best;
    if (leader == null) {
      _junctionNodeId = null;
      _junctionDistanceM = double.infinity;
      _junctionCandidateEdgeIds = const [];
      return;
    }
    final junction = _network.nearestJunctionOn(
      leader.edge,
      leader.edge.pointAt(leader.progressM),
      // 회전 중 진행한 거리는 창에서 빼 준다. `_junctionAlternatives`가 후보를
      // 열어 두는 구간과 재탐색을 유예하는 구간이 어긋나면 안 된다.
      maxDistanceM: _junctionZoneRadiusM(leader.edge) + leader.offEdgeDistanceM,
    );
    if (junction == null) {
      _junctionNodeId = null;
      _junctionDistanceM = double.infinity;
      _junctionCandidateEdgeIds = const [];
      return;
    }
    _junctionNodeId = junction.node.id;
    _junctionDistanceM = junction.distanceM;
    _junctionCandidateEdgeIds = [
      for (final option in _network.recoveryOptionsFromNode(junction.node.id))
        option.edge.id,
    ];
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
    final marginDeg = held != null && _isJunctionTurn(held, globalBest)
        ? config.junctionLeaderSwitchMarginDeg
        : config.leaderSwitchMarginDeg;
    if (held == null ||
        globalBest.meanErrorDeg < held.meanErrorDeg - marginDeg) {
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

  // ── optimistic preview cursor ──

  /// 확정 1등이 optimistic cursor와 더 이상 같은 길 위에 있지 않을 때만
  /// 화면 cursor를 재배치한다.
  ///
  /// 배치 수신 자체는 marker 이동 이벤트가 아니다. 확정 빔이 optimistic cursor를
  /// 그래프로 따라잡을 수 있는 한(같은 간선이거나 앞으로 연결된 간선), cursor는
  /// 그대로 둔다 — 그게 "배치가 와도 뒤로 가지 않는다"의 구현이다.
  void _reconcileOptimistic() {
    final best = _best;
    if (best == null) {
      _optimisticBeam = const [];
      return;
    }
    final leader = _optimisticBest;
    if (leader == null) {
      _rebaseOptimistic(best);
      return;
    }
    if (leader.edge.id == best.edge.id &&
        leader.travelSign == best.travelSign) {
      return;
    }
    if (_network.isForwardReachable(
      fromEdge: best.edge,
      travelSign: best.travelSign,
      progressM: best.progressM,
      targetEdgeId: leader.edge.id,
      maxDistanceM: _optimisticLeadM + config.optimisticReconcileMarginM,
    )) {
      return;
    }
    // 그래프로 설명되지 않는 1등 교체. 화면을 옛 복도에 남겨 두면 그때부터
    // 모든 갱신이 틀린 자리에서 시작하므로 확정 쪽으로 되돌린다.
    _leaderRelocated = true;
    _rebaseOptimistic(best);
  }

  void _rebaseOptimistic(_Hypothesis confirmedLeader) {
    _optimisticBeam = [confirmedLeader.forPreview()];
    _optimisticTraveledM = _confirmedTraveledM;
  }

  /// 아직 태우지 않은 preview peak만 시간순으로 한 번 적용한다.
  void _applyPreviewPeaks(CorridorObservation observation) {
    if (observation.hasSyntheticPreviewPeakIds) {
      _previewPeakIdsSynthetic = true;
    }
    var origin = observation.previewTailOriginM;
    if (origin == null) return;
    for (final step in observation.timedPreviewSteps) {
      final previous = origin!;
      origin = step.rawPoint;
      if (!_rememberPreviewPeak(step.peakId)) continue;
      final movement = step.rawPoint - previous;
      if (movement.distance <= 1e-6) continue;
      _advanceOptimistic(
        headingDeg: pdrBearingForDirection(movement),
        distanceM: movement.distance,
        rawPoint: step.rawPoint,
        peakId: step.peakId,
        occurredAtMs: step.peakId > 0 ? step.peakId : observation.timestampMs,
      );
      _optimisticTraveledM += movement.distance;
    }
  }

  /// preview로 한 번도 보이지 않고 배치로만 들어온 걸음을 태운다.
  ///
  /// 두 beam이 같은 걸음을 두 번 먹지 않으면서도, optimistic cursor가 확정보다
  /// 뒤에 남는 일은 없어야 한다. 차이는 항상 "preview가 놓친 걸음"이다.
  void _catchUpOptimisticToConfirmed() {
    final deficitM = _confirmedTraveledM - _optimisticTraveledM;
    if (deficitM <= 1e-6) return;
    final best = _best;
    if (best == null) return;
    if (_optimisticBeam.isEmpty) _rebaseOptimistic(best);
    // 확정 간선의 방위가 아니라 **관측 방향**을 쓴다. 간선 방위를 넣으면
    // optimistic beam이 확정 1등의 선택을 그대로 베끼게 되어, 회전을 스스로
    // 발견할 수 없다(관측이 항상 지금 간선과 일치하는 것처럼 보인다).
    _advanceOptimistic(
      headingDeg: _lastConfirmedSegmentHeadingDeg ?? _sensorHeadingDeg,
      distanceM: deficitM,
      rawPoint: _rawConfirmedPosition,
    );
    _optimisticTraveledM = _confirmedTraveledM;
  }

  void _advanceOptimistic({
    required double headingDeg,
    required double distanceM,
    required PdrLocalPoint rawPoint,
    int? peakId,
    int? occurredAtMs,
  }) {
    if (_optimisticBeam.isEmpty) return;
    final previousLeaderId = _optimisticBest!.diagnosticId;
    final observed = _normalizeBearing(headingDeg + _headingBiasDeg);
    final next = <_Hypothesis>[];
    for (final original in _optimisticBeam) {
      final hypothesis = original.beginStep();
      next.addAll(_advance(hypothesis, observed, distanceM, rawPoint));
      // 실제 유턴은 반영한다. 반대 부호 가설을 함께 만들어 두면 비용이
      // 판정하고, 이길 경우 cursor가 뒤로 가는 것도 허용된다.
      final currentBearing = hypothesis.edge.bearingForTravel(
        hypothesis.progressM,
        hypothesis.travelSign,
      );
      if (hypothesis.edge.bidirectional &&
          _headingError(observed, currentBearing) >= config.reverseTriggerDeg) {
        next.addAll(
          _advance(hypothesis.reversed(), observed, distanceM, rawPoint),
        );
      }
    }
    if (next.isEmpty) return;
    _optimisticBeam = _prune(next);
    final leader = _optimisticBest!;
    if (peakId != null && occurredAtMs != null) {
      final runnerUp = _optimisticBeam.length > 1 ? _optimisticBeam[1] : null;
      final previewIsAmbiguous =
          runnerUp != null &&
          runnerUp.edge.id != leader.edge.id &&
          runnerUp.meanErrorDeg - leader.meanErrorDeg <
              config.ambiguousMarginDeg;
      final traversals = List<OptimisticEdgeTraversal>.unmodifiable(
        leader.stepTraversals,
      );
      _optimisticStepAdvances.add(
        OptimisticStepAdvance(
          peakId: peakId,
          occurredAtMs: occurredAtMs,
          hypothesisId: leader.diagnosticId,
          parentHypothesisId: leader.stepParentHypothesisId ?? previousLeaderId,
          distanceM: traversals.fold(0, (sum, item) => sum + item.distanceM),
          edgeId: leader.edge.id,
          mapMatchedHeadingDeg: leader.edge.bearingForTravel(
            leader.progressM,
            leader.travelSign,
          ),
          previewIsAmbiguous: previewIsAmbiguous,
          position: leader.edge.pointAt(leader.progressM),
          traversals: traversals,
          crossedNodeIds: List<String>.unmodifiable(leader.stepCrossedNodeIds),
          leaderRelocated:
              _leaderRelocated ||
              leader.stepParentHypothesisId != previousLeaderId,
        ),
      );
    }
  }

  /// 처음 보는 peak면 기억하고 true. 이미 태운 peak면 false.
  bool _rememberPreviewPeak(int peakId) {
    if (!_appliedPreviewPeakIdSet.add(peakId)) return false;
    _appliedPreviewPeakIds.add(peakId);
    while (_appliedPreviewPeakIds.length > config.maxTrackedPreviewPeaks) {
      _appliedPreviewPeakIdSet.remove(_appliedPreviewPeakIds.removeAt(0));
    }
    return true;
  }

  /// 확정 시간창을 지난 식별자는 다시 tail에 나타나지 않으므로 잊는다.
  void _forgetAcknowledgedPeakIds(int? confirmedThroughMs) {
    if (confirmedThroughMs == null) return;
    while (_appliedPreviewPeakIds.isNotEmpty) {
      final oldest = _appliedPreviewPeakIds.first;
      // 합성 식별자(음수)는 시각 축이 아니므로 개수 상한으로만 관리한다.
      if (oldest < 0 || oldest > confirmedThroughMs) break;
      _appliedPreviewPeakIdSet.remove(_appliedPreviewPeakIds.removeAt(0));
    }
  }

  void _publishPreview() {
    final leader = _optimisticBest;
    if (leader == null) {
      _resetPreviewToConfirmed();
      return;
    }
    final runnerUp = _optimisticBeam.length > 1 ? _optimisticBeam[1] : null;
    // 모호 판정에 히스테리시스를 준다. 단일 임계값을 쓰면 점수가 그 근처에서
    // 오갈 때마다 후보 목록이 프레임마다 뒤집힌다.
    final gapDeg = runnerUp == null || runnerUp.edge.id == leader.edge.id
        ? double.infinity
        : runnerUp.meanErrorDeg - leader.meanErrorDeg;
    final exitThreshold = config.ambiguousMarginDeg * 2;
    _previewIsAmbiguous = _previewIsAmbiguous
        ? gapDeg < exitThreshold
        : gapDeg < config.ambiguousMarginDeg;

    _previewPosition = leader.edge.pointAt(leader.progressM);
    _previewHeadingDeg = leader.edge.bearingForTravel(
      leader.progressM,
      leader.travelSign,
    );
    // 표시 경로는 확정 위치에서 optimistic cursor까지의 **선행분**이다.
    // 선행분을 별도 scalar로 안정화하지 않고 두 누적 거리의 차이로 정의하므로,
    // 배치가 확인만 하고 지나가는 프레임에서는 값이 그대로 유지된다.
    final tail = _takeLastLength(leader.path, _optimisticLeadM);
    _previewPath
      ..clear()
      ..addAll(tail.isEmpty ? [_previewPosition] : tail);
    final seen = <String>{};
    _previewCandidateEdgeIds = [
      for (final candidate in _optimisticBeam)
        if (seen.add(candidate.edge.id)) candidate.edge.id,
    ];
  }

  /// 경로 **끝에서부터** [lengthM]만큼만 남긴다. 첫 점은 정확히 그 지점이다.
  static List<PdrLocalPoint> _takeLastLength(
    List<PdrLocalPoint> path,
    double lengthM,
  ) {
    if (path.isEmpty) return const [];
    if (lengthM <= 1e-9) return [path.last];
    final tail = <PdrLocalPoint>[path.last];
    var remaining = lengthM;
    for (var index = path.length - 1; index >= 1; index -= 1) {
      final step = (path[index] - path[index - 1]).distance;
      if (step <= 1e-9) continue;
      if (remaining >= step) {
        tail.add(path[index - 1]);
        remaining -= step;
        continue;
      }
      if (remaining > 1e-6) {
        final t = remaining / step;
        tail.add(
          PdrLocalPoint(
            path[index].eastM + (path[index - 1].eastM - path[index].eastM) * t,
            path[index].northM +
                (path[index - 1].northM - path[index].northM) * t,
          ),
        );
      }
      break;
    }
    return tail.reversed.toList(growable: false);
  }

  void _resetPreviewToConfirmed() {
    _previewPosition = _correctedPosition;
    _previewHeadingDeg = result.correctedHeadingDeg;
    _previewPath
      ..clear()
      ..add(_correctedPosition);
    _previewCandidateEdgeIds = const [];
    _previewIsAmbiguous = false;
    final best = _best;
    if (best != null) {
      _rebaseOptimistic(best);
    } else {
      _optimisticBeam = const [];
      _optimisticTraveledM = _confirmedTraveledM;
    }
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
    this.previousOffsetM = 0,
    this.seedPenaltyDegM = 0,
    this.offEdgeDistanceM = 0,
    this.stepParentHypothesisId,
    this.stepTraversals = const [],
    this.stepCrossedNodeIds = const [],
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

  /// 직전 걸음에서 원본 위치와 벌어져 있던 거리(m).
  final double previousOffsetM;

  /// 시작 위치에서 떨어져 있던 만큼의 영구 벌점(도·m). 감쇠하지 않는다.
  final double seedPenaltyDegM;

  /// 이 간선 방향과 **크게 어긋난 채** 진행한 거리(m).
  ///
  /// 회전 허용 구간을 그래프 진행거리만으로 재면, 사람이 코너에서 직각으로
  /// 꺾는 동안에도 가설의 progress는 원래 간선을 따라 계속 늘어난다. 그래서
  /// 정작 회전 중일 때 창이 닫힌다. 이 값만큼 창을 되돌려 주면, "지금 이
  /// 간선을 따라 걷고 있지 않다"는 구간에서는 창이 유지된다.
  final double offEdgeDistanceM;

  /// 현재 preview peak를 적용하기 직전 lineage와, 그 peak 안에서 지난 graph
  /// 조각. 다음 peak가 시작될 때 [beginStep]이 비운다.
  final String? stepParentHypothesisId;
  final List<OptimisticEdgeTraversal> stepTraversals;
  final List<String> stepCrossedNodeIds;

  String get diagnosticId =>
      '${edge.id}:$travelSign:${progressM.toStringAsFixed(3)}:$transitions';

  /// 가설끼리 비교하는 값. 같은 걸음을 먹었으므로 거리 정규화만으로 공평하다.
  double get meanErrorDeg => matchedM <= 1e-6
      ? cost + seedPenaltyDegM
      : (cost + seedPenaltyDegM) / matchedM;

  _Hypothesis reversed() => _copy(travelSign: -travelSign);

  _Hypothesis beginStep() => _Hypothesis(
    edge: edge,
    progressM: progressM,
    travelSign: travelSign,
    path: path,
    cost: cost,
    matchedM: matchedM,
    unmatchedM: unmatchedM,
    previousObservedHeadingDeg: previousObservedHeadingDeg,
    previousGraphHeadingDeg: previousGraphHeadingDeg,
    transitions: transitions,
    lastNodeId: lastNodeId,
    previousOffsetM: previousOffsetM,
    seedPenaltyDegM: seedPenaltyDegM,
    offEdgeDistanceM: offEdgeDistanceM,
    stepParentHypothesisId: diagnosticId,
  );

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
    required double offEdgeSlackLimitM,
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
    final nextTraversals = nextProgress == progressM
        ? stepTraversals
        : [
            ...stepTraversals,
            OptimisticEdgeTraversal(
              edgeId: edge.id,
              fromProgressM: progressM,
              toProgressM: nextProgress,
            ),
          ];
    // 나란한 복도를 가르는 신호. 다만 **절대 어긋남**을 벌하면 안 된다 —
    // PDR 원본은 heading 오차로 옆으로 밀리고(실측 안드로이드 87m 보행에서
    // north 방향 13m), 그러면 원본이 밀려간 쪽의 엉뚱한 평행 복도가 오히려
    // 가까워져서 그리로 붙는다. 실제로 남쪽 매장 앞을 걸었는데 10m 북쪽
    // 복도로 올라가 버렸다.
    //
    // 그래서 어긋남의 **증가분**만 벌한다. 서서히 밀리는 드리프트는 걸음당
    // 증가가 미미해 거의 공짜이고, 갈림길에서 엉뚱한 쪽으로 꺾는 순간에는
    // 급격히 벌어져 크게 물린다.
    final offsetNowM = (nextPoint - rawPoint).distance;
    final grownM = (offsetNowM - previousOffsetM)
        .clamp(0.0, positionalMaxOffsetM)
        .toDouble();
    final offsetM =
        grownM * 10 +
        (offsetNowM - positionalToleranceM).clamp(0.0, positionalMaxOffsetM) *
            0.15;
    final nextPath = path.length >= maxPathPoints
        ? [...path.skip(path.length - maxPathPoints + 1), nextPoint]
        : [...path, nextPoint];
    // 오래된 증거를 지수적으로 잊는다. 그래야 후반에도 최근 구간이 순위를
    // 바꿀 수 있다.
    final decay = math.exp(-distanceM / costHorizonM);
    // 이 간선을 따라 걷고 있지 않은 구간만 센다. 다시 정렬되면 같은 지평선으로
    // 잊어 창이 영구히 열려 있지 않게 한다.
    final nextOffEdgeM = absoluteError > 60
        ? math.min(offEdgeSlackLimitM, offEdgeDistanceM + distanceM)
        : offEdgeDistanceM * decay;
    return _copy(
      progressM: nextProgress,
      path: nextPath,
      offEdgeDistanceM: nextOffEdgeM,
      cost:
          cost * decay +
          combined * distanceM +
          offsetM * positionalWeightDegPerM * distanceM,
      matchedM: matchedM * decay + distanceM,
      unmatchedM: unmatchedM * decay,
      previousOffsetM: offsetNowM,
      previousObservedHeadingDeg: observedHeadingDeg,
      previousGraphHeadingDeg: graphHeadingDeg,
      stepTraversals: nextTraversals,
    );
  }

  _Hypothesis enter(
    _RecoveryOption option, {
    required String nodeId,
    required PdrLocalPoint nodePoint,
    required PdrLocalPoint rawPoint,
    required double penaltyDegM,
    double? turnedGraphHeadingDeg,
    List<PdrLocalPoint> approachPath = const [],
    double trimTailM = 0,
  }) => _Hypothesis(
    edge: option.edge,
    progressM: option.travelSign > 0 ? 0 : option.edge.lengthM,
    travelSign: option.travelSign,
    // 전환 구간 가설의 경로는 **복도를 따라** node까지 간 뒤 새 간선으로
    // 넘어간다. 지금 위치에서 node로 직선을 그으면 그 선이 매장을 가로지르고,
    // 걸은 궤적이 지도 위에서 순간이동한 것처럼 보인다.
    //
    // 지나쳐 놓고 되돌아오는 경우(늦은 회전)에는 그 사이 그려 둔 꼬리를
    // 지운다. 남겨 두면 실제로 걷지 않은 왕복이 궤적에 남는다.
    path: [..._dropLastLength(path, trimTailM), ...approachPath, nodePoint],
    cost: cost + penaltyDegM,
    matchedM: matchedM,
    unmatchedM: unmatchedM,
    previousObservedHeadingDeg: previousObservedHeadingDeg,
    // 전환 구간 가설은 "회전이 방금 여기서 일어났다"고 주장한다. 그런데 관측
    // 쪽 회전은 직전 걸음에 이미 기록됐으므로, 그래프 쪽 기준을 이전 간선에
    // 두면 **다음 걸음**에서 있지도 않은 방위 변화가 형태 오차로 잡힌다.
    // 회전 비용은 이미 전이 벌점으로 물었으니 두 번 물리지 않는다.
    previousGraphHeadingDeg: turnedGraphHeadingDeg ?? previousGraphHeadingDeg,
    transitions: transitions + 1,
    lastNodeId: nodeId,
    // 노드로 옮겨 앉은 그 순간의 어긋남을 새 기준으로 삼는다.
    //
    // 위치 항은 "갈림길에서 엉뚱한 쪽으로 꺾는 순간 급격히 벌어지는" 것을
    // 벌하려고 어긋남의 **증가분**을 본다. 그런데 노드 전이 자체가 위치를
    // 옮기므로, 직전 간선 기준 어긋남을 그대로 물려주면 전이 첫 걸음이 항상
    // 큰 증가분을 문다. 코너를 잘라 도는 정상 보행이 그 벌점 때문에 여섯
    // 걸음 뒤에야 이겼다.
    previousOffsetM: (nodePoint - rawPoint).distance,
    seedPenaltyDegM: seedPenaltyDegM,
    stepParentHypothesisId: stepParentHypothesisId,
    stepTraversals: stepTraversals,
    stepCrossedNodeIds: [...stepCrossedNodeIds, nodeId],
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
    double? previousOffsetM,
    double? offEdgeDistanceM,
    List<OptimisticEdgeTraversal>? stepTraversals,
  }) => _Hypothesis(
    seedPenaltyDegM: seedPenaltyDegM,
    offEdgeDistanceM: offEdgeDistanceM ?? this.offEdgeDistanceM,
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
    previousOffsetM: previousOffsetM ?? this.previousOffsetM,
    stepParentHypothesisId: stepParentHypothesisId,
    stepTraversals: stepTraversals ?? this.stepTraversals,
    stepCrossedNodeIds: stepCrossedNodeIds,
  );
}

/// 경로 **끝에서** [lengthM]만큼 지운다. 첫 점은 항상 남긴다.
List<PdrLocalPoint> _dropLastLength(List<PdrLocalPoint> path, double lengthM) {
  if (lengthM <= 1e-9 || path.length < 2) return path;
  var remaining = lengthM;
  var index = path.length - 1;
  while (index >= 1) {
    final step = (path[index] - path[index - 1]).distance;
    if (step > remaining) break;
    remaining -= step;
    index -= 1;
  }
  if (index <= 0) return [path.first];
  final kept = path.sublist(0, index);
  if (remaining > 1e-6) {
    final step = (path[index] - path[index - 1]).distance;
    final t = step <= 1e-9 ? 0.0 : (step - remaining) / step;
    kept.add(
      PdrLocalPoint(
        path[index - 1].eastM + (path[index].eastM - path[index - 1].eastM) * t,
        path[index - 1].northM +
            (path[index].northM - path[index - 1].northM) * t,
      ),
    );
  }
  return kept;
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
    accepts: (nodeId) => isDirectionDecisionNode(edge, nodeId),
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

  bool isDirectionDecisionNode(_CorridorEdge current, String nodeId) {
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

  /// [fromEdge] 위 [progressM]에서 진행 방향으로 [maxDistanceM] 안에
  /// [targetEdgeId]에 닿을 수 있는지.
  ///
  /// optimistic cursor를 그대로 둘지 확정 쪽으로 되돌릴지 가르는 판정이다.
  /// "가까운 간선"이 아니라 **연결된 간선**만 본다 — 나란한 평행 복도는 거리가
  /// 아무리 가까워도 여기서 통과하지 못한다.
  bool isForwardReachable({
    required _CorridorEdge fromEdge,
    required int travelSign,
    required double progressM,
    required String targetEdgeId,
    required double maxDistanceM,
  }) {
    if (fromEdge.id == targetEdgeId) return true;
    final remainingM = travelSign > 0
        ? fromEdge.lengthM - progressM
        : progressM;
    if (remainingM > maxDistanceM) return false;
    final visited = <String>{fromEdge.id};
    final queue = <({String nodeId, double distanceM})>[
      (nodeId: fromEdge.nodeAtTravelEnd(travelSign), distanceM: remainingM),
    ];
    while (queue.isNotEmpty) {
      final head = queue.removeAt(0);
      for (final option in recoveryOptionsFromNode(head.nodeId)) {
        if (option.edge.id == targetEdgeId) return true;
        if (!visited.add(option.edge.id)) continue;
        final nextM = head.distanceM + option.edge.lengthM;
        if (nextM > maxDistanceM) continue;
        queue.add((
          nodeId: option.edge.nodeAtTravelEnd(option.travelSign),
          distanceM: nextM,
        ));
      }
    }
    return false;
  }

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

  /// [fromM]에서 [toM]까지 간선을 따라 촘촘히 샘플한 중간 점들(양 끝 제외).
  ///
  /// 회전 전환 구간에서 node로 옮겨 앉을 때, 그 사이를 직선 하나로 이으면
  /// 궤적이 3m 넘게 건너뛴 것처럼 보인다. 간선 형상을 따라 나눠 두면 실제
  /// 복도를 걸어간 모양으로 남는다.
  List<PdrLocalPoint> pointsBetween(
    double fromM,
    double toM, {
    double stepM = 0.8,
  }) {
    final spanM = (toM - fromM).abs();
    if (spanM <= stepM) return const [];
    final count = (spanM / stepM).ceil() - 1;
    final sign = toM >= fromM ? 1 : -1;
    return [
      for (var index = 1; index <= count; index += 1)
        pointAt(fromM + sign * spanM * index / (count + 1)),
    ];
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
