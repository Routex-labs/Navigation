import 'package:latlong2/latlong.dart' as ll;

import '../../domain/geo_transform.dart';
import '../../models/floor_graph.dart';

class DebugMapNode {
  const DebugMapNode({
    required this.id,
    required this.position,
    required this.active,
  });

  final String id;
  final ll.LatLng position;
  final bool active;
}

class DebugMapEdge {
  const DebugMapEdge({
    required this.id,
    required this.points,
    required this.labelPosition,
    required this.active,
  });

  final String id;
  final List<ll.LatLng> points;
  final ll.LatLng labelPosition;
  final bool active;
}

class DebugMapOverlay {
  const DebugMapOverlay({
    this.nodes = const [],
    this.edges = const [],
    this.showNodes = false,
    this.showEdges = false,
    this.showNodeLabels = false,
    this.showEdgeLabels = false,
  });

  final List<DebugMapNode> nodes;
  final List<DebugMapEdge> edges;
  final bool showNodes;
  final bool showEdges;
  final bool showNodeLabels;
  final bool showEdgeLabels;

  bool get isEmpty => nodes.isEmpty && edges.isEmpty;
}

/// floor-local navigation graph를 MapLibre가 바로 그릴 수 있는 WGS84 진단
/// 데이터로 바꾼다. 지도 위젯은 graph 모델을 알 필요 없이 이 결과만 받는다.
DebugMapOverlay buildDebugMapOverlay(
  FloorGraph? graph, {
  bool showNodes = true,
  bool showEdges = true,
  bool showNodeLabels = false,
  bool showEdgeLabels = false,
  Set<String> activeEdgeIds = const {},
}) {
  if (graph == null ||
      graph.nodes.isEmpty ||
      (!showNodes && !showEdges && !showNodeLabels && !showEdgeLabels)) {
    return const DebugMapOverlay();
  }

  final transform = fitFloorGeoTransform(graph.nodes);
  final nodesById = {for (final node in graph.nodes) node.id: node};
  final activeNodeIds = <String>{};
  for (final edge in graph.edges) {
    if (activeEdgeIds.contains(edge.id)) {
      activeNodeIds
        ..add(edge.fromNodeId)
        ..add(edge.toNodeId);
    }
  }

  ll.LatLng convert(double x, double y) {
    final point = transform.apply(x, y);
    return ll.LatLng(point.$1, point.$2);
  }

  final nodes = showNodes || showNodeLabels
      ? [
          for (final node in graph.nodes)
            DebugMapNode(
              id: node.id,
              position: convert(node.xM, node.yM),
              active: activeNodeIds.contains(node.id),
            ),
        ]
      : const <DebugMapNode>[];

  final edges = <DebugMapEdge>[];
  if (showEdges || showEdgeLabels) {
    for (final edge in graph.edges) {
      final from = nodesById[edge.fromNodeId];
      final to = nodesById[edge.toNodeId];
      final localPoints = edge.geometryLocalM.length >= 2
          ? edge.geometryLocalM
          : (from == null || to == null
                ? const <LocalPoint>[]
                : [LocalPoint(from.xM, from.yM), LocalPoint(to.xM, to.yM)]);
      if (localPoints.length < 2) continue;
      final points = [
        for (final point in localPoints) convert(point.x, point.y),
      ];
      edges.add(
        DebugMapEdge(
          id: edge.id,
          points: points,
          labelPosition: points[points.length ~/ 2],
          active: activeEdgeIds.contains(edge.id),
        ),
      );
    }
  }

  return DebugMapOverlay(
    nodes: nodes,
    edges: edges,
    showNodes: showNodes,
    showEdges: showEdges,
    showNodeLabels: showNodeLabels,
    showEdgeLabels: showEdgeLabels,
  );
}
