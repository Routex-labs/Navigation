import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/route/dijkstra.dart';
import 'package:navigation_client/domain/route/route_endpoint_swap.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';

StoreIndexEntry store(String id, {String? node, String floor = 'B1'}) =>
    StoreIndexEntry(
      id: id,
      name: id,
      floorId: floor,
      floorName: floor,
      entranceNodeId: node,
    );

NodeReach reach(double m) => NodeReach(distanceM: m, costM: m);

void main() {
  group('현재 위치를 대신할 최근접 매장', () {
    test('도달 거리가 가장 짧은 매장을 고른다', () {
      final picked = nearestStoreForCurrentLocation(
        stores: [
          store('먼곳', node: 'n1'),
          store('가까운곳', node: 'n2'),
          store('중간', node: 'n3'),
        ],
        reachByNodeId: {'n1': reach(90), 'n2': reach(12), 'n3': reach(40)},
      );
      expect(picked?.name, '가까운곳');
    });

    test('거리를 모르면 고르지 않는다', () {
      // 야외이거나 PDR 측위 전이다. 여기서 아무 매장이나 고르면 사용자가 지정한
      // 적 없는 곳이 도착지가 된다 — nearestByWalkingDistance의 "같은 층 첫
      // 매장" 폴백을 쓰지 않는 이유다.
      expect(
        nearestStoreForCurrentLocation(
          stores: [store('아무곳', node: 'n1')],
          reachByNodeId: null,
        ),
        isNull,
      );
      expect(
        nearestStoreForCurrentLocation(
          stores: [store('아무곳', node: 'n1')],
          reachByNodeId: const {},
        ),
        isNull,
      );
    });

    test('지금 도착지는 후보에서 뺀다', () {
      // 도착지 바로 앞에 서 있는 경우. 그대로 뒤집으면 출발 == 도착이라
      // 길이 0인 경로가 된다.
      final picked = nearestStoreForCurrentLocation(
        stores: [
          store('스타벅스', node: 'n1'),
          store('옆집', node: 'n2'),
        ],
        reachByNodeId: {'n1': reach(2), 'n2': reach(50)},
        excludeNodeId: 'n1',
      );
      expect(picked?.name, '옆집');
    });

    test('뺐더니 남는 후보가 없으면 고르지 않는다', () {
      expect(
        nearestStoreForCurrentLocation(
          stores: [store('스타벅스', node: 'n1')],
          reachByNodeId: {'n1': reach(2)},
          excludeNodeId: 'n1',
        ),
        isNull,
      );
    });

    test('입구 노드가 없거나 그래프에 없는 매장은 건너뛴다', () {
      final picked = nearestStoreForCurrentLocation(
        stores: [
          store('노드없음'),
          store('그래프에없음', node: 'n404'),
          store('도달가능', node: 'n2'),
        ],
        reachByNodeId: {'n2': reach(70)},
      );
      expect(picked?.name, '도달가능');
    });

    test('전부 도달 불가면 고르지 않는다', () {
      expect(
        nearestStoreForCurrentLocation(
          stores: [
            store('a', node: 'n1'),
            store('b'),
          ],
          reachByNodeId: {'n9': reach(5)},
        ),
        isNull,
      );
    });

    test('거리가 같으면 먼저 훑은 쪽이 남는다', () {
      // 같은 입력이면 같은 결과가 나와야 한다. 누를 때마다 도착지가 바뀌면
      // 사용자는 버튼이 무슨 일을 하는지 알 수 없다.
      final stores = [store('먼저', node: 'n1'), store('나중', node: 'n2')];
      final reachMap = {'n1': reach(30), 'n2': reach(30)};
      for (var i = 0; i < 5; i++) {
        expect(
          nearestStoreForCurrentLocation(
            stores: stores,
            reachByNodeId: reachMap,
          )?.name,
          '먼저',
        );
      }
    });
  });
}
