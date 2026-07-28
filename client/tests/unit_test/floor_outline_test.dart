import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:navigation_client/screens/outdoor_map/floor_outline.dart';

/// 야외 지도 위 "현재 층 외곽선" 규칙 테스트.
///
/// 검증 기준은 셋이다.
///   1. 실내에 들어가 있지 않으면 선이 없다.
///   2. 지상층은 건물 외곽선, 지하층은 그 층 도면 외곽선을 따른다.
///   3. 지하층 도면이 아직 없으면 건물 외곽선으로 폴백하지 **않고** 아무것도
///      그리지 않는다(잘못된 경계를 잠깐이라도 보여주지 않는다).
void main() {
  // 서로 확실히 구분되는 두 사각형. 어느 링이 선택됐는지 좌표로 판별한다.
  const building = [
    LatLng(37.5000, 127.0000),
    LatLng(37.5010, 127.0000),
    LatLng(37.5010, 127.0010),
    LatLng(37.5000, 127.0010),
  ];
  const basement = [
    LatLng(37.4990, 126.9990),
    LatLng(37.5020, 126.9990),
    LatLng(37.5020, 127.0020),
    LatLng(37.4990, 127.0020),
  ];

  group('isBasementFloor', () {
    test('B로 시작하는 숫자 층은 지하다', () {
      expect(isBasementFloor('B1'), isTrue);
      expect(isBasementFloor('B4'), isTrue);
      expect(isBasementFloor('b2'), isTrue);
    });

    test('지상층과 알 수 없는 라벨은 지하가 아니다', () {
      expect(isBasementFloor('1F'), isFalse);
      expect(isBasementFloor('6F'), isFalse);
      expect(isBasementFloor('BF'), isFalse);
      expect(isBasementFloor('LB1'), isFalse);
      expect(isBasementFloor(null), isFalse);
    });
  });

  group('floorOutlineRing', () {
    test('실내에 들어가 있지 않으면 그리지 않는다', () {
      expect(
        floorOutlineRing(
          indoorEntered: false,
          floor: '1F',
          buildingFootprint: building,
          floorFootprint: basement,
        ),
        isNull,
        reason: '야외 지도를 훑는 동안에는 건물 테두리를 그리지 않기로 했다',
      );
    });

    test('지상층은 건물 외곽선을 따른다', () {
      expect(
        floorOutlineRing(
          indoorEntered: true,
          floor: '1F',
          buildingFootprint: building,
          floorFootprint: basement,
        ),
        building,
      );
    });

    test('지하층은 그 층 도면의 외곽선을 따른다', () {
      expect(
        floorOutlineRing(
          indoorEntered: true,
          floor: 'B3',
          buildingFootprint: building,
          floorFootprint: basement,
        ),
        basement,
        reason: '지하는 건물 외곽선과 모양이 달라 건물 외곽선을 쓰면 도면과 어긋난다',
      );
    });

    test('지하층 도면이 아직 없으면 건물 외곽선으로 폴백하지 않는다', () {
      expect(
        floorOutlineRing(
          indoorEntered: true,
          floor: 'B3',
          buildingFootprint: building,
          floorFootprint: null,
        ),
        isNull,
      );
      expect(
        floorOutlineRing(
          indoorEntered: true,
          floor: 'B3',
          buildingFootprint: building,
          floorFootprint: const [],
        ),
        isNull,
      );
    });

    test('점이 3개 미만인 링은 폴리곤이 되지 않으므로 없는 것으로 본다', () {
      expect(
        floorOutlineRing(
          indoorEntered: true,
          floor: '1F',
          buildingFootprint: const [LatLng(37.5, 127.0), LatLng(37.5, 127.1)],
          floorFootprint: null,
        ),
        isNull,
      );
    });

    test('알 수 없는 층 라벨은 지상으로 보고 건물 외곽선을 쓴다', () {
      expect(
        floorOutlineRing(
          indoorEntered: true,
          floor: 'LOBBY',
          buildingFootprint: building,
          floorFootprint: basement,
        ),
        building,
      );
    });
  });
}
