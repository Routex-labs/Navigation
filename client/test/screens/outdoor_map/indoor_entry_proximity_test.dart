import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/screens/outdoor_map/indoor_entry_proximity.dart';

/// 실내 진입 근접 판정 테스트.
///
/// 지키려는 증상: 실내 도면이 있는 건물이 주변에 없는데도 지도를 확대하면 실내
/// 모드로 전환돼, 보여줄 도면 없이 층 선택기·위치 지정 버튼만 뜨던 문제.
/// 판정을 지도 컨트롤러에서 떼어낸 순수 함수로 두고 여기서 고정한다.
void main() {
  /// 데모 건물(assets/mock/sample_building.json)의 footprint. 위도 폭
  /// 0.0004도(약 44 m), 경도 폭 0.0006도(이 위도에서 약 53 m)인 사각형이다.
  const footprint = <ll.LatLng>[
    ll.LatLng(37.5663, 126.9777),
    ll.LatLng(37.5667, 126.9777),
    ll.LatLng(37.5667, 126.9783),
    ll.LatLng(37.5663, 126.9783),
  ];

  const center = ll.LatLng(37.5665, 126.9780);

  // 위도 1도 = 111320 m 기준. 경도는 이 위도에서 cos(37.5665) 배(약 88231 m/도).
  const metersPerDegreeLat = 111320.0;
  const metersPerDegreeLng = 88231.0;

  ll.LatLng northOf(double meters) =>
      ll.LatLng(37.5667 + meters / metersPerDegreeLat, 126.9780);
  ll.LatLng eastOf(double meters) =>
      ll.LatLng(37.5665, 126.9783 + meters / metersPerDegreeLng);

  group('폴리곤 폭', () {
    // 실내 진입 임계값을 화면 폭에 맞출 때 "이 건물이 화면에 담기는 zoom"의
    // 입력이다. 여기가 틀리면 좁은 화면의 진입 임계값이 통째로 어긋난다.
    test('경도 폭을 이 위도의 미터로 환산한다', () {
      // 경도 0.0006도 x 88231 m/도 ≈ 53 m.
      expect(polygonWidthMeters(footprint), closeTo(52.9, 0.5));
    });

    test('위도가 높아질수록 같은 경도 폭이 좁아진다', () {
      const north = <ll.LatLng>[
        ll.LatLng(60.0000, 126.9777),
        ll.LatLng(60.0004, 126.9777),
        ll.LatLng(60.0004, 126.9783),
        ll.LatLng(60.0000, 126.9783),
      ];
      expect(
        polygonWidthMeters(north),
        lessThan(polygonWidthMeters(footprint)),
      );
    });

    test('점이 3개 미만이면 0이다', () {
      // 호출부는 0을 "보정 근거 없음"으로 읽고 기본 임계값을 그대로 쓴다.
      expect(polygonWidthMeters(const []), 0);
      expect(
        polygonWidthMeters(const [
          ll.LatLng(37.5663, 126.9777),
          ll.LatLng(37.5667, 126.9783),
        ]),
        0,
      );
    });
  });

  group('폴리곤 내부 판정', () {
    test('건물 중심은 내부다', () {
      expect(isPointInPolygon(center, footprint), isTrue);
    });

    test('건물 밖 좌표는 내부가 아니다', () {
      expect(isPointInPolygon(northOf(30), footprint), isFalse);
      expect(isPointInPolygon(eastOf(30), footprint), isFalse);
    });

    test('점이 3개 미만이면 판정하지 않는다', () {
      expect(isPointInPolygon(center, const []), isFalse);
      expect(
        isPointInPolygon(center, const [
          ll.LatLng(37.5663, 126.9777),
          ll.LatLng(37.5667, 126.9777),
        ]),
        isFalse,
      );
    });
  });

  group('폴리곤까지의 거리', () {
    test('내부면 0이다', () {
      expect(metersToPolygon(center, footprint), 0);
    });

    test('북쪽 50 m는 약 50 m로 나온다', () {
      expect(metersToPolygon(northOf(50), footprint), closeTo(50, 1.0));
    });

    test('경도 방향 거리에 cos(위도)를 반영한다', () {
      // 반영하지 않으면 같은 좌표가 약 88 m로 나와 26% 부풀려진다.
      // 서울 위도에서 동서 거리를 남북과 같은 척도로 재던 실수를 잡는 케이스다.
      expect(metersToPolygon(eastOf(70), footprint), closeTo(70, 1.0));
    });

    test('꼭짓점이 아니라 변까지의 거리를 잰다', () {
      // 위쪽 변(길이 약 53 m) 중점에서 10 m 위. 가장 가까운 꼭짓점까지는 약
      // 28 m지만 변까지는 10 m다. 꼭짓점만 비교하면 긴 벽면 가운데를 확대한
      // 사용자가 "건물이 멀다"고 잘못 판정된다.
      final aboveEdgeMidpoint = northOf(10);
      expect(metersToPolygon(aboveEdgeMidpoint, footprint), closeTo(10, 1.0));
      expect(
        isIndoorBuildingNearCamera(
          camera: aboveEdgeMidpoint,
          footprint: footprint,
          radiusMeters: 15,
        ),
        isTrue,
        reason: '변까지 10 m인데 꼭짓점 거리(28 m)로 판정하면 false가 된다',
      );
    });
  });

  group('실내 진입 근접 판정', () {
    test('건물 안에서는 가깝다', () {
      expect(
        isIndoorBuildingNearCamera(camera: center, footprint: footprint),
        isTrue,
      );
    });

    test('벽 바로 밖(톨러런스 안)도 가깝다', () {
      expect(
        isIndoorBuildingNearCamera(camera: northOf(50), footprint: footprint),
        isTrue,
      );
      expect(
        isIndoorBuildingNearCamera(camera: eastOf(70), footprint: footprint),
        isTrue,
      );
    });

    test('톨러런스를 넘으면 멀다', () {
      expect(
        isIndoorBuildingNearCamera(camera: northOf(200), footprint: footprint),
        isFalse,
      );
      // 완전히 다른 지역(강남역). 여기를 확대해도 실내 모드가 되면 안 된다.
      expect(
        isIndoorBuildingNearCamera(
          camera: const ll.LatLng(37.4979, 127.0276),
          footprint: footprint,
        ),
        isFalse,
      );
    });

    test('건물을 아직 로드하지 못했으면 항상 멀다', () {
      // 이게 false여야 앱 시작 직후 확대해도 빈 실내 모드로 들어가지 않는다.
      expect(
        isIndoorBuildingNearCamera(camera: center, footprint: null),
        isFalse,
      );
      expect(
        isIndoorBuildingNearCamera(camera: center, footprint: const []),
        isFalse,
      );
    });

    test('카메라 위치를 모르면 진입하지 않는 쪽으로 판정한다', () {
      expect(
        isIndoorBuildingNearCamera(camera: null, footprint: footprint),
        isFalse,
      );
    });

    test('톨러런스는 진입 임계값 화면 반폭보다 크고, 한 블록보다는 작다', () {
      // 값을 옮길 때 근거를 잃지 않도록 범위로 고정한다. 60 m는 zoom 17.5에서
      // 폭 360 px 화면의 반폭이고, 150 m를 넘어가면 건물이 화면에 없는데도
      // 실내로 들어가기 시작한다.
      expect(indoorEntryProximityMeters, greaterThan(60));
      expect(indoorEntryProximityMeters, lessThan(150));
    });
  });
  group('실내에서 밖을 탭해 나가는 판정 — 오탭으로 쫓겨나지 않는다', () {
    // 이 그룹이 지키는 증상: 벽에 붙은 매장을 누르려다 손가락이 외곽선을 살짝
    // 넘겨 실내가 통째로 닫히던 문제. 되돌리려면 건물을 다시 찾아 탭해야 해서
    // 오조작 비용이 크다.

    test('건물 안을 누르면 나가지 않는다', () {
      expect(
        isTapOutsideBuildingForExit(point: center, footprint: footprint),
        isFalse,
      );
    });

    test('외곽선 바로 바깥(여유 폭 안)은 오탭으로 보고 나가지 않는다', () {
      for (final m in [0.5, 3.0, 8.0, 14.0]) {
        expect(
          isTapOutsideBuildingForExit(point: northOf(m), footprint: footprint),
          isFalse,
          reason: '외곽선에서 ${m}m 바깥 탭에 실내가 닫히면 매장을 누르려다 쫓겨난다',
        );
        expect(
          isTapOutsideBuildingForExit(point: eastOf(m), footprint: footprint),
          isFalse,
          reason: '동쪽 ${m}m — 경도 축 환산이 틀리면 여기서만 어긋난다',
        );
      }
    });

    test('건물에서 눈에 띄게 떨어진 곳을 누르면 나간다', () {
      for (final m in [20.0, 50.0, 200.0]) {
        expect(
          isTapOutsideBuildingForExit(point: northOf(m), footprint: footprint),
          isTrue,
          reason: '${m}m 바깥까지 못 나가면 탭으로 나가는 탈출 경로가 죽는다',
        );
      }
    });

    test('외곽선을 모르면 나가지 않는다', () {
      // 아직 건물을 못 받았거나 외곽선이 없다. 판정 근거가 없을 때는 잘못
      // 나가는 쪽보다 잘못 머무는 쪽이 싸다 — 머무는 것은 한 번 더 탭하면
      // 되지만, 나간 것은 건물을 다시 찾아야 한다.
      expect(
        isTapOutsideBuildingForExit(point: northOf(500), footprint: null),
        isFalse,
      );
      expect(
        isTapOutsideBuildingForExit(
          point: northOf(500),
          footprint: const [ll.LatLng(37.5663, 126.9777)],
        ),
        isFalse,
      );
    });

    test('여유 폭은 건물을 삼킬 만큼 크지 않다', () {
      // 여유 폭이 건물 반폭보다 크면 건물 반대편을 눌러도 "안쪽"으로 판정돼
      // 탭으로 나가는 길이 사실상 사라진다.
      expect(
        indoorExitTapMarginMeters,
        lessThan(polygonWidthMeters(footprint) / 2),
      );
    });
  });
}
