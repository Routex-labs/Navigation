import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/features/debug_mode/debug_mode.dart';
import 'package:navigation_client/features/indoor_navigation/contract/calibration_state.dart';
import 'package:navigation_client/features/indoor_navigation/contract/pdr_anchor.dart';
import 'package:navigation_client/models/floor_graph.dart';
import 'package:shared_preferences/shared_preferences.dart';

PdrSnapshot _snapshot() => const PdrSnapshot(
  position: PdrLocalPoint(2, 0),
  path: [PdrLocalPoint.zero, PdrLocalPoint(1, 0), PdrLocalPoint(2, 0)],
  steps: 2,
  distanceM: 2,
  walkingHeadingDeg: 90,
  hasHeading: true,
  preview: PdrPreview(
    position: PdrLocalPoint(2.2, 0),
    path: [PdrLocalPoint.zero, PdrLocalPoint(1.1, 0), PdrLocalPoint(2.2, 0)],
    steps: 2,
    distanceM: 2.2,
  ),
  quality: PdrQuality(
    state: PdrQualityState.healthy,
    warnings: [],
    features: PdrQualityFeatures(
      greenOrangeDistanceDivergencePct: 10,
      orangeStepRatio: 1,
      orangeOvercountLikely: false,
      pedometerUndercountSuspected: false,
      pedometerFlaggedSpanS: 0,
      headingStable: true,
      headingSource: 'test',
      magneticAccuracy: 'high',
      rotationHeadingAccuracyDeg: 1,
      cadenceHz: 1.5,
      pitchDeg: 0,
      rollDeg: 0,
      headingReferenceIsMagneticNorth: true,
      peakRejectHistogram: {},
    ),
  ),
);

const _anchor = PdrAnchor(
  floorId: '1F',
  anchorLocalM: PdrLocalPoint(10, 20),
  rotationDeg: 0,
  headingReference: HeadingReference.magneticNorth,
  requiresManualRotationCalibration: false,
  source: AnchorSource.userPin,
  confidence: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'debug settings load defaults and persist every display toggle',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final controller = DebugModeController(preferences: preferences);
      await controller.ready;

      expect(controller.enabled, isFalse);
      expect(controller.showGraphNodes, isTrue);
      expect(controller.showGraphEdges, isTrue);
      expect(controller.showRawPdrPath, isTrue);
      expect(controller.showConfirmedPdrPath, isTrue);
      expect(controller.showMapMatchedPdrPath, isTrue);
      expect(controller.showAbsoluteCardinals, isTrue);
      expect(controller.showPhoneHeading, isTrue);

      await controller.setEnabled(true);
      await controller.setShowGraphNodes(false);
      await controller.setShowGraphEdges(false);
      await controller.setShowRawPdrPath(false);
      await controller.setShowConfirmedPdrPath(false);
      await controller.setShowMapMatchedPdrPath(false);
      await controller.setShowAbsoluteCardinals(false);
      await controller.setShowPhoneHeading(false);

      final restored = DebugModeController(preferences: preferences);
      await restored.ready;
      expect(restored.enabled, isTrue);
      expect(restored.showGraphNodes, isFalse);
      expect(restored.showGraphEdges, isFalse);
      expect(restored.showRawPdrPath, isFalse);
      expect(restored.showConfirmedPdrPath, isFalse);
      expect(restored.showMapMatchedPdrPath, isFalse);
      expect(restored.showAbsoluteCardinals, isFalse);
      expect(restored.showPhoneHeading, isFalse);

      controller.dispose();
      restored.dispose();
    },
  );

  test('더현대 절대 진북은 현재 도면 위쪽에서 시계방향 38.5도다', () {
    final reference = absoluteNorthReferenceForBuilding('thehyundai-seoul');

    expect(reference, isNotNull);
    expect(reference!.mapBearingDeg, 38.5);
    expect(
      absoluteDirectionScreenAngleDeg(
        mapBearingDeg: reference.mapBearingDeg,
        cameraBearingDeg: 10,
      ),
      28.5,
    );
    expect(
      absoluteDirectionScreenAngleDeg(
        mapBearingDeg: reference.mapBearingDeg,
        cameraBearingDeg: 90,
      ),
      308.5,
    );
    expect(absoluteNorthReferenceForBuilding('unknown'), isNull);
  });

  testWidgets('절대 방위 오버레이는 네 방위를 모두 표시한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AbsoluteCardinalOverlay(
            reference: AbsoluteNorthReference(
              mapBearingDeg: 38.5,
              description: 'test',
            ),
            cameraBearingDeg: 0,
            showPhoneHeading: true,
            phoneHeadingDeg: 25,
            phoneHeadingStable: false,
            phoneHeadingAccuracy: 'low',
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('absolute-cardinal-N')), findsOneWidget);
    expect(find.byKey(const ValueKey('absolute-cardinal-E')), findsOneWidget);
    expect(find.byKey(const ValueKey('absolute-cardinal-S')), findsOneWidget);
    expect(find.byKey(const ValueKey('absolute-cardinal-W')), findsOneWidget);
    expect(find.text('도면 진북 +38.5°'), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-heading-needle')), findsOneWidget);
    expect(find.text('폰 25° · LOW'), findsOneWidget);
  });

  test(
    'graph overlay marks the matched edge and its endpoint nodes active',
    () {
      final graph = FloorGraph(
        nodes: const [
          GraphNode(id: 'A', type: 'corridor', xM: 0, yM: 0),
          GraphNode(id: 'B', type: 'corridor', xM: 10, yM: 0),
          GraphNode(id: 'C', type: 'corridor', xM: 20, yM: 0),
        ],
        edges: const [
          GraphEdge(
            id: 'AB',
            fromNodeId: 'A',
            toNodeId: 'B',
            lengthM: 10,
            bidirectional: true,
            geometryLocalM: [],
          ),
          GraphEdge(
            id: 'BC',
            fromNodeId: 'B',
            toNodeId: 'C',
            lengthM: 10,
            bidirectional: true,
            geometryLocalM: [],
          ),
        ],
      );

      final overlay = buildDebugMapOverlay(graph, activeEdgeIds: {'AB'});

      expect(overlay.nodes, hasLength(3));
      expect(overlay.edges, hasLength(2));
      expect(
        overlay.nodes.where((node) => node.active).map((node) => node.id),
        containsAll(<String>['A', 'B']),
      );
      expect(
        overlay.nodes.singleWhere((node) => node.id == 'C').active,
        isFalse,
      );
      expect(
        overlay.edges.singleWhere((edge) => edge.id == 'AB').active,
        isTrue,
      );
      expect(
        overlay.edges.singleWhere((edge) => edge.id == 'BC').active,
        isFalse,
      );
    },
  );

  test('PDR trail survives stop calibration and clears on the next start', () {
    final snapshot = _snapshot();
    final state = DebugPdrTrailState()
      ..recordSnapshot(snapshot)
      ..recordCalibration(
        const CalibrationStatus(
          phase: CalibrationPhase.calibrated,
          headingReference: HeadingReference.magneticNorth,
          requiresManualRotationCalibration: false,
          anchor: _anchor,
        ),
      );

    // stopGuidance가 보내는 uncalibrated 상태는 마지막 선을 지우지 않는다.
    state.recordCalibration(const CalibrationStatus.uncalibrated());
    expect(state.snapshot, same(snapshot));
    expect(state.anchor, same(_anchor));

    // 다음 PDR 시작 시점에만 이전 세션 표시를 초기화한다.
    state.beginNewSession();
    expect(state.snapshot, isNull);
    expect(state.anchor, isNull);
  });

  testWidgets('debug toast floats compactly above the map controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDebugToast(
                context,
                message: 'PDR 세션이 종료됐습니다.',
                bottomOffset: 124,
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();

    final toast = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(toast.behavior, SnackBarBehavior.floating);
    expect((toast.margin! as EdgeInsets).bottom, 124);
    expect(find.text('PDR 세션이 종료됐습니다.'), findsOneWidget);
  });

  testWidgets('advanced options appear only after debug mode is enabled', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final controller = DebugModeController(preferences: preferences);
    await controller.ready;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => DebugModeSettingsButton(
              controller: controller,
              onPressed: () => showDebugModeSettingsSheet(context, controller),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.bug_report_outlined));
    await tester.pumpAndSettle();
    expect(find.text('고급 표시 옵션'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('debug-mode-enabled')));
    await tester.pumpAndSettle();
    expect(find.text('고급 표시 옵션'), findsOneWidget);
    expect(find.text('절대 동·서·남·북'), findsOneWidget);
    expect(find.text('폰 측정 방위'), findsOneWidget);
    expect(find.text('노드 이름'), findsNothing);
    expect(find.text('간선 이름'), findsNothing);
    expect(find.text('Raw 근접 경로'), findsOneWidget);
    expect(find.text('확정 PDR 경로'), findsOneWidget);
    expect(find.text('지도 부착 경로'), findsOneWidget);

    controller.dispose();
  });
}
