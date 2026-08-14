import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/floor_plan.dart';
import 'package:navigation_client/widgets/store_label_priority.dart';

void main() {
  StorePolygon store(String id, double x, double y, double side) {
    final origin = LatLng(37 + y / 111320, 126 + x / 88000);
    return StorePolygon(
      id: id,
      name: id,
      centroid: origin,
      polygon: const [],
      polygonLocalM: [
        LocalFloorPoint(x, y),
        LocalFloorPoint(x + side, y),
        LocalFloorPoint(x + side, y + side),
        LocalFloorPoint(x, y + side),
      ],
    );
  }

  test('첫 라벨은 가장 큰 매장이다', () {
    final ranks = rankStoreLabels([
      store('small', 0, 0, 4),
      store('large', 10, 10, 12),
      store('medium', 20, 20, 8),
    ]);
    expect(ranks['large'], 0);
  });

  test('다음 라벨은 같은 구역의 두 번째 큰 매장보다 먼 기준점을 고른다', () {
    final ranks = rankStoreLabels([
      store('anchor', 0, 0, 12),
      store('near-large', 2, 2, 10),
      store('far-small', 100, 100, 4),
    ]);
    expect(ranks['far-small'], 1);
    expect(ranks['near-large'], 2);
  });

  test('같은 입력이면 순서와 무관하게 같은 순위를 만든다', () {
    final a = store('a', 0, 0, 8);
    final b = store('b', 50, 50, 8);
    final c = store('c', 25, 25, 8);
    expect(rankStoreLabels([a, b, c]), rankStoreLabels([c, a, b]));
  });

  test('선택 매장은 면적 순위보다 먼저 충돌 판정을 받는다', () {
    final expression =
        storeLabelSortKeyExpression(const {
              'large': 0,
              'small': 1,
            }, selectedStoreId: 'small')
            as List<Object>;
    expect(expression.first, 'case');
    expect(expression.toString(), contains('small'));
    expect(expression, contains(-1));
  });
}
