/// 디버그 모드 전용 PDR 진단 레이어(그래프 노드·간선 + 세 경로)의 등록·갱신.
///
/// 실내 지도(floor_plan_view.dart)가 이미 같은 세 경로를 그리고 있어서,
/// **색·굵기·점선 패턴을 그대로 맞춘다** — 두 화면에서 같은 선이 다른 색으로
/// 보이면 진단 자체를 믿을 수 없게 된다.
///
/// 세 경로를 따로 두는 이유는 PDR 파이프라인의 단계를 눈으로 분리해 보기
/// 위해서다. raw(주황 점선)는 걸음 추정이 만든 날것의 궤적, confirmed(초록)는
/// 그중 확정된 걸음만, matched(보라)는 confirmed를 통행 그래프 간선에 스냅한
/// 결과다. 셋이 갈라지는 지점이 곧 어느 단계에서 틀어졌는지를 가리킨다.
///
/// 화면 상태에서 분리해 둔 경계는 "무엇을 보여줄지"와 "지도에 쓰기"다.
/// 어떤 경로를 보여줄지(디버그 토글·층·앵커 판단)는 화면 상태가 정해 완성된
/// 데이터를 넘기고, 이 파일은 받은 데이터를 MapLibre 소스에 쓰는 일만 한다.
library;

import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/map_geojson.dart';
import '../../features/debug_mode/debug_map_overlay.dart';

const _debugGraphSourceId = 'outdoor-debug-graph';
const _debugGraphEdgeLayerId = 'outdoor-debug-graph-edges';
const _debugGraphActiveEdgeLayerId = 'outdoor-debug-graph-active-edges';
const _debugGraphNodeLayerId = 'outdoor-debug-graph-nodes';
const _debugGraphActiveNodeLayerId = 'outdoor-debug-graph-active-nodes';
const _pdrRawTrailSourceId = 'outdoor-pdr-raw-trail';
const _pdrRawTrailLayerId = 'outdoor-pdr-raw-trail-line';
const _pdrConfirmedTrailSourceId = 'outdoor-pdr-confirmed-trail';
const _pdrConfirmedTrailCasingLayerId = 'outdoor-pdr-confirmed-trail-casing';
const _pdrConfirmedTrailLayerId = 'outdoor-pdr-confirmed-trail-line';
const _pdrMatchedTrailSourceId = 'outdoor-pdr-matched-trail';
const _pdrMatchedTrailCasingLayerId = 'outdoor-pdr-matched-trail-casing';
const _pdrMatchedTrailLayerId = 'outdoor-pdr-matched-trail-line';

/// 진단 소스·레이어를 스타일에 등록한다. 데이터는 전부 빈 컬렉션으로 시작하고,
/// 이후 갱신은 [syncPdrDebugLayers]가 소스 데이터만 덮어쓴다.
Future<void> registerPdrDebugLayers(MapLibreMapController controller) async {
  await controller.addSource(
    _debugGraphSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addLineLayer(
    _debugGraphSourceId,
    _debugGraphEdgeLayerId,
    const LineLayerProperties(
      lineColor: '#607D8B',
      lineWidth: 2,
      lineOpacity: 0.72,
      lineDasharray: [2, 1.5],
      lineCap: 'round',
      lineJoin: 'round',
    ),
    filter: [
      '==',
      ['get', 'kind'],
      'edge',
    ],
    enableInteraction: false,
  );
  // 현재 PDR이 올라타 있다고 판정된 간선만 굵은 청록으로 덧그린다.
  await controller.addLineLayer(
    _debugGraphSourceId,
    _debugGraphActiveEdgeLayerId,
    const LineLayerProperties(
      lineColor: '#00ACC1',
      lineWidth: 5,
      lineOpacity: 0.88,
      lineCap: 'round',
      lineJoin: 'round',
    ),
    filter: [
      'all',
      [
        '==',
        ['get', 'kind'],
        'edge',
      ],
      [
        '==',
        ['get', 'active'],
        true,
      ],
    ],
    enableInteraction: false,
  );
  await controller.addCircleLayer(
    _debugGraphSourceId,
    _debugGraphNodeLayerId,
    const CircleLayerProperties(
      circleRadius: 4,
      circleColor: '#FFFFFF',
      circleStrokeColor: '#455A64',
      circleStrokeWidth: 2,
    ),
    filter: [
      '==',
      ['get', 'kind'],
      'node',
    ],
    enableInteraction: false,
  );
  await controller.addCircleLayer(
    _debugGraphSourceId,
    _debugGraphActiveNodeLayerId,
    const CircleLayerProperties(
      circleRadius: 6,
      circleColor: '#00ACC1',
      circleStrokeColor: '#FFFFFF',
      circleStrokeWidth: 2,
    ),
    filter: [
      'all',
      [
        '==',
        ['get', 'kind'],
        'node',
      ],
      [
        '==',
        ['get', 'active'],
        true,
      ],
    ],
    enableInteraction: false,
  );

  // raw: 걸음 추정이 만든 날것의 궤적. 점선이라 확정 경로와 겹쳐도 구분된다.
  await controller.addSource(
    _pdrRawTrailSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addLineLayer(
    _pdrRawTrailSourceId,
    _pdrRawTrailLayerId,
    const LineLayerProperties(
      lineColor: '#F57C00',
      lineWidth: 3.25,
      lineOpacity: 0.95,
      lineDasharray: [1.5, 1.5],
      lineCap: 'round',
      lineJoin: 'round',
    ),
    enableInteraction: false,
  );

  // confirmed: 확정된 걸음만. 흰 casing을 깔아 어두운 배경에서도 읽힌다.
  await controller.addSource(
    _pdrConfirmedTrailSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addLineLayer(
    _pdrConfirmedTrailSourceId,
    _pdrConfirmedTrailCasingLayerId,
    const LineLayerProperties(
      lineColor: '#FFFFFF',
      lineWidth: 6.25,
      lineOpacity: 0.82,
      lineCap: 'round',
      lineJoin: 'round',
    ),
    enableInteraction: false,
  );
  await controller.addLineLayer(
    _pdrConfirmedTrailSourceId,
    _pdrConfirmedTrailLayerId,
    const LineLayerProperties(
      lineColor: '#2E7D32',
      lineWidth: 3.25,
      lineOpacity: 0.96,
      lineCap: 'round',
      lineJoin: 'round',
    ),
    enableInteraction: false,
  );

  // matched: confirmed를 통행 그래프에 스냅한 결과. 셋이 갈라지는 지점이
  // 어느 단계에서 틀어졌는지를 가리킨다.
  await controller.addSource(
    _pdrMatchedTrailSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addLineLayer(
    _pdrMatchedTrailSourceId,
    _pdrMatchedTrailCasingLayerId,
    const LineLayerProperties(
      lineColor: '#FFFFFF',
      lineWidth: 6.5,
      lineOpacity: 0.9,
      lineCap: 'round',
      lineJoin: 'round',
    ),
    enableInteraction: false,
  );
  await controller.addLineLayer(
    _pdrMatchedTrailSourceId,
    _pdrMatchedTrailLayerId,
    const LineLayerProperties(
      lineColor: '#7E57C2',
      lineWidth: 3.25,
      lineOpacity: 0.96,
      lineCap: 'round',
      lineJoin: 'round',
    ),
    enableInteraction: false,
  );
}

/// 진단 소스 데이터를 덮어쓴다. 끌 때는 빈 [overlay]·빈 경로를 넘긴다 —
/// 레이어를 지웠다 다시 만들지 않고 데이터만 비우는 편이 층 전환·스타일
/// 재로드와 경쟁하지 않아 안전하다.
Future<void> syncPdrDebugLayers(
  MapLibreMapController controller, {
  required DebugMapOverlay overlay,
  required List<ll.LatLng> rawPath,
  required List<ll.LatLng> confirmedPath,
  required List<ll.LatLng> matchedPath,
}) async {
  final features = <Map<String, dynamic>>[
    for (final edge in overlay.edges)
      {
        'type': 'Feature',
        'properties': {'kind': 'edge', 'active': edge.active},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final p in edge.points) [p.longitude, p.latitude],
          ],
        },
      },
    for (final node in overlay.nodes)
      {
        'type': 'Feature',
        'properties': {'kind': 'node', 'active': node.active},
        'geometry': {
          'type': 'Point',
          'coordinates': [node.position.longitude, node.position.latitude],
        },
      },
  ];
  await controller.setGeoJsonSource(
    _debugGraphSourceId,
    geoJsonCollection(features),
  );

  await _setTrail(controller, _pdrRawTrailSourceId, rawPath);
  await _setTrail(controller, _pdrConfirmedTrailSourceId, confirmedPath);
  await _setTrail(controller, _pdrMatchedTrailSourceId, matchedPath);
}

/// 점 2개 미만이면 LineString이 성립하지 않아 소스를 비운다.
Future<void> _setTrail(
  MapLibreMapController controller,
  String sourceId,
  List<ll.LatLng> points,
) async {
  await controller.setGeoJsonSource(
    sourceId,
    points.length < 2
        ? emptyGeoJsonCollection()
        : geoJsonCollection([geoJsonLineFeature(points)]),
  );
}
