import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/application/escalator_arrival.dart';
import 'package:navigation_client/features/indoor_navigation/application/escalator_node_naming.dart';
import 'package:navigation_client/features/indoor_navigation/application/escalator_transition_detector.dart';
import 'package:navigation_client/features/indoor_navigation/contract/floor_transition_ui_state.dart';
import 'package:navigation_client/models/building/floor_graph.dart';

GraphNode _escalator(String id, String? name, double x, double y) =>
    GraphNode(id: id, type: 'escalator', name: name, xM: x, yM: y);

EscalatorTransition _transition({
  String group = 'ES1',
  EscalatorDirection direction = EscalatorDirection.up,
  String from = '2F',
  String to = '3F',
  String? expectedArrivalNodeId,
}) => EscalatorTransition(
  group: group,
  direction: direction,
  fromFloorLabel: from,
  toFloorLabel: to,
  deltaM: 4.5,
  durationMs: 20000,
  stepsDuring: 0,
  boardingNodeId: 'n-boarding',
  boardingNodeName: 'ES1-UP(TO3F)',
  boardingDistanceM: 1.2,
  boardingEvidence: 'observed',
  expectedArrivalNodeId: expectedArrivalNodeId,
);

EscalatorPhaseChange _stage({
  required EscalatorPhase phase,
  String from = '2F',
  String? to = '3F',
  EscalatorDirection? direction = EscalatorDirection.up,
}) => EscalatorPhaseChange(
  phase: phase,
  atMs: 1000,
  fromFloorLabel: from,
  reason: 'test',
  toFloorLabel: to,
  direction: direction,
);

void main() {
  group('findEscalatorArrivalNode — 도착 노드 찾기', () {
    // 실측 배치: 한 랜딩에 상행 도착/출발 노드가 1.5m 거리로 붙어 있다.
    final graph = FloorGraph(
      nodes: [
        _escalator('n3-up-fr2f', 'ES1-UP(FR2F)', 0, 0),
        _escalator('n3-up-to4f', 'ES1-UP(TO4F)', 1.5, 0),
        _escalator('n3-dn-fr4f', 'ES1-DN(FR4F)', 3.0, 0),
        const GraphNode(id: 'n-hall', type: 'corridor', xM: 20, yM: 20),
      ],
      edges: const [],
    );

    test('길찾기가 지목한 노드를 최우선으로 쓴다', () {
      // 붙어 있는 레인 중 어느 것을 탔는지는 센서로 못 가른다. 경로만 안다.
      final node = findEscalatorArrivalNode(
        graph,
        _transition(expectedArrivalNodeId: 'n3-up-to4f'),
      );

      expect(node?.id, 'n3-up-to4f');
    });

    test('지목된 노드가 에스컬레이터가 아니면 무시하고 이름으로 찾는다', () {
      final node = findEscalatorArrivalNode(
        graph,
        _transition(expectedArrivalNodeId: 'n-hall'),
      );

      expect(node?.id, 'n3-up-fr2f', reason: '2F에서 올라온 도착 노드');
    });

    test('지목이 없으면 출발 층까지 맞는 도착 노드를 쓴다', () {
      final node = findEscalatorArrivalNode(graph, _transition(from: '2F'));

      expect(node?.id, 'n3-up-fr2f');
    });

    test('이름 규칙이 안 맞으면 같은 뱅크·같은 방향으로 물러선다', () {
      // 이름이 깨진 데이터에서도 같은 에스컬레이터 근처에는 세운다. 정확하진
      // 않아도 반대편 건물에 떨어뜨리는 것보다 낫다.
      final brokenGraph = FloorGraph(
        nodes: [
          _escalator('n3-up-x', 'ES1-UP(TO4F)', 5, 5),
          const GraphNode(id: 'n-hall', type: 'corridor', xM: 20, yM: 20),
        ],
        edges: const [],
      );

      final node = findEscalatorArrivalNode(brokenGraph, _transition());

      expect(node?.id, 'n3-up-x');
    });

    test('같은 뱅크가 아예 없으면 null', () {
      final otherBank = FloorGraph(
        nodes: [_escalator('n-es2', 'ES2-UP(FR2F)', 0, 0)],
        edges: const [],
      );

      expect(findEscalatorArrivalNode(otherBank, _transition()), isNull);
    });

    test('그래프가 아직 없으면 null', () {
      expect(findEscalatorArrivalNode(null, _transition()), isNull);
    });

    test('하행 이동은 하행 노드를 고른다', () {
      final node = findEscalatorArrivalNode(
        graph,
        _transition(direction: EscalatorDirection.down, from: '4F', to: '3F'),
      );

      expect(node?.id, 'n3-dn-fr4f');
    });
  });

  group('floorTransitionUiState — 배너 단계', () {
    test('타는 중이면 단계 값이 있어도 swapping이다', () {
      // 뒤집으면 도면을 갈아 끼우는 동안 "접근 중"이 떠 있다.
      final state = floorTransitionUiState(
        ride: _transition(),
        stage: _stage(phase: EscalatorPhase.boardingDetected),
      );

      expect(state?.stage, FloorTransitionStage.swapping);
    });

    test('수직 이동이 관측되면 moving, 접근만이면 boarding', () {
      expect(
        floorTransitionUiState(
          ride: null,
          stage: _stage(phase: EscalatorPhase.verticalMotionDetected),
        )?.stage,
        FloorTransitionStage.moving,
      );
      expect(
        floorTransitionUiState(
          ride: null,
          stage: _stage(phase: EscalatorPhase.boardingDetected),
        )?.stage,
        FloorTransitionStage.boarding,
      );
    });

    test('도착 층을 모르면 배너를 띄우지 않는다', () {
      // `{출발}→{도착}`이 문구의 뼈대라, 한쪽이 없으면 쓸 문장이 없다.
      final state = floorTransitionUiState(
        ride: null,
        stage: _stage(phase: EscalatorPhase.boardingDetected, to: null),
      );

      expect(state, isNull);
    });

    test('아무 단계도 없으면 null', () {
      // 하차가 확정되면 ride·stage가 함께 비고, 그 순간 배너도 사라진다 —
      // "N층으로 이동했습니다"를 몇 초 더 띄우는 완료 단계는 없다.
      expect(floorTransitionUiState(ride: null, stage: null), isNull);
    });

    test('상행·하행이 배너 화살표 방향으로 이어진다', () {
      expect(
        floorTransitionUiState(
          ride: _transition(direction: EscalatorDirection.up),
          stage: null,
        )?.goingUp,
        isTrue,
      );
      expect(
        floorTransitionUiState(
          ride: _transition(direction: EscalatorDirection.down),
          stage: null,
        )?.goingUp,
        isFalse,
      );
    });
  });

  group('FloorTransitionUiState — 배너 문구', () {
    FloorTransitionUiState state(FloorTransitionStage stage) =>
        FloorTransitionUiState(
          stage: stage,
          fromFloorLabel: 'B2',
          toFloorLabel: 'B1',
          goingUp: true,
        );

    test('큰 줄은 가는 곳, 작은 줄은 지금 일어나는 일이다', () {
      expect(state(FloorTransitionStage.moving).headline, 'B2 → B1');
      expect(state(FloorTransitionStage.moving).detail, '에스컬레이터로 이동 중');
    });

    test('도면을 갈아 끼우는 동안도 "에스컬레이터로 이동 중"이다', () {
      // 지도가 전환된다는 것은 앱의 사정이다. 그 사람에게 일어나는 일은
      // 층 이동 하나뿐이라, 두 단계가 다른 말을 하면 안 된다.
      expect(
        state(FloorTransitionStage.swapping).detail,
        state(FloorTransitionStage.moving).detail,
      );
    });

    test('탑승 전에는 감지 사실을 말한다', () {
      expect(state(FloorTransitionStage.boarding).detail, '에스컬레이터 탑승을 감지했습니다');
    });
  });
}
