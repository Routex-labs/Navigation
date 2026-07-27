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
}) => CorridorObservation(
  timestampMs: atMs,
  rawConfirmedPosition: raw,
  confirmedSteps: confirmedSteps,
  confirmedDistanceM: confirmedDistanceM,
  rawPreviewPosition: raw,
  previewSteps: previewSteps,
  sensorHeadingDeg: headingDeg,
  hasHeading: true,
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
    test('직선에서는 위치와 heading bias가 함께 복도 방향으로 수렴한다', () {
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
      expect(result.correctedHeadingDeg, greaterThan(80));
      expect(result.correctedPosition.northM.abs(), lessThan(0.45));
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

    test('초록 배치는 수신 시점 heading이 아니라 복원된 걸음별 경로를 적분한다', () {
      final tracker = CorridorPositionTracker(_longStraightGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(1, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      final result = tracker.update(
        CorridorObservation(
          timestampMs: 1000,
          rawConfirmedPosition: const PdrLocalPoint(1, 1.4),
          confirmedSteps: 2,
          confirmedDistanceM: 1.4,
          rawPreviewPosition: const PdrLocalPoint(1, 1.4),
          previewSteps: 2,
          // 배치가 늦게 도착한 시점에는 폰이 이미 동쪽을 향한 상황.
          sensorHeadingDeg: 90,
          hasHeading: true,
          rawConfirmedStepPositions: const [
            PdrLocalPoint(1, 0.7),
            PdrLocalPoint(1, 1.4),
          ],
        ),
      );

      expect(result.correctedPosition.eastM, closeTo(1, 1e-9));
      expect(result.correctedPosition.northM, closeTo(1.4, 1e-9));
    });

    test('직진 연결 간선은 초록 거리로 노드 도달이 확인된 뒤 이어간다', () {
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

      expect(result.state, CorridorTrackingState.nodeConfirmed);
      expect(result.currentEdgeId, 'bd');
      expect(result.lastConfirmedNodeId, 'b');
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
  });
}
