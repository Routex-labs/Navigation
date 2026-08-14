import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/floor_plan.dart';
import 'package:navigation_client/core/map/store_label_anchor.dart';
import 'package:navigation_client/core/map/store_label_fit.dart';

/// 더현대 서울 B1 오설록·일상다완이 실제로 갖는 값. 중심점은 완전히 같고
/// POI 핀만 다르다 — 이 파일이 지키려는 상황 그대로다.
const _sharedCentroid = LatLng(37.526366, 126.928334);

/// 두 매장이 공유하는 폴리곤. 실제 크기는 가로 9.6m · 세로 6.17m다.
/// 위도 1도 ≈ 111320m, 이 위도에서 경도 1도 ≈ 88300m로 잡아 만들었다.
const _polygon = <LatLng>[
  LatLng(37.526394, 126.928280),
  LatLng(37.526394, 126.928389),
  LatLng(37.526339, 126.928389),
  LatLng(37.526339, 126.928280),
];

/// 원본 핀. 오설록이 북쪽(화면 위), 일상다완이 남쪽에 찍혀 있다.
const _osullocPin = LatLng(37.526373, 126.928307);
const _ilsangPin = LatLng(37.526363, 126.928345);

StorePolygon _store(
  String id, {
  LatLng centroid = _sharedCentroid,
  LatLng? entrance,
  List<LatLng> polygon = _polygon,
}) => StorePolygon(
  id: id,
  name: id,
  polygon: polygon,
  centroid: centroid,
  entrance: entrance,
);

/// [a]와 [b]가 화면 세로로 얼마나 떨어져 있는가(m). bearing 0 기준이라 위도만 본다.
double _verticalGapM(LatLng a, LatLng b) =>
    ((a.latitude - b.latitude) * 111320.0).abs();

void main() {
  test('혼자 있는 매장은 중심점 그대로 둔다', () {
    final anchors = resolveStoreLabelAnchors(
      stores: [_store('a', entrance: _osullocPin)],
      bearingDeg: 0,
    );

    expect(anchors['a'], _sharedCentroid);
  });

  // 핵심. 앵커를 원본 핀으로 옮기기만 했을 때는 두 라벨이 3.6m 간격에 6.8m 폭을
  // 요구해 겹쳤고, 실기기에서 하나가 지워졌다. 칸으로 나누면 간격이 폴리곤
  // 세로의 절반(≈3.1m)으로 **정해지고**, 라벨도 같은 칸 높이에 맞춰진다.
  test('겹친 두 매장은 폴리곤 세로를 반으로 나눈 칸에 하나씩 놓인다', () {
    final anchors = resolveStoreLabelAnchors(
      stores: [
        _store('osulloc', entrance: _osullocPin),
        _store('ilsangdawan', entrance: _ilsangPin),
      ],
      bearingDeg: 0,
    );

    final box = storeLabelBoxMeters(polygon: _polygon, bearingDeg: 0);
    final gap = _verticalGapM(anchors['osulloc']!, anchors['ilsangdawan']!);

    expect(gap, closeTo(box.heightM / 2, 0.05));
    // 중심점을 사이에 두고 대칭이다.
    expect(
      (anchors['osulloc']!.latitude + anchors['ilsangdawan']!.latitude) / 2,
      closeTo(_sharedCentroid.latitude, 1e-9),
    );
  });

  test('원본 핀이 위에 있던 매장이 위 칸으로 간다', () {
    final anchors = resolveStoreLabelAnchors(
      stores: [
        _store('ilsangdawan', entrance: _ilsangPin),
        _store('osulloc', entrance: _osullocPin),
      ],
      bearingDeg: 0,
    );

    // 오설록 핀이 북쪽 = 화면 위쪽이므로 위 칸이어야 한다.
    expect(
      anchors['osulloc']!.latitude,
      greaterThan(anchors['ilsangdawan']!.latitude),
    );
  });

  test('세 곳이 겹치면 세 칸으로 나누고 가운데는 중심점에 남는다', () {
    final anchors = resolveStoreLabelAnchors(
      stores: [_store('a'), _store('b'), _store('c')],
      bearingDeg: 0,
    );

    final box = storeLabelBoxMeters(polygon: _polygon, bearingDeg: 0);
    // 핀이 없으므로 id 순으로 위에서 아래.
    expect(anchors['a']!.latitude, greaterThan(anchors['b']!.latitude));
    expect(anchors['b']!.latitude, greaterThan(anchors['c']!.latitude));
    expect(anchors['b']!.latitude, closeTo(_sharedCentroid.latitude, 1e-9));
    expect(
      _verticalGapM(anchors['a']!, anchors['b']!),
      closeTo(box.heightM / 3, 0.05),
    );
  });

  test('폴리곤이 없으면 고정 간격으로 벌린다', () {
    final anchors = resolveStoreLabelAnchors(
      stores: [
        _store('a', polygon: const []),
        _store('b', polygon: const []),
      ],
      bearingDeg: 0,
      fallbackGapM: 10,
    );

    expect(_verticalGapM(anchors['a']!, anchors['b']!), closeTo(10, 0.01));
  });

  test('지도가 돌아가 있으면 칸도 따라 돈다', () {
    final anchors = resolveStoreLabelAnchors(
      stores: [_store('a', polygon: const []), _store('b', polygon: const [])],
      bearingDeg: 90,
      fallbackGapM: 10,
    );

    // bearing 90 → 화면 위쪽이 동쪽이라 경도로 갈린다.
    expect(anchors['a']!.longitude, isNot(anchors['b']!.longitude));
    expect(anchors['a']!.latitude, closeTo(_sharedCentroid.latitude, 1e-9));
  });

  test('입력 순서가 달라도 같은 결과를 낸다', () {
    final forward = resolveStoreLabelAnchors(
      stores: [_store('a'), _store('b')],
      bearingDeg: 0,
    );
    final reversed = resolveStoreLabelAnchors(
      stores: [_store('b'), _store('a')],
      bearingDeg: 0,
    );

    expect(forward['a'], reversed['a']);
    expect(forward['b'], reversed['b']);
  });

  test('빈 목록은 빈 결과', () {
    expect(resolveStoreLabelAnchors(stores: [], bearingDeg: 0), isEmpty);
  });

  group('한 자리 그룹과 묶음 라벨 문구', () {
    test('centroid를 공유하는 매장만 그룹이 되고 핀 순서로 정렬된다', () {
      final groups = sharedStoreGroups([
        _store('ilsangdawan', entrance: _ilsangPin),
        _store('osulloc', entrance: _osullocPin),
        _store('alone', centroid: const LatLng(37.5265, 126.9290)),
      ], bearingDeg: 0);

      expect(groups, hasLength(1));
      // 오설록 핀이 북쪽 = 화면 위쪽이라 먼저 온다.
      expect(groups.single.map((s) => s.id), ['osulloc', 'ilsangdawan']);
    });

    // 백엔드 tiling._cluster_labels와 같은 형식이어야 두 화면이 같은 자리에
    // 같은 문구를 적는다.
    test('묶음 라벨 문구는 「첫 매장 외 N」이다', () {
      final groups = sharedStoreGroups([
        _store('a'),
        _store('b'),
        _store('c'),
      ], bearingDeg: 0);

      expect(clusterLabelText(groups.single), 'a 외 2');
    });
  });

  group('묶음 매장 판정', () {
    StorePolygon named(String id, String name) => StorePolygon(
      id: id,
      name: name,
      polygon: const [],
      centroid: LatLng(37.5 + id.hashCode % 100 * 1e-4, 126.9),
    );

    // 백엔드 tiling._aggregate_store_ids와 같은 규칙이어야 타일 라벨과
    // 클라이언트 탭 판정이 같은 매장을 같은 쪽으로 취급한다.
    test('다른 매장 이름 2개 이상을 이어 붙인 항목만 묶음이다', () {
      final ids = aggregateStoreIds([
        named('agg', '포동 푸딩 우나하우스 세띠엠므 멜로드도산'),
        named('podong', '포동 푸딩'),
        // 표기 흔들림: 묶음에는 「세띠엠므」, 구성 매장에는 「세띠 엠므」.
        named('setti', '세띠 엠므'),
        named('melrod', '멜로드도산'),
      ]);

      expect(ids, {'agg'});
    });

    test('다른 매장 이름을 하나만 품는 매장은 묶음이 아니다', () {
      final ids = aggregateStoreIds([
        named('nb', '뉴발란스'),
        named('nbkids', '뉴발란스 키즈'),
      ]);

      expect(ids, isEmpty);
    });

    test('같은 이름 두 매장은 서로를 묶음으로 만들지 않는다', () {
      final ids = aggregateStoreIds([
        named('subway1', '지하철 5/9호선 여의도역'),
        named('subway2', '지하철 5/9호선 여의도역'),
      ]);

      expect(ids, isEmpty);
    });
  });

  group('한 자리를 나눠 쓰는 매장 수', () {
    test('혼자면 1, 둘이 겹치면 2', () {
      final counts = storeLabelShareCounts([
        _store('osulloc', entrance: _osullocPin),
        _store('ilsangdawan', entrance: _ilsangPin),
        _store('alone', centroid: const LatLng(37.5265, 126.9290)),
      ]);

      expect(counts['osulloc'], 2);
      expect(counts['ilsangdawan'], 2);
      expect(counts['alone'], 1);
    });

    // 칸을 나눠 놓아도 글자가 폴리곤 전체 크기면 칸을 넘어 서로를 밀어낸다.
    // 칸 높이에 맞춘 글자라면 두 개를 쌓아도 폴리곤 세로 안에 들어가야 한다.
    test('칸 높이에 맞춘 글자는 두 개를 쌓아도 폴리곤 안에 들어간다', () {
      final box = storeLabelBoxMeters(polygon: _polygon, bearingDeg: 0);

      final solo = fitStoreLabel(
        name: '오설록',
        boxWidthM: box.widthM,
        boxHeightM: box.heightM,
      );
      final shared = fitStoreLabel(
        name: '오설록',
        boxWidthM: box.widthM,
        boxHeightM: box.heightM / 2,
      );

      expect(shared.emMeters, lessThan(solo.emMeters));
      final stackedHeight =
          shared.emMeters * shared.lines * kStoreLabelLineHeightEm * 2;
      expect(stackedHeight, lessThanOrEqualTo(box.heightM));
    });
  });
}
