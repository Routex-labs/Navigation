import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/features/indoor_navigation/application/escalator_node_naming.dart';
import 'package:navigation_client/features/indoor_navigation/application/escalator_transition_detector.dart';
import 'package:navigation_client/features/indoor_navigation/contract/altitude_sample.dart';
import 'package:navigation_client/features/indoor_navigation/contract/raw_motion_activity.dart';
import 'package:navigation_client/models/floor_graph.dart';

/// 표준대기 고도 → 기압. [pressureAltitudeM]의 역함수라, 테스트는 "이 고도에
/// 있었다면 센서가 봤을 기압"을 만들어 넣는다.
double _pressureForAltitudeM(double altitudeM) =>
    1013.25 * math.pow(1.0 - altitudeM / 44330.0, 1 / 0.190295);

const _floors = ['6F', '5F', '4F', '3F', '2F', '1F', 'B1'];

GraphNode _escalator(String id, String? name, double x, double y) =>
    GraphNode(id: id, type: 'escalator', name: name, xM: x, yM: y);

/// 실측 데이터와 같은 배치: 한 랜딩에 상행 탑승/도착 노드가 1.5m 거리로 붙어
/// 있고, 하행 쌍은 조금 떨어져 있다.
FloorGraph _graphFor2F() => FloorGraph(
  nodes: [
    _escalator('n-up-to3f', 'ES1-UP(TO3F)', 0, 0),
    _escalator('n-up-fr1f', 'ES1-UP(FR1F)', 1.5, 0),
    _escalator('n-dn-to1f', 'ES1-DN(TO1F)', 3.0, 0),
    _escalator('n-dn-fr3f', 'ES1-DN(FR3F)', 4.5, 0),
    GraphNode(id: 'n-far', type: 'junction', name: null, xM: 60, yM: 60),
  ],
  edges: const [],
);

FloorGraph _graphFor3F() => FloorGraph(
  nodes: [
    _escalator('n3-up-to4f', 'ES1-UP(TO4F)', 0, 0),
    _escalator('n3-up-fr2f', 'ES1-UP(FR2F)', 1.5, 0),
  ],
  edges: const [],
);

class _Fixture {
  _Fixture({
    FloorGraph? graph,
    String floorLabel = '2F',
    List<String> floorLabels = _floors,
    EscalatorDetectorConfig config = const EscalatorDetectorConfig(),
  }) : detector = EscalatorTransitionDetector(config: config) {
    detector.updateContext(
      floorLabel: floorLabel,
      graph: graph ?? _graphFor2F(),
      floorLabels: floorLabels,
    );
  }

  final EscalatorTransitionDetector detector;
  int nowMs = 1000000;
  int steps = 40;
  final started = <EscalatorTransition>[];
  final cancelled = <EscalatorTransition>[];
  final confirmed = <EscalatorTransition>[];

  /// 에스컬레이터 탑승 노드 근처에 서 있다고 알린다.
  void standNearBoarding({double x = 0.5, double y = 0.5}) {
    detector.onPosition(
      positionM: PdrLocalPoint(x, y),
      steps: steps,
      timestampMs: nowMs,
    );
  }

  /// 에스컬레이터에서 멀리 떨어진 복도에 있다고 알린다.
  void standFarAway() {
    detector.onPosition(
      positionM: const PdrLocalPoint(60, 60),
      steps: steps,
      timestampMs: nowMs,
    );
  }

  /// 샘플 간격(ms). 기본값은 iOS `CMAltimeter` 실측 간격이다 — 정확히 1000ms로
  /// 테스트하면 평활 창 경계에 걸리는 버그를 놓친다(실제로 놓쳤다).
  int sampleIntervalMs = 1069;

  /// [seconds]초 동안 고도를 [fromM] → [toM]으로 선형 변화시킨다.
  void ramp({
    required double fromM,
    required double toM,
    required int seconds,
    int stepsPerSecond = 0,
    int rawPeaksPerSample = 0,
  }) {
    final sampleCount = (seconds * 1000 / sampleIntervalMs).round();
    for (var index = 1; index <= sampleCount; index++) {
      final altitude = fromM + (toM - fromM) * (index / sampleCount);
      nowMs += sampleIntervalMs;
      if (stepsPerSecond > 0) {
        // 걸으면 snapshot이 갱신되므로 실제 앱과 같이 위치·걸음도 함께 들어온다.
        steps += (stepsPerSecond * sampleIntervalMs / 1000).round();
        standNearBoarding();
      }
      if (rawPeaksPerSample > 0) {
        // 걸음 적용이 멈춘 동안에도 흐르는 원시 움직임. `steps`는 늘지 않는다.
        detector.onRawMotion(
          RawMotionActivity(
            timestampMs: nowMs,
            accelPeakDelta: rawPeaksPerSample,
          ),
        );
      }
      feed(altitude);
    }
  }

  void hold({required double atM, required int seconds}) =>
      ramp(fromM: atM, toM: atM, seconds: seconds);

  void feed(double altitudeM) {
    final transition = detector.onAltitude(
      AltitudeSample(
        timestampMs: nowMs,
        pressureHpa: _pressureForAltitudeM(altitudeM),
        source: 'test',
      ),
    );
    final startedTransition = detector.takeStartedTransition();
    if (startedTransition != null) started.add(startedTransition);
    final cancelledTransition = detector.takeCancelledTransition();
    if (cancelledTransition != null) cancelled.add(cancelledTransition);
    if (transition != null) confirmed.add(transition);
    phases.addAll(detector.takePhaseChanges());
  }

  final phases = <EscalatorPhaseChange>[];

  /// 활성 경로를 따라 탑승점으로 [steps]걸음 다가간다.
  void approachBoarding({
    required List<double> remainingM,
    PdrLocalPoint routeEnd = const PdrLocalPoint(0, 0),
    String boardingNodeId = 'n-up-to3f',
    String? arrivalNodeId = 'n3-up-fr2f',
  }) {
    for (final remaining in remainingM) {
      steps += 2;
      nowMs += 700;
      detector.onEscalatorRouteApproach(
        positionM: PdrLocalPoint(routeEnd.eastM + remaining, routeEnd.northM),
        routeEndM: routeEnd,
        expectedBoardingNodeId: boardingNodeId,
        expectedArrivalNodeId: arrivalNodeId,
        steps: steps,
        timestampMs: nowMs,
      );
      phases.addAll(detector.takePhaseChanges());
    }
  }

  List<EscalatorPhase> phasesOf() => phases.map((c) => c.phase).toList();

  List<String> rejectionReasons() => detector
      .takeEvents()
      .where((event) => event.kind == 'rejected')
      .map((event) => event.reason)
      .toList();
}

void main() {
  group('에스컬레이터 상행', () {
    test('탑승 노드 근처에서 한 층 올라가면 도착 층을 확정한다', () {
      final fixture = _Fixture();
      // baseline을 채우고 탑승 노드 근처에 선다.
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      // 에스컬레이터 상승: 20초에 4.5m. 그 사이 걸음은 늘지 않는다.
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      // 하차 후 평지.
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, hasLength(1));
      final transition = fixture.confirmed.single;
      expect(transition.direction, EscalatorDirection.up);
      expect(transition.fromFloorLabel, '2F');
      expect(transition.toFloorLabel, '3F');
      expect(transition.group, 'ES1');
      expect(transition.boardingNodeId, 'n-up-to3f');
      expect(transition.boardingEvidence, 'observed');
      expect(transition.stepsDuring, 0);
      expect(transition.deltaM, closeTo(4.5, 0.5));
    });

    test('상승 중에는 확정하지 않고 멈춘 뒤에 확정한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      // 아직 안정 창을 채우지 않았다 = 탑승 중.
      expect(fixture.confirmed, isEmpty);
      fixture.hold(atM: 4.5, seconds: 5);
      expect(fixture.confirmed, hasLength(1));
    });

    test('반 층을 지나면 하차 전에도 조기 층 전환 신호를 낸다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 3.2, seconds: 12);

      expect(fixture.started, hasLength(1));
      expect(fixture.started.single.fromFloorLabel, '2F');
      expect(fixture.started.single.toFloorLabel, '3F');
      expect(fixture.confirmed, isEmpty);
      expect(fixture.detector.pendingTransition, isNotNull);
    });

    test('하차 뒤 첫 걸음과 수직 속도 감소가 겹치면 다음 샘플에 확정한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      expect(fixture.started, hasLength(1));
      expect(fixture.confirmed, isEmpty);

      fixture.nowMs += fixture.sampleIntervalMs;
      fixture.steps++;
      fixture.standNearBoarding();
      fixture.feed(4.5);

      expect(
        fixture.confirmed,
        hasLength(1),
        reason: '하차 후 첫 걸음을 2.5초 settle 창 때문에 늦추면 안 된다',
      );
    });

    test('연속 두 층을 각각 확정한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);
      expect(fixture.confirmed, hasLength(1));

      // 확정 뒤 화면이 3F로 바뀌고 그 층 그래프가 들어온다.
      fixture.detector.updateContext(
        floorLabel: '3F',
        graph: _graphFor3F(),
        floorLabels: _floors,
      );
      fixture.hold(atM: 4.5, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 4.5, toM: 9.0, seconds: 20);
      fixture.hold(atM: 9.0, seconds: 5);

      expect(fixture.confirmed, hasLength(2));
      expect(fixture.confirmed.last.fromFloorLabel, '3F');
      expect(fixture.confirmed.last.toFloorLabel, '4F');
    });

    test('하차 직후에도 상대 고도는 0에서 다시 시작한다', () {
      // 연속 환승(내리자마자 다음 에스컬레이터)에서 중요한 두 가지를 함께 본다.
      // (1) 새 0점은 **하차 시점**에 잡힌다 — 이미 올라와 있는 것으로 읽지 않는다.
      // (2) 층이 바뀌었다고 기압 창까지 버리지 않는다 — 버리면 최소 샘플을 다시
      //     채울 때까지(iOS 약 3초) 판정이 아예 죽어 두 번째 층이 늦는다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 4);
      expect(fixture.confirmed, hasLength(1));

      fixture.detector.updateContext(
        floorLabel: '3F',
        graph: _graphFor3F(),
        floorLabels: _floors,
      );

      expect(
        fixture.detector.smoothedAltitudeM,
        isNotNull,
        reason: '평활값이 null이면 다시 채울 때까지 판정이 죽는다',
      );
      final delta = fixture.detector.deltaM;
      expect(delta, isNotNull);
      expect(
        delta!.abs(),
        lessThan(0.6),
        reason: '4.5m를 올라왔어도 새 층에서의 상대 고도는 0 근처여야 한다',
      );
    });
  });

  group('센서 주기 (실측 회귀)', () {
    test('iOS 1069ms 간격에서도 평활값이 나오고 확정된다', () {
      // 실측 로그(2026-07-30, iPhone 13 Pro)에서 CMAltimeter 간격은 1069ms였다.
      // 평활 창이 2000ms일 때는 창 안에 항상 2개만 들어와 최소 샘플 수를
      // 영원히 못 채웠고, 판정기가 한 번도 돌지 않았다(smoothed_m 전 구간 null).
      final fixture = _Fixture()..sampleIntervalMs = 1069;
      fixture.hold(atM: 0, seconds: 6);
      expect(
        fixture.detector.smoothedAltitudeM,
        isNotNull,
        reason: '평활값이 null이면 이후 모든 판정이 죽는다',
      );
      expect(fixture.detector.baselineM, isNotNull);

      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 6.2, seconds: 24);
      fixture.hold(atM: 6.2, seconds: 8);
      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.toFloorLabel, '3F');
    });

    test('실측 한 층 상승폭(6.2m)은 다층으로 거부하지 않는다', () {
      // 더현대 B2→B1 실측값. 거부선이 8.0m였다면 정상 이동이 잘려 나갔다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 6);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 6.2, seconds: 24);
      fixture.hold(atM: 6.2, seconds: 8);
      expect(fixture.confirmed, hasLength(1));
      expect(
        fixture.rejectionReasons(),
        isNot(contains('multiFloorUnsupported')),
      );
    });

    test('시계열이 끊긴 뒤에는 옛 고도를 섞지 않고 창을 다시 채운다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 6);
      fixture.standNearBoarding();
      // 앱이 background에 다녀와 30초 공백이 생겼고, 그 사이 고도가 바뀌었다.
      fixture.nowMs += 30000;
      fixture.feed(6.2);
      expect(
        fixture.detector.smoothedAltitudeM,
        isNull,
        reason: '공백 직후 첫 샘플로 판정하면 30초 전 고도가 중앙값에 섞인다',
      );
      expect(fixture.confirmed, isEmpty);
    });
  });

  group('에스컬레이터에서 걷는 경우', () {
    test('걸음이 늘어도 확정하고, 걸음 수를 근거로 남긴다', () {
      // 걸음은 확정 조건이 아니다(가점도 감점도 아님). 계단과 구분하기 위한
      // 사후 분석용으로만 기록한다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 6);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 5.0, seconds: 16, stepsPerSecond: 2);
      fixture.hold(atM: 5.0, seconds: 8);

      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.toFloorLabel, '3F');
      // 후보가 열린 시점부터 센 값이라 전체 걸음보다 작다.
      expect(fixture.confirmed.single.stepsDuring, greaterThan(5));
    });
  });

  group('원시 움직임과 하차 재개', () {
    test('걸음 적용이 멈춰 있어도 원시 움직임으로 하차를 빠르게 확정한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      // 탑승 중: 걸음 적용은 pause라 steps가 늘지 않는다.
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      final beforeSteps = fixture.steps;
      // 하차: 수직 속도가 잦아드는 첫 샘플에 원시 걸음이 함께 들어온다.
      fixture.ramp(fromM: 4.5, toM: 4.5, seconds: 3, rawPeaksPerSample: 2);

      expect(fixture.steps, beforeSteps, reason: '적용 걸음은 여전히 멈춰 있어야 한다');
      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.toFloorLabel, '3F');
    });

    test('수직 이동 중 진동 peak로는 재개하지 않는다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      // 에스컬레이터 진동이 계속 peak로 잡히지만 수직 속도는 크다.
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20, rawPeaksPerSample: 3);

      expect(
        fixture.confirmed,
        isEmpty,
        reason: '진동 peak가 아무리 많아도 오르내리는 중에는 확정하지 않는다',
      );
    });

    test('원시 움직임이 없으면 연속 저속 샘플로 확정한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, hasLength(1));
    });
  });

  group('에스컬레이터 하행', () {
    test('내려가면 하행 탑승 노드의 목표 층으로 확정한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      // 하행 탑승 노드(3.0, 0) 근처.
      fixture.standNearBoarding(x: 3.0, y: 0.5);
      fixture.ramp(fromM: 0, toM: -4.5, seconds: 20);
      fixture.hold(atM: -4.5, seconds: 5);

      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.direction, EscalatorDirection.down);
      expect(fixture.confirmed.single.toFloorLabel, '1F');
      expect(fixture.confirmed.single.boardingEvidence, 'observed');
      expect(fixture.confirmed.single.boardingNodeId, 'n-dn-to1f');
    });

    test('활성 경로가 하행 탑승점을 가리키면 12m 위치 오차에서도 확정한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.detector.onEscalatorRouteApproach(
        // 실측 로그처럼 보정 위치는 탑승점보다 늦게 따라온다.
        positionM: const PdrLocalPoint(15, 0),
        routeEndM: const PdrLocalPoint(3, 0),
        expectedBoardingNodeId: 'n-dn-to1f',
        expectedArrivalNodeId: 'n1-dn-fr2f',
        steps: fixture.steps,
        timestampMs: fixture.nowMs,
      );
      fixture.ramp(fromM: 0, toM: -5.5, seconds: 24);
      fixture.hold(atM: -5.5, seconds: 6);

      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.direction, EscalatorDirection.down);
      expect(fixture.confirmed.single.toFloorLabel, '1F');
      expect(fixture.confirmed.single.boardingEvidence, 'routeExpected');
      expect(fixture.confirmed.single.expectedArrivalNodeId, 'n1-dn-fr2f');
    });

    test('허가가 늦게 걸려도 그 전 하강분을 baseline이 먹지 않는다', () {
      // 보정 위치가 탑승 노드에 늦게 수렴하는 경우(하행 랜딩 실측). 허가 전에
      // 이미 내려간 만큼이 baseline에 흡수되면, 허가 시점의 Δ가 0에 가까워져
      // 사용자는 이미 반쯤 내려왔는데 판정은 처음부터 다시 시작한다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standFarAway();
      fixture.ramp(fromM: 0, toM: -2.0, seconds: 8);

      final deltaBeforeArming = fixture.detector.deltaM;
      expect(deltaBeforeArming, isNotNull);
      expect(
        deltaBeforeArming!.abs(),
        greaterThan(1.5),
        reason: '움직이는 중에는 baseline이 하강분을 따라가지 않아야 한다',
      );
    });
  });

  group('단계 분리', () {
    test('탑승점 접근만으로 배너 단계에 올라가고 층은 그대로다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.approachBoarding(remainingM: const [12, 8, 4, 2]);

      expect(fixture.phasesOf(), contains(EscalatorPhase.boardingDetected));
      final boarding = fixture.phases.firstWhere(
        (change) => change.phase == EscalatorPhase.boardingDetected,
      );
      expect(boarding.fromFloorLabel, '2F');
      expect(boarding.toFloorLabel, '3F');
      expect(boarding.boardingNodeId, 'n-up-to3f');
      expect(boarding.expectedArrivalNodeId, 'n3-up-fr2f');
      expect(fixture.started, isEmpty, reason: '층 전환은 아직 시작하지 않는다');
      expect(fixture.confirmed, isEmpty);
    });

    test('한 프레임 근접만으로는 배너를 띄우지 않는다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.approachBoarding(remainingM: const [2]);

      expect(fixture.phasesOf(), isNot(contains(EscalatorPhase.boardingDetected)));
    });

    test('탑승점에서 다시 멀어지면 배너 단계를 되돌린다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.approachBoarding(remainingM: const [12, 8, 4, 2]);
      fixture.approachBoarding(remainingM: const [6, 10]);

      expect(fixture.phasesOf(), contains(EscalatorPhase.cancelled));
    });

    test('걸음 pause는 지도 전환 문턱 이전 수직 속도에서 시작한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.approachBoarding(remainingM: const [12, 8, 4, 2]);
      // 지도 전환 문턱(minDeltaM)에 한참 못 미치는 0.8m만 오른다.
      fixture.ramp(fromM: 0, toM: 0.8, seconds: 5);

      expect(
        fixture.phasesOf(),
        contains(EscalatorPhase.verticalMotionDetected),
      );
      expect(
        fixture.phasesOf(),
        isNot(contains(EscalatorPhase.midpointReached)),
        reason: '목적 층 지도는 midpoint 근거 전에는 열지 않는다',
      );
    });

    test('지도 전환은 반 층(2m)에 닿기 전에 열린다', () {
      // 실측 층고 4.5m를 20초에 오르는 에스컬레이터(0.22 m/s). 예전 문턱
      // (1.8m)에서는 지도가 8초쯤 뒤에 바뀌어, 사용자는 이미 탑승한 뒤로도
      // 한참 이전 층 도면을 봤다. 이 테스트는 "얼마나 일찍 열리는가"를 고정한다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);

      final midpoint = fixture.phases
          .where((change) => change.phase == EscalatorPhase.midpointReached)
          .firstOrNull;
      expect(midpoint, isNotNull, reason: '탑승 중에 지도가 넘어가야 한다');
      expect(
        midpoint!.deltaM.abs(),
        lessThan(2.0),
        reason: '반 층을 다 오르기 전에 지도가 넘어가야 "탔는데 아직 이전 층"이 사라진다',
      );
    });

    test('층 지도 전환과 하차 재개는 서로 다른 시점이다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      final midpointIndex = fixture
          .phasesOf()
          .indexOf(EscalatorPhase.midpointReached);
      expect(midpointIndex, greaterThanOrEqualTo(0));
      expect(fixture.phasesOf(), isNot(contains(EscalatorPhase.landed)));

      fixture.hold(atM: 4.5, seconds: 5);
      final landedIndex = fixture.phasesOf().indexOf(EscalatorPhase.landed);
      expect(landedIndex, greaterThan(midpointIndex));
    });

    test('접근만 하고 지나가면 제한 시간 뒤 단계를 되돌린다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.approachBoarding(remainingM: const [12, 8, 4, 2]);
      expect(fixture.phasesOf(), contains(EscalatorPhase.boardingDetected));

      // 고도 변화 없이 제한 시간을 넘긴다.
      fixture.hold(atM: 0, seconds: 50);

      expect(fixture.phasesOf(), contains(EscalatorPhase.cancelled));
    });
  });

  group('오탐 방어', () {
    test('가까운 도착 노드가 같은 그룹의 먼 탑승 노드를 대신 허가하지 않는다', () {
      final fixture = _Fixture(
        graph: FloorGraph(
          nodes: [
            _escalator('arrival', 'ES2-UP(FR1F)', 0, 0),
            _escalator('far-boarding', 'ES2-UP(TO3F)', 15, 0),
          ],
          edges: const [],
        ),
      );
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding(x: 0, y: 0);
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, isEmpty);
      expect(fixture.detector.isArmed, isFalse);
    });

    test('붙어 있는 같은 방향 두 레인은 경로가 없으면 가장 가까운 것을 쓴다', () {
      final fixture = _Fixture(
        graph: FloorGraph(
          nodes: [
            _escalator('lane-a', 'ES2-UP(TO3F)', 0, 0),
            _escalator('lane-b', 'ES2-1-UP(TO3F)', 1, 0),
          ],
          edges: const [],
        ),
      );
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding(x: 0.5, y: 0);
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.boardingNodeId, 'lane-a');
    });

    test('붙어 있는 레인에서는 활성 경로가 고른 정확한 탑승 노드를 우선한다', () {
      final fixture = _Fixture(
        graph: FloorGraph(
          nodes: [
            _escalator('lane-a', 'ES2-UP(TO3F)', 0, 0),
            _escalator('lane-b', 'ES2-1-UP(TO3F)', 1, 0),
          ],
          edges: const [],
        ),
      );
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding(x: 0.5, y: 0);
      fixture.detector.onEscalatorRouteApproach(
        positionM: const PdrLocalPoint(0.5, 0),
        routeEndM: const PdrLocalPoint(1, 0),
        expectedBoardingNodeId: 'lane-b',
        expectedArrivalNodeId: 'lane-b-arrival',
        steps: fixture.steps,
        timestampMs: fixture.nowMs,
      );
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.boardingNodeId, 'lane-b');
      expect(fixture.confirmed.single.expectedArrivalNodeId, 'lane-b-arrival');
      expect(fixture.confirmed.single.boardingEvidence, 'routeAndObserved');
    });

    test('에스컬레이터에서 멀면 같은 상승에도 층을 바꾸지 않는다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standFarAway();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 10);

      expect(fixture.confirmed, isEmpty);
    });

    test('활성 경로가 있어도 16m 밖이면 기압 변화만으로 허가하지 않는다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.detector.onEscalatorRouteApproach(
        positionM: const PdrLocalPoint(25, 0),
        routeEndM: const PdrLocalPoint(3, 0),
        expectedBoardingNodeId: 'n-dn-to1f',
        steps: fixture.steps,
        timestampMs: fixture.nowMs,
      );
      fixture.ramp(fromM: 0, toM: -5.5, seconds: 24);
      fixture.hold(atM: -5.5, seconds: 6);

      expect(fixture.confirmed, isEmpty);
    });

    test('층 안에 서서 기상 드리프트만 있으면 확정하지 않는다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      // 노드 근처에 계속 서 있어도(허가 상태) 5분에 걸친 3m 드리프트는
      // 에스컬레이터가 아니다 — baseline 추적과 안정 조건이 함께 막는다.
      for (var second = 0; second < 300; second++) {
        fixture.standNearBoarding();
        fixture.nowMs += 1000;
        fixture.feed(3.0 * second / 300);
      }
      expect(fixture.confirmed, isEmpty);
    });

    test('올라갔다 바로 돌아오면 reverted로 거부한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      // 후보가 열릴 만큼(누적 2.5m 이상) 올라갔다가 되돌아온다.
      fixture.ramp(fromM: 0, toM: 3.5, seconds: 7);
      fixture.ramp(fromM: 3.5, toM: 0, seconds: 7);
      fixture.hold(atM: 0, seconds: 5);

      expect(fixture.confirmed, isEmpty);
      expect(fixture.rejectionReasons(), contains('reverted'));
      expect(fixture.cancelled, hasLength(1));
      expect(fixture.cancelled.single.toFloorLabel, '3F');
    });

    test('여러 층 이동은 층고를 추측하지 않고 거부한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      // 엘리베이터로 2층 이상 이동한 경우.
      fixture.ramp(fromM: 0, toM: 10.0, seconds: 20);
      fixture.hold(atM: 10.0, seconds: 5);

      expect(fixture.confirmed, isEmpty);
      expect(fixture.rejectionReasons(), contains('multiFloorUnsupported'));
    });

    test('기압 방향과 반대인 에스컬레이터만 근처에 있으면 거부한다', () {
      // 하행 노드만 있는 층에서 고도가 올라갔다 = 에스컬레이터로 설명되지 않는다.
      final fixture = _Fixture(
        graph: FloorGraph(
          nodes: [
            _escalator('n-dn-to1f', 'ES1-DN(TO1F)', 0, 0),
            _escalator('n-dn-fr3f', 'ES1-DN(FR3F)', 1.5, 0),
          ],
          edges: const [],
        ),
      );
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, isEmpty);
      expect(fixture.rejectionReasons(), contains('noBoardingNode'));
    });

    test('이름 규칙이 없는 데이터에서는 판정 자체가 돌지 않는다', () {
      final fixture = _Fixture(
        graph: FloorGraph(
          nodes: [
            _escalator('n-a', '에스컬레이터', 0, 0),
            _escalator('n-b', null, 1.5, 0),
          ],
          edges: const [],
        ),
      );
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, isEmpty);
      expect(fixture.detector.isArmed, isFalse);
    });

    test('이름이 가리키는 층이 건물 층 목록에 없으면 거부한다', () {
      final fixture = _Fixture(floorLabels: const ['1F', '2F']);
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, isEmpty);
      expect(fixture.rejectionReasons(), contains('unknownTargetFloor'));
    });

    test('층을 수동으로 바꾸면 baseline과 허가를 버린다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 2.0, seconds: 4);
      // 사용자가 층 선택기로 다른 층을 훑어본다.
      fixture.detector.updateContext(
        floorLabel: '5F',
        graph: _graphFor3F(),
        floorLabels: _floors,
      );
      expect(fixture.detector.isArmed, isFalse);
      expect(fixture.detector.baselineM, isNull);
      // 이어지는 상승은 새 baseline 기준이라 직전 2m를 이어받지 않는다.
      fixture.hold(atM: 2.0, seconds: 5);
      expect(fixture.confirmed, isEmpty);
    });
  });
}
