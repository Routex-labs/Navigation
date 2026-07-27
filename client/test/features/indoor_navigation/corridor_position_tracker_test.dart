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
  List<PdrLocalPoint> rawPreviewTailPositions = const [],
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
  rawPreviewTailPositions: rawPreviewTailPositions,
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

    test('초록보다 앞선 주황 tail은 확정 위치를 바꾸지 않고 보라 preview만 진행한다', () {
      final tracker = CorridorPositionTracker(_longStraightGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(1, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      final result = tracker.update(
        _observation(
          atMs: 1000,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 3,
          headingDeg: 90,
          rawPreviewTailPositions: const [
            PdrLocalPoint(1, 0),
            PdrLocalPoint(1.7, 0),
            PdrLocalPoint(2.4, 0),
            PdrLocalPoint(3.1, 0),
          ],
        ),
      );

      expect(result.correctedPosition, const PdrLocalPoint(1, 0));
      expect(result.previewPosition.eastM, closeTo(3.1, 1e-9));
      expect(result.previewPosition.northM, closeTo(0, 1e-9));
      expect(result.previewPath, hasLength(4));
    });

    test('주황 tail의 직진-회전 형태를 연결 간선 후보와 비교한다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(9, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      final result = tracker.update(
        _observation(
          atMs: 1000,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 4,
          headingDeg: 0,
          rawPreviewTailPositions: const [
            PdrLocalPoint(9, 0),
            PdrLocalPoint(9.7, 0),
            PdrLocalPoint(10, 0),
            PdrLocalPoint(10, 0.7),
            PdrLocalPoint(10, 1.4),
          ],
        ),
      );

      expect(result.correctedPosition, const PdrLocalPoint(9, 0));
      expect(result.previewPosition.eastM, closeTo(10, 1e-9));
      expect(result.previewPosition.northM, closeTo(1.4, 1e-9));
      expect(result.previewCandidateEdgeIds, contains('bc'));
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
