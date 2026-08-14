import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/screens/outdoor_map/camera/building_orientation.dart';
import 'package:navigation_client/map/camera/zoom_math.dart';

/// 건물을 세로로 세우는 계산의 검증.
///
/// 각도 계산은 부호 하나만 틀려도 **조용히 90도 어긋난다** — 화면에서는 "돌긴
/// 도는데 엉뚱하게 눕는다"로만 보여서, 눈으로 디버깅하면 오래 걸린다. 그래서
/// 방위를 아는 사각형을 직접 만들어 놓고 되찾아 오는지 확인한다.
void main() {
  const lat0 = 37.526; // 더현대 서울 위도
  const lng0 = 126.928;
  const metersPerDegLat = 111320.0;
  final metersPerDegLng = metersPerDegLat * math.cos(lat0 * math.pi / 180);

  /// 중심 [lat0], [lng0]에 놓인 [widthM] x [heightM] 직사각형을 방위각
  /// [rotationDeg]만큼 **시계방향**으로 돌린 네 꼭짓점.
  ///
  /// 돌리기 전에는 heightM 변이 남북(세로)이다. 즉 rotationDeg가 0이면 긴 변이
  /// 북쪽을 향한다(방위각 0).
  List<ll.LatLng> rect({
    required double widthM,
    required double heightM,
    required double rotationDeg,
  }) {
    final rad = rotationDeg * math.pi / 180;
    // 방위각은 북 기준 시계방향이다. (동, 북) 평면에서 시계방향 회전은
    // 동' = 동·cos + 북·sin, 북' = -동·sin + 북·cos.
    final c = math.cos(rad);
    final s = math.sin(rad);
    final halfW = widthM / 2;
    final halfH = heightM / 2;
    const corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)];
    return [
      for (final (sx, sy) in corners)
        () {
          final east = sx * halfW;
          final north = sy * halfH;
          final e2 = east * c + north * s;
          final n2 = -east * s + north * c;
          return ll.LatLng(
            lat0 + n2 / metersPerDegLat,
            lng0 + e2 / metersPerDegLng,
          );
        }(),
    ];
  }

  group('최소 넓이 상자', () {
    test('점이 3개 미만이면 상자가 없다', () {
      expect(minAreaBoxFor(const []), isNull);
      expect(minAreaBoxFor([ll.LatLng(lat0, lng0)]), isNull);
      expect(
        minAreaBoxFor([ll.LatLng(lat0, lng0), ll.LatLng(lat0 + 0.001, lng0)]),
        isNull,
      );
    });

    test('돌아가지 않은 사각형은 변 길이와 방위를 그대로 돌려준다', () {
      final box = minAreaBoxFor(
        rect(widthM: 150, heightM: 300, rotationDeg: 0),
      )!;
      expect(box.longSideM, closeTo(300, 1.0));
      expect(box.shortSideM, closeTo(150, 1.0));
      // 긴 변이 남북이므로 방위각 0(북).
      expect(box.longAxisAzimuthDeg, closeTo(0, 0.6));
    });

    test('돌려 놓은 사각형의 방위를 되찾는다', () {
      // 더현대 서울의 실제 회전각(약 53도)을 포함해 여러 각도로 확인한다.
      for (final deg in [15.0, 37.0, 53.0, 90.0, 128.0, 165.0]) {
        final box = minAreaBoxFor(
          rect(widthM: 148, heightM: 295, rotationDeg: deg),
        )!;
        expect(box.longSideM, closeTo(295, 2.0), reason: '$deg도에서 긴 변 길이가 틀렸다');
        expect(
          box.shortSideM,
          closeTo(148, 2.0),
          reason: '$deg도에서 짧은 변 길이가 틀렸다',
        );
        // 축은 0~180으로 접히므로 deg를 같은 방식으로 접어 비교한다.
        final expected = deg % 180;
        expect(
          box.longAxisAzimuthDeg,
          closeTo(expected, 1.0),
          reason:
              '$deg도로 돌린 건물의 긴 축이 '
              '${box.longAxisAzimuthDeg.toStringAsFixed(1)}도로 나왔다 — '
              '부호가 뒤집혔거나 축이 뒤바뀌었다',
        );
      }
    });

    test('정북 정렬 상자보다 작다 — 이게 돌려 재는 이유다', () {
      // 53도 돌아앉은 건물을 정북 기준으로 재면 실제보다 훨씬 큰 상자가 나온다.
      // 그 상자에 맞춰 확대하면 도면이 그만큼 작게 들어온다.
      final footprint = rect(widthM: 148, heightM: 295, rotationDeg: 53);
      final box = minAreaBoxFor(footprint)!;

      var minLat = double.infinity, maxLat = double.negativeInfinity;
      var minLng = double.infinity, maxLng = double.negativeInfinity;
      for (final p in footprint) {
        minLat = math.min(minLat, p.latitude);
        maxLat = math.max(maxLat, p.latitude);
        minLng = math.min(minLng, p.longitude);
        maxLng = math.max(maxLng, p.longitude);
      }
      final northAlignedWidth = (maxLng - minLng) * metersPerDegLng;
      expect(
        box.shortSideM,
        lessThan(northAlignedWidth),
        reason: '돌려 잰 짧은 변이 정북 정렬 폭보다 작아야 화면을 더 채울 수 있다',
      );
    });

    test('중심은 상자의 한가운데다', () {
      // 대칭 사각형이면 상자 중심 = 도형 중심이다. 여기서 어긋나면 아래의
      // 비대칭 검증이 무슨 값을 재는지 알 수 없게 된다.
      for (final deg in [0.0, 53.0, 128.0]) {
        final box = minAreaBoxFor(
          rect(widthM: 148, heightM: 295, rotationDeg: deg),
        )!;
        expect(box.center.latitude, closeTo(lat0, 1e-6), reason: '$deg도');
        expect(box.center.longitude, closeTo(lng0, 1e-6), reason: '$deg도');
      }
    });

    test('비대칭 도형에서 상자 중심은 정북 bbox 중심과 다르다', () {
      // **이게 도면이 한쪽으로 밀리던 자리다.** 배율은 돌아간 상자로 재고 위치는
      // 정북 bbox 중심으로 잡으면, 두 중심의 차이만큼 도면이 프레임에서 밀린다.
      // 사방 여백이 7%뿐이라(_floorFitFillRatio 0.86) 그 차이가 곧 잘림이 된다.
      // 53도 돌아간 사각형에 한쪽 모서리만 튀어나온 꼬리를 붙여 비대칭을 만든다.
      final footprint = [
        ...rect(widthM: 148, heightM: 295, rotationDeg: 53),
        ll.LatLng(lat0, lng0 + 200 / metersPerDegLng),
      ];
      final box = minAreaBoxFor(footprint)!;

      var minLat = double.infinity, maxLat = double.negativeInfinity;
      var minLng = double.infinity, maxLng = double.negativeInfinity;
      for (final p in footprint) {
        minLat = math.min(minLat, p.latitude);
        maxLat = math.max(maxLat, p.latitude);
        minLng = math.min(minLng, p.longitude);
        maxLng = math.max(maxLng, p.longitude);
      }
      final bboxCenterLat = (minLat + maxLat) / 2;
      final bboxCenterLng = (minLng + maxLng) / 2;
      final gapM = math.sqrt(
        math.pow((box.center.latitude - bboxCenterLat) * metersPerDegLat, 2) +
            math.pow(
              (box.center.longitude - bboxCenterLng) * metersPerDegLng,
              2,
            ),
      );
      expect(
        gapM,
        greaterThan(5),
        reason: '두 중심이 사실상 같으면 이 테스트가 회귀를 못 잡는다',
      );

      // 상자 중심에서 재면 도형이 상자 안에 대칭으로 들어온다 — 즉 어느 쪽으로도
      // 상자 절반보다 멀리 있는 점이 없다.
      final rad = box.longAxisAzimuthDeg * math.pi / 180;
      for (final p in footprint) {
        final east =
            (p.longitude - box.center.longitude) * metersPerDegLng;
        final north = (p.latitude - box.center.latitude) * metersPerDegLat;
        // 긴 축 방향 성분과 그 직교 성분.
        final along = east * math.sin(rad) + north * math.cos(rad);
        final across = east * math.cos(rad) - north * math.sin(rad);
        expect(along.abs(), lessThanOrEqualTo(box.longSideM / 2 + 1e-6));
        expect(across.abs(), lessThanOrEqualTo(box.shortSideM / 2 + 1e-6));
      }
    });
  });

  group('그려지는 것까지 덮는 상자(covering)', () {
    test('외곽선 밖의 점까지 덮도록 넓어진다', () {
      // 더현대 서울 1F가 이 모양이다 — 매장 폴리곤이 층 외곽선 위아래로
      // 12 m·19 m 튀어나와 있어, 외곽선에만 맞추면 그만큼이 화면 밖에 남는다.
      final footprint = rect(widthM: 148, heightM: 295, rotationDeg: 0);
      final bare = minAreaBoxFor(footprint)!;
      // 긴 축(남북)으로 한쪽에만 20 m 더 나간 점.
      final outside = ll.LatLng(
        lat0 + (295 / 2 + 20) / metersPerDegLat,
        lng0,
      );
      final box = minAreaBoxFor(
        footprint,
        covering: [...footprint, outside],
      )!;
      expect(box.longSideM, closeTo(bare.longSideM + 20, 1.0));
      expect(box.shortSideM, closeTo(bare.shortSideM, 1.0));
      // 한쪽으로만 넓어졌으므로 중심도 그 절반만큼 그쪽으로 움직인다.
      expect(
        (box.center.latitude - lat0) * metersPerDegLat,
        closeTo(10, 1.0),
      );
    });

    test('각도는 외곽선이 정한다 — covering이 축을 흔들지 않는다', () {
      // 축은 카메라를 세우는 기준이라(portraitBearingFor), 층마다 매장 배치가
      // 조금씩 다른 것 때문에 몇 도씩 돌면 층을 바꿀 때마다 지도가 미세하게
      // 회전한다. covering은 크기만 넓힌다.
      final footprint = rect(widthM: 148, heightM: 295, rotationDeg: 53);
      final bare = minAreaBoxFor(footprint)!;
      // 축을 90도쯤 뒤집고 싶어할 만큼 옆으로 길게 퍼진 점들을 covering에 넣는다.
      final wide = [
        for (final d in [-200.0, -100.0, 100.0, 200.0])
          ll.LatLng(lat0, lng0 + d / metersPerDegLng),
      ];
      final box = minAreaBoxFor(footprint, covering: [...footprint, ...wide])!;
      expect(
        box.longAxisAzimuthDeg,
        closeTo(bare.longAxisAzimuthDeg, 1e-9),
        reason: 'covering이 축을 바꾸면 층을 오갈 때 지도가 돈다',
      );
    });

    test('covering이 비어 있으면 외곽선 자신을 덮는다(예전 동작)', () {
      final footprint = rect(widthM: 148, heightM: 295, rotationDeg: 53);
      final bare = minAreaBoxFor(footprint)!;
      final same = minAreaBoxFor(footprint, covering: const [])!;
      expect(same.longSideM, closeTo(bare.longSideM, 1e-9));
      expect(same.shortSideM, closeTo(bare.shortSideM, 1e-9));
      expect(same.center.latitude, closeTo(bare.center.latitude, 1e-12));
      expect(same.center.longitude, closeTo(bare.center.longitude, 1e-12));
    });
  });

  group('세로로 세우는 bearing', () {
    test('긴 축 방위를 그대로 위로 올린다', () {
      // MapLibre bearing은 "화면 위에 오는 나침반 방향"이다.
      expect(
        portraitBearingFor(longAxisAzimuthDeg: 53, currentBearing: 0),
        closeTo(53, 0.001),
      );
    });

    test('덜 도는 쪽을 고른다', () {
      // 축은 선이라 170도와 350도가 같은 세로 방향을 만든다. 정북에서
      // 출발하면 170도를 도는 것보다 -10도(=350) 쪽이 훨씬 가깝다.
      expect(
        portraitBearingFor(longAxisAzimuthDeg: 170, currentBearing: 0),
        closeTo(350, 0.001),
      );
      // 반대로 지금 카메라가 이미 그쪽을 보고 있으면 그대로 둔다.
      expect(
        portraitBearingFor(longAxisAzimuthDeg: 170, currentBearing: 175),
        closeTo(170, 0.001),
      );
    });

    test('카메라 각도를 모르면 정북에서 출발한다고 본다', () {
      expect(
        portraitBearingFor(longAxisAzimuthDeg: 170, currentBearing: null),
        closeTo(350, 0.001),
      );
      expect(
        portraitBearingFor(longAxisAzimuthDeg: 170, currentBearing: double.nan),
        closeTo(350, 0.001),
      );
    });

    test('언제나 0~360 안에 있다', () {
      for (var a = 0.0; a < 180; a += 7) {
        for (final cur in [0.0, 90.0, 200.0, 359.0]) {
          final b = portraitBearingFor(
            longAxisAzimuthDeg: a,
            currentBearing: cur,
          );
          expect(b, greaterThanOrEqualTo(0));
          expect(b, lessThan(360));
        }
      }
    });

    test('고른 bearing은 긴 축을 세로로 세운다', () {
      // 두 후보(θ, θ+180) 중 무엇을 골랐든, 긴 축과 화면 세로가 나란해야 한다.
      for (var a = 0.0; a < 180; a += 11) {
        final b = portraitBearingFor(longAxisAzimuthDeg: a, currentBearing: 0);
        final diff = (b - a) % 180;
        expect(
          diff < 0.001 || (180 - diff) < 0.001,
          isTrue,
          reason: '축 $a도에 대해 bearing $b도는 세로 정렬이 아니다',
        );
      }
    });
  });
  group('방위각 방향으로 밀기', () {
    // 도면을 chrome이 가리지 않는 띠 한가운데로 내릴 때 쓴다. 지도가 돌아가
    // 있으면 "화면 위"가 북쪽이 아니므로, 방위각을 그대로 따라가야 한다.
    const origin = ll.LatLng(lat0, lng0);

    double metersBetween(ll.LatLng a, ll.LatLng b) {
      final dNorth = (b.latitude - a.latitude) * metersPerDegLat;
      final dEast = (b.longitude - a.longitude) * metersPerDegLng;
      return math.sqrt(dNorth * dNorth + dEast * dEast);
    }

    test('북쪽(0도)으로 밀면 위도만 오른다', () {
      final moved = offsetByMeters(origin, azimuthDeg: 0, meters: 100);
      expect(moved.longitude, closeTo(lng0, 1e-9));
      expect((moved.latitude - lat0) * metersPerDegLat, closeTo(100, 0.5));
    });

    test('동쪽(90도)으로 밀면 경도만 오른다', () {
      final moved = offsetByMeters(origin, azimuthDeg: 90, meters: 100);
      expect(moved.latitude, closeTo(lat0, 1e-9));
      expect((moved.longitude - lng0) * metersPerDegLng, closeTo(100, 0.5));
    });

    test('어느 방위로든 이동 거리는 같다', () {
      for (var az = 0.0; az < 360; az += 23) {
        final moved = offsetByMeters(origin, azimuthDeg: az, meters: 250);
        expect(
          metersBetween(origin, moved),
          closeTo(250, 1.0),
          reason: '$az도로 250 m 밀었는데 거리가 다르다 — 경도 축 환산이 틀렸다',
        );
      }
    });

    test('0 m를 밀면 제자리다', () {
      final moved = offsetByMeters(origin, azimuthDeg: 137, meters: 0);
      expect(moved.latitude, closeTo(lat0, 1e-12));
      expect(moved.longitude, closeTo(lng0, 1e-12));
    });

    test('음수 거리는 반대 방향이다', () {
      final back = offsetByMeters(origin, azimuthDeg: 53, meters: -80);
      final forward = offsetByMeters(origin, azimuthDeg: 233, meters: 80);
      expect(back.latitude, closeTo(forward.latitude, 1e-9));
      expect(back.longitude, closeTo(forward.longitude, 1e-9));
    });
  });

  group('경로 상자', () {
    const minSideM = 12.0;

    /// [lat0], [lng0]에서 방위각 [azimuthDeg] 쪽으로 [lengthM]만큼 뻗은 직선
    /// 경로. 점 개수는 [pointCount].
    List<ll.LatLng> straightRoute({
      required double lengthM,
      required double azimuthDeg,
      int pointCount = 2,
    }) {
      final rad = azimuthDeg * math.pi / 180;
      return [
        for (var i = 0; i < pointCount; i++)
          () {
            final d = lengthM * i / (pointCount - 1);
            return ll.LatLng(
              lat0 + d * math.cos(rad) / metersPerDegLat,
              lng0 + d * math.sin(rad) / metersPerDegLng,
            );
          }(),
      ];
    }

    test('점이 2개 미만이면 상자가 없다', () {
      expect(routeBoxFor(const [], minSideM: minSideM), isNull);
      expect(
        routeBoxFor([ll.LatLng(lat0, lng0)], minSideM: minSideM),
        isNull,
      );
    });

    test('점이 둘뿐인 곧은 경로도 상자를 만든다', () {
      // [minAreaBoxFor]는 3점을 요구해 여기서 null을 낸다. 복도 한 구간짜리
      // 경로가 딱 이 모양이라, 안내 시작 연출이 통째로 사라지는 자리였다.
      final points = straightRoute(lengthM: 200, azimuthDeg: 53);
      expect(minAreaBoxFor(points), isNull);
      expect(routeBoxFor(points, minSideM: minSideM), isNotNull);
    });

    test('곧은 경로의 긴 축은 경로가 뻗은 방향이다', () {
      for (final az in [0.0, 31.0, 53.0, 90.0, 147.0]) {
        final box = routeBoxFor(
          straightRoute(lengthM: 180, azimuthDeg: az),
          minSideM: minSideM,
        )!;
        expect(
          box.longSideM,
          closeTo(180, 2.0),
          reason: '$az도에서 경로 길이가 긴 변으로 안 나왔다',
        );
        expect(
          box.longAxisAzimuthDeg,
          closeTo(az % 180, 0.6),
          reason: '$az도에서 방위가 어긋났다 — 카메라가 그만큼 잘못 돈다',
        );
      }
    });

    test('일직선 경로의 짧은 변을 하한이 받친다', () {
      // **이게 없으면 zoom이 발산한다.** 짧은 변 0은 zoomToFitWidth의
      // log(가용폭 / 0) = 무한대로 이어져 지도가 사라진다.
      final box = routeBoxFor(
        straightRoute(lengthM: 240, azimuthDeg: 53, pointCount: 9),
        minSideM: minSideM,
      )!;
      expect(box.shortSideM, closeTo(minSideM, 1e-6));
    });

    test('받친 상자는 유한한 zoom을 만든다', () {
      final box = routeBoxFor(
        straightRoute(lengthM: 240, azimuthDeg: 53, pointCount: 9),
        minSideM: minSideM,
      )!;
      final zoom = zoomToFitRotatedBox(
        widthMeters: box.shortSideM,
        heightMeters: box.longSideM,
        viewportWidthPx: 360,
        viewportHeightPx: 500,
        latitude: lat0,
      );
      expect(zoom.isFinite, isTrue, reason: '하한을 뚫고 zoom이 발산했다');
    });

    test('아주 짧은 경로는 두 변 모두 하한으로 받친다', () {
      final box = routeBoxFor(
        straightRoute(lengthM: 3, azimuthDeg: 53),
        minSideM: minSideM,
      )!;
      expect(box.longSideM, closeTo(minSideM, 1e-6));
      expect(box.shortSideM, closeTo(minSideM, 1e-6));
    });

    test('넓이가 있는 경로는 하한이 건드리지 않는다', () {
      // ㄱ자로 꺾인 경로. 두 변 모두 하한보다 크므로 [minAreaBoxFor]와 같아야
      // 한다 — 하한이 정상 입력까지 부풀리면 경로가 필요 이상으로 작게 보인다.
      final corner = [
        ll.LatLng(lat0, lng0),
        ll.LatLng(lat0 + 120 / metersPerDegLat, lng0),
        ll.LatLng(lat0 + 120 / metersPerDegLat, lng0 + 80 / metersPerDegLng),
      ];
      final raw = minAreaBoxFor(corner)!;
      final box = routeBoxFor(corner, minSideM: minSideM)!;
      expect(box.longSideM, closeTo(raw.longSideM, 1e-9));
      expect(box.shortSideM, closeTo(raw.shortSideM, 1e-9));
      expect(box.longAxisAzimuthDeg, closeTo(raw.longAxisAzimuthDeg, 1e-9));
    });

    test('하한이 변을 받쳐도 중심은 그대로다', () {
      // 변만 양쪽으로 넓히는 것이므로 경로가 화면 한가운데에 남아야 한다.
      final points = straightRoute(lengthM: 3, azimuthDeg: 53);
      final box = routeBoxFor(points, minSideM: minSideM)!;
      final midLat = (points.first.latitude + points.last.latitude) / 2;
      final midLng = (points.first.longitude + points.last.longitude) / 2;
      expect(box.center.latitude, closeTo(midLat, 1e-9));
      expect(box.center.longitude, closeTo(midLng, 1e-9));
    });
  });
}
