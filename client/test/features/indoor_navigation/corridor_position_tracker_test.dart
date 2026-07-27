import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/features/indoor_navigation/application/corridor_position_tracker.dart';
import 'package:navigation_client/features/indoor_navigation/contract/pdr_anchor.dart';
import 'package:navigation_client/models/floor_graph.dart';

const _crossGraph = FloorGraph(
  nodes: [
    GraphNode(id: 'a', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'b', type: 'junction', xM: 10, yM: 0),
    GraphNode(id: 'c', type: 'corridor', xM: 10, yM: 10),
    GraphNode(id: 'd', type: 'corridor', xM: 20, yM: 0),
    GraphNode(id: 'e', type: 'junction', xM: 20, yM: 3),
    GraphNode(id: 'f', type: 'corridor', xM: 0, yM: 3),
  ],
  edges: [
    GraphEdge(
      id: 'ab',
      fromNodeId: 'a',
      toNodeId: 'b',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(10, 0)],
    ),
    GraphEdge(
      id: 'bd',
      fromNodeId: 'b',
      toNodeId: 'd',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(10, 0), LocalPoint(20, 0)],
    ),
    GraphEdge(
      id: 'bc',
      fromNodeId: 'b',
      toNodeId: 'c',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(10, 0), LocalPoint(10, 10)],
    ),
    GraphEdge(
      id: 'de',
      fromNodeId: 'd',
      toNodeId: 'e',
      lengthM: 3,
      bidirectional: true,
      geometryLocalM: [LocalPoint(20, 0), LocalPoint(20, 3)],
    ),
    GraphEdge(
      id: 'ef',
      fromNodeId: 'e',
      toNodeId: 'f',
      lengthM: 20,
      bidirectional: true,
      geometryLocalM: [LocalPoint(20, 3), LocalPoint(0, 3)],
    ),
  ],
);

const _longStraightGraph = FloorGraph(
  nodes: [
    GraphNode(id: 'start', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'end', type: 'corridor', xM: 50, yM: 0),
  ],
  edges: [
    GraphEdge(
      id: 'straight',
      fromNodeId: 'start',
      toNodeId: 'end',
      lengthM: 50,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(50, 0)],
    ),
  ],
);

CorridorObservation _observation({
  required int atMs,
  required int confirmedSteps,
  required double confirmedDistanceM,
  required int previewSteps,
  required double headingDeg,
  PdrLocalPoint raw = PdrLocalPoint.zero,
  List<PdrLocalPoint> rawConfirmedStepPositions = const [],
}) => CorridorObservation(
  timestampMs: atMs,
  rawConfirmedPosition: raw,
  confirmedSteps: confirmedSteps,
  confirmedDistanceM: confirmedDistanceM,
  rawPreviewPosition: raw,
  previewSteps: previewSteps,
  sensorHeadingDeg: headingDeg,
  hasHeading: true,
  rawConfirmedStepPositions: rawConfirmedStepPositions,
);

void main() {
  test('도면 y축이 반전되면 위치와 동일하게 heading도 반전한다', () {
    const anchor = PdrAnchor(
      floorId: '1F',
      anchorLocalM: PdrLocalPoint.zero,
      rotationDeg: 0,
      headingReference: HeadingReference.magneticNorth,
      requiresManualRotationCalibration: false,
      source: AnchorSource.userPin,
      confidence: 1,
      axes: PdrToFloorAxes(eastToX: 1, northToX: 0, eastToY: 0, northToY: -1),
    );
    final transform = FloorCoordinateTransform(anchor);

    expect(transform.toFloorBearing(0), closeTo(180, 1e-9));
    expect(transform.toFloorBearing(90), closeTo(90, 1e-9));
    expect(transform.floorBearingToMapBearing(180), closeTo(0, 1e-9));
  });

  group('CorridorPositionTracker', () {
    test('직선에서는 위치를 간선에 고정하고 heading bias를 복도 방향으로 수렴시킨다', () {
      final tracker = CorridorPositionTracker(_longStraightGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(1, 0),
          initialHeadingDeg: 80,
          timestampMs: 0,
        );

      for (var step = 1; step <= 10; step += 1) {
        tracker.update(
          _observation(
            atMs: step * 500,
            confirmedSteps: step,
            confirmedDistanceM: step * 0.7,
            previewSteps: step,
            headingDeg: 80,
            raw: PdrLocalPoint(1 + step * 0.7, step * 0.7 * 0.173648),
          ),
        );
      }

      final result = tracker.result;
      expect(result.currentEdgeId, 'straight');
      expect(result.state, CorridorTrackingState.straightTracking);
      expect(result.headingBiasDeg, greaterThan(0));
      expect(result.correctedHeadingDeg, closeTo(90, 1e-9));
      expect(result.correctedPosition.northM, closeTo(0, 1e-9));
      expect(
        result.correctedPath.every((point) => point.northM.abs() < 1e-9),
        isTrue,
      );
    });

    test('원본이 평행 복도에 가까워져도 연결 노드 도달 전에는 전환하지 않는다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(2, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      for (var step = 1; step <= 8; step += 1) {
        tracker.update(
          _observation(
            atMs: step * 500,
            confirmedSteps: step,
            confirmedDistanceM: step * 0.7,
            previewSteps: step,
            headingDeg: 90,
            raw: PdrLocalPoint(2 + step * 0.7, 2.8),
          ),
        );
      }

      expect(tracker.result.currentEdgeId, 'ab');
      expect(tracker.result.correctedPosition.northM.abs(), lessThan(0.1));
    });

    test('초록 배치는 복원된 걸음별 방향으로 간선 진행 방향을 정한다', () {
      final tracker = CorridorPositionTracker(_longStraightGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(1, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      final result = tracker.update(
        CorridorObservation(
          timestampMs: 1000,
          rawConfirmedPosition: const PdrLocalPoint(2.4, 0),
          confirmedSteps: 2,
          confirmedDistanceM: 1.4,
          rawPreviewPosition: const PdrLocalPoint(2.4, 0),
          previewSteps: 2,
          // 배치가 늦게 도착한 시점에는 폰이 이미 동쪽을 향한 상황.
          sensorHeadingDeg: 90,
          hasHeading: true,
          rawConfirmedStepPositions: const [
            PdrLocalPoint(1.7, 0),
            PdrLocalPoint(2.4, 0),
          ],
        ),
      );

      expect(result.correctedPosition.eastM, closeTo(2.4, 1e-9));
      expect(result.correctedPosition.northM, closeTo(0, 1e-9));
    });

    test('직진 연결 간선은 체크포인트 전이 없이 같은 복도처럼 이어간다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(8.5, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      final result = tracker.update(
        _observation(
          atMs: 1800,
          confirmedSteps: 3,
          confirmedDistanceM: 2.1,
          previewSteps: 0,
          headingDeg: 90,
        ),
      );

      expect(result.state, CorridorTrackingState.straightTracking);
      expect(result.currentEdgeId, 'bd');
      expect(result.lastConfirmedNodeId, isNull);
      expect(result.correctedPath, contains(const PdrLocalPoint(10, 0)));
      expect(result.correctedPosition.eastM, closeTo(10.6, 1e-9));
      expect(result.correctedPosition.northM, closeTo(0, 1e-9));
    });

    test('노드 근처 주황 회전을 관찰하고 초록 진행거리로 새 간선을 확정한다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(7, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      tracker.update(
        _observation(
          atMs: 1000,
          confirmedSteps: 2,
          confirmedDistanceM: 1.4,
          previewSteps: 2,
          headingDeg: 90,
        ),
      );
      tracker.update(
        _observation(
          atMs: 1200,
          confirmedSteps: 2,
          confirmedDistanceM: 1.4,
          previewSteps: 3,
          headingDeg: 2,
        ),
      );
      final pending = tracker.update(
        _observation(
          atMs: 1800,
          confirmedSteps: 2,
          confirmedDistanceM: 1.4,
          previewSteps: 4,
          headingDeg: 2,
        ),
      );
      expect(pending.state, CorridorTrackingState.turnPending);
      expect(pending.pendingEdgeId, 'bc');

      final beforeConfirmation = tracker.update(
        _observation(
          atMs: 2600,
          confirmedSteps: 5,
          confirmedDistanceM: 3.5,
          previewSteps: 6,
          headingDeg: 1,
        ),
      );
      expect(beforeConfirmation.currentEdgeId, 'ab');
      expect(beforeConfirmation.correctedPosition.eastM, lessThanOrEqualTo(10));
      expect(beforeConfirmation.correctedPosition.northM, closeTo(0, 1e-9));
      final confirmed = tracker.update(
        _observation(
          atMs: 3300,
          confirmedSteps: 8,
          confirmedDistanceM: 5.6,
          previewSteps: 8,
          headingDeg: 0,
        ),
      );

      expect(
        confirmed.state,
        anyOf(
          CorridorTrackingState.nodeConfirmed,
          CorridorTrackingState.straightTracking,
        ),
      );
      expect(confirmed.currentEdgeId, 'bc');
      expect(confirmed.correctedPath, contains(const PdrLocalPoint(10, 0)));
      expect(confirmed.correctedPosition.northM, greaterThanOrEqualTo(1.5));
    });

    test('교차로에서 먼 곳에서 휴대폰만 돌리면 회전 후보로 진입하지 않는다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(2, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      final result = tracker.update(
        _observation(
          atMs: 800,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 1,
          headingDeg: 0,
        ),
      );

      expect(result.state, CorridorTrackingState.straightTracking);
      expect(result.currentEdgeId, 'ab');
    });

    test('회전 후보가 제한시간 동안 일관되지 않으면 점프 없이 uncertain이 된다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(8.5, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      tracker.update(
        _observation(
          atMs: 100,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 1,
          headingDeg: 0,
        ),
      );
      tracker.update(
        _observation(
          atMs: 700,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 2,
          headingDeg: 0,
        ),
      );
      final uncertain = tracker.update(
        _observation(
          atMs: 4800,
          confirmedSteps: 4,
          confirmedDistanceM: 2.8,
          previewSteps: 6,
          headingDeg: 180,
        ),
      );

      expect(uncertain.state, CorridorTrackingState.uncertain);
      expect(uncertain.currentEdgeId, 'ab');
      expect(uncertain.correctedPosition.northM, closeTo(0, 1e-9));
      expect(
        uncertain.correctedPath,
        isNot(contains(const PdrLocalPoint(10, 10))),
      );
    });

    test('uncertain 뒤 원래 직진 방향이 돌아오면 연결된 직진 간선을 재획득한다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(8.5, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      tracker.update(
        _observation(
          atMs: 100,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 1,
          headingDeg: 0,
        ),
      );
      tracker.update(
        _observation(
          atMs: 700,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 2,
          headingDeg: 0,
        ),
      );
      tracker.update(
        _observation(
          atMs: 4800,
          confirmedSteps: 4,
          confirmedDistanceM: 2.8,
          previewSteps: 6,
          headingDeg: 180,
        ),
      );

      tracker.update(
        _observation(
          atMs: 5000,
          confirmedSteps: 4,
          confirmedDistanceM: 2.8,
          previewSteps: 7,
          headingDeg: 90,
        ),
      );
      final recovered = tracker.update(
        _observation(
          atMs: 7000,
          confirmedSteps: 7,
          confirmedDistanceM: 4.9,
          previewSteps: 10,
          headingDeg: 90,
        ),
      );

      expect(
        recovered.state,
        anyOf(
          CorridorTrackingState.nodeConfirmed,
          CorridorTrackingState.straightTracking,
        ),
      );
      expect(recovered.currentEdgeId, 'bd');
      expect(recovered.correctedPosition.eastM, greaterThanOrEqualTo(11.5));
      expect(recovered.correctedPosition.northM, closeTo(0, 1e-9));
    });

    test('간선 끝에서 되돌아가면 같은 간선의 역방향을 거리 검증 후 재획득한다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(19, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      final stoppedAtNode = tracker.update(
        _observation(
          atMs: 1000,
          confirmedSteps: 4,
          confirmedDistanceM: 2.8,
          previewSteps: 4,
          headingDeg: 90,
          raw: const PdrLocalPoint(21.8, 0),
          rawConfirmedStepPositions: const [
            PdrLocalPoint(19.7, 0),
            PdrLocalPoint(20.4, 0),
            PdrLocalPoint(21.1, 0),
            PdrLocalPoint(21.8, 0),
          ],
        ),
      );
      expect(stoppedAtNode.state, CorridorTrackingState.uncertain);
      expect(stoppedAtNode.currentEdgeId, 'bd');
      expect(stoppedAtNode.correctedPosition, const PdrLocalPoint(20, 0));

      tracker.update(
        _observation(
          atMs: 1400,
          confirmedSteps: 4,
          confirmedDistanceM: 2.8,
          previewSteps: 5,
          headingDeg: 270,
          raw: const PdrLocalPoint(21.8, 0),
        ),
      );
      final recovered = tracker.update(
        _observation(
          atMs: 3200,
          confirmedSteps: 7,
          confirmedDistanceM: 4.9,
          previewSteps: 8,
          headingDeg: 270,
          raw: const PdrLocalPoint(19.7, 0),
          rawConfirmedStepPositions: const [
            PdrLocalPoint(21.1, 0),
            PdrLocalPoint(20.4, 0),
            PdrLocalPoint(19.7, 0),
          ],
        ),
      );

      expect(recovered.state, CorridorTrackingState.nodeConfirmed);
      expect(recovered.currentEdgeId, 'bd');
      expect(recovered.travelDirectionSign, -1);
      expect(recovered.lastConfirmedNodeId, 'd');
      expect(recovered.correctedPosition.eastM, closeTo(17.9, 1e-9));
      expect(recovered.correctedPosition.northM, closeTo(0, 1e-9));
      expect(
        recovered.correctedPath,
        isNot(contains(const PdrLocalPoint(20, 3))),
      );
    });

    test('uncertain 복구는 최신 heading 스파이크보다 최근 확정 이동 형태를 우선한다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(19, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      tracker.update(
        _observation(
          atMs: 1000,
          confirmedSteps: 4,
          confirmedDistanceM: 2.8,
          previewSteps: 4,
          headingDeg: 90,
          raw: const PdrLocalPoint(21.8, 0),
        ),
      );
      tracker.update(
        _observation(
          atMs: 1400,
          confirmedSteps: 4,
          confirmedDistanceM: 2.8,
          previewSteps: 5,
          headingDeg: 270,
          raw: const PdrLocalPoint(21.8, 0),
        ),
      );
      final recovered = tracker.update(
        _observation(
          atMs: 3200,
          confirmedSteps: 7,
          confirmedDistanceM: 4.9,
          previewSteps: 8,
          // 최신 표본만 북쪽으로 튀었지만, 배치 내부 세 걸음은 서쪽이다.
          headingDeg: 0,
          raw: const PdrLocalPoint(19.7, 0),
          rawConfirmedStepPositions: const [
            PdrLocalPoint(21.1, 0),
            PdrLocalPoint(20.4, 0),
            PdrLocalPoint(19.7, 0),
          ],
        ),
      );

      expect(recovered.currentEdgeId, 'bd');
      expect(recovered.travelDirectionSign, -1);
      expect(recovered.correctedPosition.eastM, closeTo(17.9, 1e-9));
      expect(recovered.correctedPosition.northM, closeTo(0, 1e-9));
    });

    test('최신 heading만 후보와 맞고 초록 걸음별 방향이 다르면 회전을 확정하지 않는다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(7, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      tracker.update(
        _observation(
          atMs: 1200,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 1,
          headingDeg: 0,
        ),
      );
      tracker.update(
        _observation(
          atMs: 1800,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 2,
          headingDeg: 0,
        ),
      );
      final result = tracker.update(
        _observation(
          atMs: 3000,
          confirmedSteps: 8,
          confirmedDistanceM: 5.6,
          previewSteps: 8,
          headingDeg: 0,
          raw: const PdrLocalPoint(12.6, 0),
          rawConfirmedStepPositions: const [
            PdrLocalPoint(7.7, 0),
            PdrLocalPoint(8.4, 0),
            PdrLocalPoint(9.1, 0),
            PdrLocalPoint(9.8, 0),
            PdrLocalPoint(10.5, 0),
            PdrLocalPoint(11.2, 0),
            PdrLocalPoint(11.9, 0),
            PdrLocalPoint(12.6, 0),
          ],
        ),
      );

      expect(result.currentEdgeId, 'ab');
      expect(
        result.state,
        anyOf(
          CorridorTrackingState.turnPending,
          CorridorTrackingState.uncertain,
        ),
      );
    });

    test('복도 중간 유턴은 교차로 진입이나 다른 간선 전환으로 보지 않는다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(5, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      final result = tracker.update(
        _observation(
          atMs: 1000,
          confirmedSteps: 2,
          confirmedDistanceM: 1.4,
          previewSteps: 2,
          headingDeg: 270,
        ),
      );

      expect(result.state, CorridorTrackingState.straightTracking);
      expect(result.currentEdgeId, 'ab');
    });

    test('heading이 계속 흔들려도 보정 경로는 활성 간선 밖으로 나가지 않는다', () {
      final tracker = CorridorPositionTracker(_longStraightGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(45, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      const headings = [40.0, 150.0, 300.0, 20.0, 280.0];
      for (var step = 1; step <= headings.length; step += 1) {
        tracker.update(
          _observation(
            atMs: step * 500,
            confirmedSteps: step,
            confirmedDistanceM: step * 0.7,
            previewSteps: step,
            headingDeg: headings[step - 1],
            raw: PdrLocalPoint(45 + step * 0.4, step * 0.8),
            rawConfirmedStepPositions: [
              PdrLocalPoint(45 + step * 0.4, step * 0.8),
            ],
          ),
        );
      }

      expect(
        tracker.result.correctedPath.every(
          (point) =>
              point.northM.abs() < 1e-9 &&
              point.eastM >= 0 &&
              point.eastM <= 50,
        ),
        isTrue,
      );
    });

    test('연결 출구가 없는 간선 끝에서는 밖으로 뚫고 가지 않고 uncertain이 된다', () {
      final tracker = CorridorPositionTracker(_longStraightGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(49, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      final result = tracker.update(
        _observation(
          atMs: 1000,
          confirmedSteps: 4,
          confirmedDistanceM: 2.8,
          previewSteps: 4,
          headingDeg: 90,
          raw: const PdrLocalPoint(51.8, 0),
          rawConfirmedStepPositions: const [
            PdrLocalPoint(49.7, 0),
            PdrLocalPoint(50.4, 0),
            PdrLocalPoint(51.1, 0),
            PdrLocalPoint(51.8, 0),
          ],
        ),
      );

      expect(result.state, CorridorTrackingState.uncertain);
      expect(result.correctedPosition, const PdrLocalPoint(50, 0));
      expect(
        result.correctedPath.every((point) => point.northM.abs() < 1e-9),
        isTrue,
      );
    });

    test('시간 변화가 없는 heading 오차는 교차로 회전으로 오인하지 않는다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(8.5, 0),
          initialHeadingDeg: 20,
          timestampMs: 0,
        );

      tracker.update(
        _observation(
          atMs: 600,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 1,
          headingDeg: 20,
        ),
      );
      final result = tracker.update(
        _observation(
          atMs: 1200,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 2,
          headingDeg: 20,
        ),
      );

      expect(result.state, CorridorTrackingState.straightTracking);
      expect(result.pendingEdgeId, isNull);
    });

    test('진행 방향을 잠근 뒤 휴대폰 heading이 반대로 튀어도 위치와 표시 방향은 유지한다', () {
      final tracker = CorridorPositionTracker(_longStraightGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(5, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      tracker.update(
        _observation(
          atMs: 500,
          confirmedSteps: 1,
          confirmedDistanceM: 0.7,
          previewSteps: 1,
          headingDeg: 90,
          raw: const PdrLocalPoint(5.7, 0),
          rawConfirmedStepPositions: const [PdrLocalPoint(5.7, 0)],
        ),
      );
      final result = tracker.update(
        _observation(
          atMs: 1000,
          confirmedSteps: 2,
          confirmedDistanceM: 1.4,
          previewSteps: 2,
          headingDeg: 270,
          raw: const PdrLocalPoint(6.4, 0),
          rawConfirmedStepPositions: const [PdrLocalPoint(6.4, 0)],
        ),
      );

      expect(result.correctedPosition.eastM, closeTo(6.4, 1e-9));
      expect(result.correctedHeadingDeg, closeTo(90, 1e-9));
    });
  });
}
