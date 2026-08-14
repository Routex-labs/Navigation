import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:navigation_client/screens/outdoor_map/entry/floor_outline.dart';

/// 야외 지도 위 "현재 층 외곽선" 규칙 테스트.
///
/// 검증 기준은 셋이다.
///   1. 실내에 들어가 있지 않으면 선이 없다.
///   2. **어느 층이든** 그 층 도면의 외곽선을 따른다 — 1F와 2F는 서로 다른 링을
///      쓴다. 층마다 footprint가 다르므로(더현대 서울: 1F 20점, 2F 8점, B1 13점)
///      한 링을 돌려쓰면 타일이 그리는 바닥과 선이 어긋난다.
///   3. 그 층 도면이 아직 없으면 건물 외곽선으로 폴백하지 **않고** 아무것도
///      그리지 않는다(잘못된 경계를 잠깐이라도 보여주지 않는다).
void main() {
  // 서로 확실히 구분되는 세 개의 링. 어느 것이 선택됐는지 좌표로 판별한다.
  // 실제 데이터도 이런 관계다 — 지상층끼리는 비슷하지만 같지 않고, 지하는
  // 건물 밖까지 뻗는다.
  const firstFloor = [
    LatLng(37.5000, 127.0000),
    LatLng(37.5010, 127.0000),
    LatLng(37.5010, 127.0010),
    LatLng(37.5000, 127.0010),
  ];
  const secondFloor = [
    LatLng(37.5001, 127.0001),
    LatLng(37.5010, 127.0000),
    LatLng(37.5010, 127.0010),
    LatLng(37.5000, 127.0009),
  ];
  const basement = [
    LatLng(37.4990, 126.9990),
    LatLng(37.5020, 126.9990),
    LatLng(37.5020, 127.0020),
    LatLng(37.4990, 127.0020),
  ];

  group('floorOutlineRing', () {
    test('실내에 들어가 있지 않으면 그리지 않는다', () {
      expect(
        floorOutlineRing(indoorEntered: false, floorFootprint: firstFloor),
        isNull,
        reason: '야외 지도를 훑는 동안에는 건물 테두리를 그리지 않기로 했다',
      );
    });

    test('1F는 1F 도면의 외곽선을 따른다', () {
      expect(
        floorOutlineRing(indoorEntered: true, floorFootprint: firstFloor),
        firstFloor,
      );
    });

    test('2F는 2F 도면의 외곽선을 따른다 — 1F와 같은 링을 돌려쓰지 않는다', () {
      final ring = floorOutlineRing(
        indoorEntered: true,
        floorFootprint: secondFloor,
      );
      expect(ring, secondFloor);
      expect(
        ring,
        isNot(firstFloor),
        reason: '2층부터는 출구가 없어 1층과 외곽이 다르다 — 선도 그 층을 따라야 한다',
      );
    });

    test('지하층은 그 층 도면의 외곽선을 따른다', () {
      expect(
        floorOutlineRing(indoorEntered: true, floorFootprint: basement),
        basement,
        reason: '지하는 건물 외곽선 밖까지 뻗어 있어 건물 외곽선을 쓰면 도면과 어긋난다',
      );
    });

    test('층 도면이 아직 없으면 건물 외곽선으로 폴백하지 않는다', () {
      // 지상·지하 구분 없이 같은 규칙이다. 예전에는 지상층이 건물 외곽선으로
      // 폴백했는데, 그 건물 외곽선이 곧 1F라 2F 이상에서 계속 틀린 모양이었다.
      expect(
        floorOutlineRing(indoorEntered: true, floorFootprint: null),
        isNull,
      );
      expect(
        floorOutlineRing(indoorEntered: true, floorFootprint: const []),
        isNull,
      );
    });

    test('점이 3개 미만인 링은 폴리곤이 되지 않으므로 없는 것으로 본다', () {
      expect(
        floorOutlineRing(
          indoorEntered: true,
          floorFootprint: const [LatLng(37.5, 127.0), LatLng(37.5, 127.1)],
        ),
        isNull,
      );
    });
  });
}
