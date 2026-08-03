import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/dijkstra.dart';
import 'package:navigation_client/domain/nearby_facilities.dart';

NodeReach _reach(double m) => NodeReach(distanceM: m, costM: m);

void main() {
  group('facilityKindForSubcategory', () {
    // 백엔드 실데이터는 한글 소분류로 내려온다(더현대 B2 기준 `화장실` 2건).
    test('한글 소분류를 종류로 바꾼다', () {
      expect(facilityKindForSubcategory('화장실'), FacilityKind.restroom);
      expect(facilityKindForSubcategory('엘리베이터'), FacilityKind.elevator);
    });

    // 옛 시드에는 영어 열거값이 남아 있다.
    test('영어 열거값도 받는다', () {
      expect(facilityKindForSubcategory('restroom'), FacilityKind.restroom);
      expect(facilityKindForSubcategory('ELEVATOR'), FacilityKind.elevator);
    });

    test('시설이 아니면 null이다', () {
      expect(facilityKindForSubcategory('캐주얼·스트리트'), isNull);
      expect(facilityKindForSubcategory(null), isNull);
      // 에스컬레이터는 이 목록에 없다 — 상세에 적는 것은 화장실·엘리베이터뿐이다.
      expect(facilityKindForSubcategory('에스컬레이터'), isNull);
    });
  });

  group('nearestFacilities', () {
    test('종류마다 가장 가까운 하나만 고른다', () {
      final result = nearestFacilities(
        reach: {'wc-far': _reach(50), 'wc-near': _reach(12), 'ev': _reach(30)},
        candidates: const [
          (kind: FacilityKind.restroom, nodeId: 'wc-far'),
          (kind: FacilityKind.restroom, nodeId: 'wc-near'),
          (kind: FacilityKind.elevator, nodeId: 'ev'),
        ],
      );

      expect(result.length, 2);
      expect(result[0].kind, FacilityKind.restroom);
      expect(result[0].reach.distanceM, 12);
      expect(result[1].kind, FacilityKind.elevator);
    });

    // 화면에서 줄 순서가 매장마다 바뀌면 눈이 매번 다시 찾아야 한다.
    test('화장실이 항상 엘리베이터보다 먼저 온다', () {
      final result = nearestFacilities(
        reach: {'ev': _reach(5), 'wc': _reach(90)},
        candidates: const [
          (kind: FacilityKind.elevator, nodeId: 'ev'),
          (kind: FacilityKind.restroom, nodeId: 'wc'),
        ],
      );

      expect(result.map((f) => f.kind).toList(), [
        FacilityKind.restroom,
        FacilityKind.elevator,
      ]);
    });

    // reachableFrom은 도달 못 한 노드에 키를 남기지 않는다. 갈 수 없는 화장실을
    // "가장 가깝다"고 적으면 안 된다.
    test('도달할 수 없는 후보는 버린다', () {
      final result = nearestFacilities(
        reach: {'wc-reachable': _reach(40)},
        candidates: const [
          (kind: FacilityKind.restroom, nodeId: 'wc-unreachable'),
          (kind: FacilityKind.restroom, nodeId: 'wc-reachable'),
        ],
      );

      expect(result.single.reach.distanceM, 40);
    });

    test('그 종류가 하나도 없으면 줄 자체를 만들지 않는다', () {
      final result = nearestFacilities(
        reach: {'ev': _reach(10)},
        candidates: const [(kind: FacilityKind.elevator, nodeId: 'ev')],
      );

      expect(result.length, 1);
      expect(result.single.kind, FacilityKind.elevator);
    });

    test('후보가 없으면 빈 목록이다', () {
      expect(
        nearestFacilities(reach: {'a': _reach(1)}, candidates: const []),
        isEmpty,
      );
    });
  });
}
