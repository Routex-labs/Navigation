/// 축소된 실내 지도에서 먼저 남길 매장 라벨의 안정적인 우선순위.
///
/// 단순 면적순이면 큰 매장이 몰린 한쪽만 남고, 검색 횟수순이면 신규 매장은
/// 영원히 보이지 않는다. 첫 매장은 면적으로 고르되 이후에는 이미 고른 매장과의
/// 거리 72% + 면적 28%로 선택한다. 그래서 층 전체에 고르게 퍼진 기준점이 먼저
/// 배치되고, 확대해 충돌 공간이 생길수록 나머지가 순서대로 나타난다.
library;

import 'dart:math' as math;

import '../../models/building/floor_plan.dart';

const kStoreLabelPriorityProperty = 'label_priority';

Map<String, int> rankStoreLabels(Iterable<StorePolygon> input) {
  final stores =
      input
          .where((store) => store.id.isNotEmpty && store.name.trim().isNotEmpty)
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
  if (stores.isEmpty) return const {};

  final areas = <String, double>{
    for (final store in stores) store.id: _storeAreaM2(store),
  };
  final maxArea = areas.values.reduce(math.max);
  final minLat = stores
      .map((store) => store.centroid.latitude)
      .reduce(math.min);
  final maxLat = stores
      .map((store) => store.centroid.latitude)
      .reduce(math.max);
  final minLng = stores
      .map((store) => store.centroid.longitude)
      .reduce(math.min);
  final maxLng = stores
      .map((store) => store.centroid.longitude)
      .reduce(math.max);
  final meanLat = (minLat + maxLat) / 2;
  final lngScale = math.cos(meanLat * math.pi / 180);
  final diagonal = math.sqrt(
    math.pow(maxLat - minLat, 2) + math.pow((maxLng - minLng) * lngScale, 2),
  );

  final remaining = [...stores];
  final picked = <StorePolygon>[];
  final result = <String, int>{};
  while (remaining.isNotEmpty) {
    StorePolygon? best;
    var bestScore = double.negativeInfinity;
    for (final candidate in remaining) {
      final areaScore = maxArea <= 0
          ? 0.0
          : math.log(1 + areas[candidate.id]!) / math.log(1 + maxArea);
      final distanceScore = picked.isEmpty || diagonal <= 0
          ? 0.0
          : picked
                .map(
                  (other) =>
                      _normalizedDistance(candidate, other, lngScale, diagonal),
                )
                .reduce(math.min)
                .clamp(0.0, 1.0);
      final score = picked.isEmpty
          ? areaScore
          : distanceScore * 0.72 + areaScore * 0.28;
      if (score > bestScore + 1e-12 ||
          ((score - bestScore).abs() <= 1e-12 &&
              (best == null || candidate.id.compareTo(best.id) < 0))) {
        best = candidate;
        bestScore = score;
      }
    }
    result[best!.id] = picked.length;
    picked.add(best);
    remaining.remove(best);
  }
  return result;
}

/// MVT에는 클라이언트가 계산한 우선순위 속성이 없으므로 id → 순위를 표현식으로
/// 옮긴다. [selectedStoreId]는 현재 작업 맥락이라 면적과 무관하게 가장 먼저
/// 충돌 판정을 받는다.
Object storeLabelSortKeyExpression(
  Map<String, int> ranks, {
  String? selectedStoreId,
}) {
  if (ranks.isEmpty) {
    if (selectedStoreId == null || selectedStoreId.isEmpty) return 0;
    return <Object>[
      'case',
      <Object>[
        '==',
        <Object>['get', 'id'],
        selectedStoreId,
      ],
      -1,
      0,
    ];
  }
  final ordered = ranks.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  final rankExpression = <Object>[
    'match',
    <Object>['get', 'id'],
    for (final entry in ordered) ...<Object>[entry.key, entry.value],
    ranks.length + 1,
  ];
  if (selectedStoreId == null || selectedStoreId.isEmpty) {
    return rankExpression;
  }
  return <Object>[
    'case',
    <Object>[
      '==',
      <Object>['get', 'id'],
      selectedStoreId,
    ],
    -1,
    rankExpression,
  ];
}

double _normalizedDistance(
  StorePolygon a,
  StorePolygon b,
  double lngScale,
  double diagonal,
) {
  final dy = a.centroid.latitude - b.centroid.latitude;
  final dx = (a.centroid.longitude - b.centroid.longitude) * lngScale;
  return math.sqrt(dx * dx + dy * dy) / diagonal;
}

double _storeAreaM2(StorePolygon store) {
  final local = store.polygonLocalM;
  if (local.length >= 3) {
    return _shoelace(local.map((point) => (x: point.x, y: point.y)).toList());
  }
  final polygon = store.polygon;
  if (polygon.length < 3) return 1;
  final meanLat =
      polygon.map((point) => point.latitude).reduce((a, b) => a + b) /
      polygon.length;
  const metersPerDegree = 111320.0;
  final lngMeters = metersPerDegree * math.cos(meanLat * math.pi / 180);
  return _shoelace([
    for (final point in polygon)
      (x: point.longitude * lngMeters, y: point.latitude * metersPerDegree),
  ]);
}

double _shoelace(List<({double x, double y})> points) {
  var twiceArea = 0.0;
  for (var index = 0; index < points.length; index++) {
    final next = points[(index + 1) % points.length];
    twiceArea += points[index].x * next.y - next.x * points[index].y;
  }
  return twiceArea.abs() / 2;
}
