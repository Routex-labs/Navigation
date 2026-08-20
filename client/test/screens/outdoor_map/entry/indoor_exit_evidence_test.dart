import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/guidance/corridor_tracking.dart';
import 'package:navigation_client/domain/route/building_entrances.dart';
import 'package:navigation_client/models/building/floor_graph.dart';
import 'package:navigation_client/models/building/floor_plan.dart';
import 'package:navigation_client/screens/outdoor_map/entry/indoor_entry_gps.dart';
import 'package:navigation_client/screens/outdoor_map/entry/indoor_exit_evidence.dart';

/// 손으로 만든 층 좌표계. x=동쪽 m, y=북쪽 m.
const _lat0 = 37.5;
const _lng0 = 127.0;
const _metersPerDegreeLat = 111320.0;

LatLng _wgs84(double xM, double yM) => LatLng(
  _lat0 + yM / _metersPerDegreeLat,
  _lng0 + xM / (_metersPerDegreeLat * math.cos(_lat0 * math.pi / 180)),
);

GraphNode _node(String id, double xM, double yM) {
  final point = _wgs84(xM, yM);
  return GraphNode(
    id: id,
    type: 'corridor',
    xM: xM,
    yM: yM,
    lat: point.latitude,
    lng: point.longitude,
  );
}

/// 문 안쪽 앵커 노드가 원점인 층 그래프.
FloorGraph _graph() => FloorGraph(
  nodes: [_node('n-inside', 0, 0), _node('n-east', 20, 0), _node('n-north', 0, 20)],
  edges: const [],
);

/// 문 앞 좌표가 ([doorX], [doorY])인 출구 하나짜리 도면.
FloorPlan _plan({required double doorX, required double doorY}) => FloorPlan(
  stores: [
    StorePolygon(
      id: 'exit-1',
      name: '출구',
      polygon: const [],
      centroid: _wgs84(doorX, doorY),
      entranceNodeId: 'n-inside',
      subcategory: kGroundEntranceSubcategory,
    ),
  ],
  pois: const [],
);

GpsBuildingJudgement _judgement({
  double accuracy = 10,
  double inside = 0,
  double outside = 0,
  bool hasFootprint = true,
}) => GpsBuildingJudgement(
  verdict: GpsBuildingVerdict.unclear,
  accuracyMeters: accuracy,
  metersInside: inside,
  metersOutside: outside,
  hasFootprint: hasFootprint,
);

({bool leftDoorZone, bool reached}) _step({
  required bool leftDoorZone,
  required double x,
  required double y,
  bool onDefaultFloor = true,
  CorridorTrackingState? state = CorridorTrackingState.straightTracking,
  List<PdrLocalPoint> doors = const [PdrLocalPoint(0, -10)],
}) => stepExitDoorEvidence(
  leftDoorZone: leftDoorZone,
  positionM: PdrLocalPoint(x, y),
  onDefaultFloor: onDefaultFloor,
  corridorState: state,
  doorPointsM: doors,
);

void main() {
  group('exitDoorPointsFloorLocalM', () {
    test('문 앞 좌표를 층 로컬 m로 되돌린다', () {
      final points = exitDoorPointsFloorLocalM(
        _plan(doorX: 0, doorY: -10),
        _graph(),
      );
      expect(points, hasLength(1));
      expect(points.single.eastM, closeTo(0, 0.5));
      expect(points.single.northM, closeTo(-10, 0.5));
    });

    test('도면이나 그래프가 없으면 빈 목록', () {
      expect(exitDoorPointsFloorLocalM(null, _graph()), isEmpty);
      expect(exitDoorPointsFloorLocalM(_plan(doorX: 0, doorY: -10), null), isEmpty);
    });

    test('출구가 없는 도면이면 빈 목록', () {
      final plan = FloorPlan(
        stores: [
          StorePolygon(
            id: 'store-1',
            name: '카페',
            polygon: const [],
            centroid: _wgs84(5, 5),
            entranceNodeId: 'n-inside',
            subcategory: '식음료',
          ),
        ],
        pois: const [],
      );
      expect(exitDoorPointsFloorLocalM(plan, _graph()), isEmpty);
    });
  });

  group('stepExitDoorEvidence', () {
    test('들어온 직후에는 문 앞이어도 이탈이 아니다', () {
      expect(_step(leftDoorZone: false, x: 0, y: -8).reached, isFalse);
    });

    test('문에서 멀어졌다가 다시 닿으면 이탈이다', () {
      final away = _step(leftDoorZone: false, x: 0, y: 40);
      expect(away.leftDoorZone, isTrue);
      expect(away.reached, isFalse);
      final back = _step(leftDoorZone: away.leftDoorZone, x: 0, y: -8);
      expect(back.reached, isTrue);
    });

    test('문 안쪽 앵커 노드(실측 간격 상한 12 m)에 서 있어도 걸린다', () {
      // 화면 그래프에는 문 노드가 없어 보정 위치가 문 앞 좌표에 닿을 수 없다.
      // 반경이 실측 간격 상한보다 작으면 이 판정은 영원히 안 걸린다.
      final back = _step(leftDoorZone: true, x: 0, y: 0, doors: const [
        PdrLocalPoint(0, -12),
      ]);
      expect(back.reached, isTrue);
    });

    test('기본 층이 아니면 판정하지 않고 래치도 안 세운다', () {
      final away = _step(leftDoorZone: false, x: 0, y: 40, onDefaultFloor: false);
      expect(away.leftDoorZone, isFalse);
      expect(away.reached, isFalse);
    });

    test('복도 추적이 uncertain이거나 결과가 없으면 판정하지 않는다', () {
      expect(
        _step(
          leftDoorZone: true,
          x: 0,
          y: -8,
          state: CorridorTrackingState.uncertain,
        ).reached,
        isFalse,
      );
      expect(_step(leftDoorZone: true, x: 0, y: -8, state: null).reached, isFalse);
    });

    test('문 좌표가 없으면 판정하지 않는다', () {
      expect(_step(leftDoorZone: true, x: 0, y: -8, doors: const []).reached, isFalse);
    });
  });

  group('nextUnclearOutsideSince', () {
    final t0 = DateTime.utc(2026, 1, 1, 12);

    test('바깥이면 시작 시각을 세우고 이후에도 유지한다', () {
      final since = nextUnclearOutsideSince(
        judgement: _judgement(outside: 2),
        since: null,
        now: t0,
      );
      expect(since, t0);
      expect(
        nextUnclearOutsideSince(
          judgement: _judgement(outside: 5),
          since: since,
          now: t0.add(const Duration(seconds: 5)),
        ),
        t0,
      );
    });

    test('안쪽으로 찍히면 되돌린다', () {
      expect(
        nextUnclearOutsideSince(
          judgement: _judgement(inside: 3),
          since: t0,
          now: t0.add(const Duration(seconds: 5)),
        ),
        isNull,
      );
    });

    test('못 믿는 좌표는 시계를 건드리지 않는다', () {
      for (final judgement in [
        _judgement(accuracy: outdoorExitAccuracyMeters + 1),
        _judgement(hasFootprint: false),
      ]) {
        expect(
          nextUnclearOutsideSince(
            judgement: judgement,
            since: t0,
            now: t0.add(const Duration(seconds: 5)),
          ),
          t0,
        );
      }
    });
  });

  group('unclearOutsideExitDue', () {
    final t0 = DateTime.utc(2026, 1, 1, 12);

    test('지속이 문턱을 채워야 걸린다', () {
      expect(unclearOutsideExitDue(null, t0), isFalse);
      expect(
        unclearOutsideExitDue(t0, t0.add(kUnclearOutsideExitHold - const Duration(seconds: 1))),
        isFalse,
      );
      expect(unclearOutsideExitDue(t0, t0.add(kUnclearOutsideExitHold)), isTrue);
    });
  });
}
