import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/route/dijkstra.dart';
import 'package:navigation_client/domain/store/nearby_stores.dart';
import 'package:navigation_client/models/store_index_entry.dart';

/// `nearby_stores.dart` 머리말의 검증 기준 표를 그대로 옮긴 것이다.
void main() {
  StoreIndexEntry store(
    String id, {
    String? name,
    String? nodeId,
    String kind = 'store',
    String floorName = 'B2',
  }) => StoreIndexEntry(
    id: id,
    name: name ?? id,
    floorId: 'floor-b2',
    floorName: floorName,
    kind: kind,
    entranceNodeId: nodeId,
  );

  NodeReach reach(double m) => NodeReach(distanceM: m, costM: m);

  group('근처 매장', () {
    test('거리 오름차순으로 고르고 자기 자신은 뺀다', () {
      final result = nearbyStores(
        stores: [
          store('me', nodeId: 'n0'),
          store('far', nodeId: 'n2'),
          store('near', nodeId: 'n1'),
        ],
        reachByNodeId: {'n0': reach(0), 'n1': reach(10), 'n2': reach(40)},
        excludePlaceId: 'me',
      );

      expect(result.map((e) => e.store.id), ['near', 'far']);
      expect(result.first.reach.distanceM, 10);
    });

    // 입구 노드가 없으면 경로 계산의 도착점이 없다. 직선거리로 대신하면 실내에서
    // 벽을 뚫고 지나가는 값이 되어, 30m라고 적어 두고 실제로는 반대편으로 돌아가야
    // 하는 일이 생긴다 — 거리를 모르는 것보다 나쁘다.
    test('입구 노드가 없는 매장은 뺀다', () {
      final result = nearbyStores(
        stores: [store('a'), store('b', nodeId: 'n1')],
        reachByNodeId: {'n1': reach(10)},
        excludePlaceId: 'me',
      );

      expect(result.map((e) => e.store.id), ['b']);
    });

    test('그래프가 끊겨 도달할 수 없는 매장은 뺀다', () {
      final result = nearbyStores(
        stores: [store('a', nodeId: 'orphan'), store('b', nodeId: 'n1')],
        reachByNodeId: {'n1': reach(10)},
        excludePlaceId: 'me',
      );

      expect(result.map((e) => e.store.id), ['b']);
    });

    // 색인에는 주차 787·에스컬레이터 152·엘리베이터 68이 섞여 있다(전체의 61%).
    // 화장실 같은 시설도 뺀다 — 제목이 "근처 매장"이다.
    test('매장이 아닌 것(주차·시설)은 뺀다', () {
      final result = nearbyStores(
        stores: [
          store('parking', nodeId: 'n1', kind: 'excluded'),
          store('toilet', nodeId: 'n2', kind: 'facility'),
          store('shop', nodeId: 'n3'),
        ],
        reachByNodeId: {'n1': reach(1), 'n2': reach(2), 'n3': reach(30)},
        excludePlaceId: 'me',
      );

      expect(result.map((e) => e.store.id), ['shop']);
    });

    // 동점을 그대로 두면 인덱스 순서(서버가 층 내림차순으로 고정)에 기대게 되어,
    // 같은 데이터에서도 층이 바뀌면 줄 순서가 따라 바뀐다.
    test('거리가 같으면 이름순으로 고정한다', () {
      final result = nearbyStores(
        stores: [
          store('b', name: '나', nodeId: 'n1'),
          store('a', name: '가', nodeId: 'n2'),
        ],
        reachByNodeId: {'n1': reach(10), 'n2': reach(10)},
        excludePlaceId: 'me',
      );

      expect(result.map((e) => e.store.name), ['가', '나']);
    });

    // 같은 입구 노드를 공유하는 매장이 있다. 거리 0은 오류가 아니라 바로 옆이라는
    // 뜻이라 빼지 않는다.
    test('거리 0인 매장도 남긴다', () {
      final result = nearbyStores(
        stores: [store('next-door', nodeId: 'n0')],
        reachByNodeId: {'n0': reach(0)},
        excludePlaceId: 'me',
      );

      expect(result, hasLength(1));
      expect(result.first.reach.distanceM, 0);
    });

    test('limit까지만 고르고, 그보다 적으면 있는 만큼만', () {
      final many = [
        for (var index = 0; index < 9; index++)
          store('s$index', nodeId: 'n$index'),
      ];
      final reaches = {
        for (var index = 0; index < 9; index++)
          'n$index': reach(index.toDouble()),
      };

      expect(
        nearbyStores(
          stores: many,
          reachByNodeId: reaches,
          excludePlaceId: 'me',
        ),
        hasLength(5),
      );
      expect(
        nearbyStores(
          stores: many.take(2).toList(),
          reachByNodeId: reaches,
          excludePlaceId: 'me',
        ),
        hasLength(2),
      );
    });

    test('고를 것이 없으면 빈 목록이다', () {
      expect(
        nearbyStores(
          stores: [store('me', nodeId: 'n0')],
          reachByNodeId: {'n0': reach(0)},
          excludePlaceId: 'me',
        ),
        isEmpty,
      );
    });
  });
}
