import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/debug_mode/debug_mode.dart';
import 'package:navigation_client/models/floor_graph.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      expect(controller.showGraphNodeLabels, isFalse);
      expect(controller.showGraphEdges, isTrue);
      expect(controller.showGraphEdgeLabels, isFalse);
      expect(controller.showRawPdrPath, isTrue);
      expect(controller.showConfirmedPdrPath, isTrue);
      expect(controller.showMapMatchedPdrPath, isTrue);

      await controller.setEnabled(true);
      await controller.setShowGraphNodes(false);
      await controller.setShowGraphNodeLabels(true);
      await controller.setShowGraphEdges(false);
      await controller.setShowGraphEdgeLabels(true);
      await controller.setShowRawPdrPath(false);
      await controller.setShowConfirmedPdrPath(false);
      await controller.setShowMapMatchedPdrPath(false);

      final restored = DebugModeController(preferences: preferences);
      await restored.ready;
      expect(restored.enabled, isTrue);
      expect(restored.showGraphNodes, isFalse);
      expect(restored.showGraphNodeLabels, isTrue);
      expect(restored.showGraphEdges, isFalse);
      expect(restored.showGraphEdgeLabels, isTrue);
      expect(restored.showRawPdrPath, isFalse);
      expect(restored.showConfirmedPdrPath, isFalse);
      expect(restored.showMapMatchedPdrPath, isFalse);

      controller.dispose();
      restored.dispose();
    },
  );

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
    expect(find.text('노드 이름'), findsOneWidget);
    expect(find.text('간선 이름'), findsOneWidget);
    expect(find.text('Raw 근접 경로'), findsOneWidget);
    expect(find.text('확정 PDR 경로'), findsOneWidget);
    expect(find.text('지도 부착 경로'), findsOneWidget);

    controller.dispose();
  });
}
