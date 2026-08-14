/// 랜드마크로 실내 도면의 **북쪽**을 정하는 orthogonal Procrustes 맞춤.
///
/// 여기가 틀리면 도면 전체가 돌아간 채로 그려지고, 사용자는 방위선을 믿고
/// 반대 방향으로 걷는다. 그런데 화면에는 아무 오류도 안 뜬다 — 각도는 항상
/// 하나 나오기 때문이다. 그래서 **값**이 아니라 **불변성**을 못 박는다.
///
/// 도면을 통째로 옮기거나 확대해도 북쪽은 그대로여야 하고, 통째로 돌리면
/// 정확히 그만큼 돌아야 한다. 셋 중 하나라도 깨지면 맞춤 수식이 잘못된 것이다.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/features/debug_mode/landmark_cardinal_calibration.dart';
import 'package:navigation_client/models/floor_plan.dart';

const _buildingId = 'thehyundai-seoul';

/// 맞춤이 요구하는 다섯 랜드마크. 하나라도 빠지면 내장 좌표로 폴백한다.
const _names = ['보테가 베네타', '불가리', '티파니앤코', '루이비통', '프라다'];

/// 실제 더현대 1F 매장 중심에 가까운 배치. 값 자체보다 **서로의 상대 위치**가
/// 중요하다 — 맞춤이 보는 것은 그것뿐이다.
const _centroids = <LatLng>[
  LatLng(37.52570, 126.92830),
  LatLng(37.52562, 126.92845),
  LatLng(37.52585, 126.92861),
  LatLng(37.52573, 126.92885),
  LatLng(37.52559, 126.92878),
];

StorePolygon _store(String name, LatLng centroid) =>
    StorePolygon(id: name, name: name, polygon: [centroid], centroid: centroid);

/// [transform]으로 중심을 옮긴 도면을 만든다.
FloorPlan _plan({
  LatLng Function(LatLng)? transform,
  List<String> names = _names,
}) {
  final move = transform ?? (p) => p;
  return FloorPlan(
    pois: const [],
    stores: [
      for (var i = 0; i < names.length; i++)
        _store(names[i], move(_centroids[i])),
    ],
  );
}

/// 위경도를 [origin] 기준으로 [deg]만큼 돌린다.
///
/// 경도는 위도에 따라 미터 환산이 달라지므로(cos), 맞춤이 쓰는 것과 같은
/// 보정을 넣어야 "화면에서 본 회전"과 같아진다.
LatLng Function(LatLng) _rotate(double deg, {required LatLng origin}) {
  final rad = deg * math.pi / 180;
  final cosA = math.cos(rad);
  final sinA = math.sin(rad);
  final lonScale = math.cos(origin.latitude * math.pi / 180);
  return (p) {
    final x = (p.longitude - origin.longitude) * lonScale;
    final y = p.latitude - origin.latitude;
    // 화면 좌표(동쪽 +x, 북쪽 +y)에서 시계 방향으로 [deg]만큼.
    final rx = x * cosA + y * sinA;
    final ry = -x * sinA + y * cosA;
    return LatLng(origin.latitude + ry, origin.longitude + rx / lonScale);
  };
}

/// 각도 차이를 -180~180으로 접는다.
double _angleDelta(double a, double b) {
  final raw = (a - b) % 360;
  return raw > 180 ? raw - 360 : (raw < -180 ? raw + 360 : raw);
}

/// 소스에 박혀 있는 **레퍼런스 캡처 픽셀 좌표**(동쪽 +x, 북쪽 +y).
///
/// 네이버 지도 북고정 캡처에서 읽은 값이라, 이 좌표계에서 북쪽은 정의상 +y다.
const _referencePx = <(double east, double north)>[
  (1512.154324, 1385.826808), // 보테가 베네타
  (1602.193920, 1245.499904), // 불가리
  (1999.433648, 1327.886856), // 티파니앤코
  (2012.675944, 1020.994392), // 루이비통
  (1800.813784, 952.001024), // 프라다
];

const _origin = LatLng(37.52570, 126.92830);

/// 레퍼런스 픽셀 좌표를 **그대로** 도면 위경도로 옮긴 계획.
///
/// 이렇게 만들면 도면 좌표계와 레퍼런스 좌표계가 (평행이동·축척을 빼면) 같아진다.
/// 그러면 맞춤이 찾아야 할 회전은 0이고, **북쪽은 정확히 0°여야 한다.**
/// 정답을 아는 입력이라 상수 오차도 반사 뒤집기도 여기서 걸린다.
FloorPlan _referencePlan({double rotateDeg = 0}) {
  const metersPerPx = 0.05;
  const degPerMeter = 1 / 111320.0;
  final lonScale = math.cos(_origin.latitude * math.pi / 180);
  final rotate = _rotate(rotateDeg, origin: _origin);
  return FloorPlan(
    pois: const [],
    stores: [
      for (var i = 0; i < _names.length; i++)
        _store(
          _names[i],
          rotate(
            LatLng(
              // 북쪽 픽셀이 커질수록 위도가 커진다.
              _origin.latitude + _referencePx[i].$2 * metersPerPx * degPerMeter,
              _origin.longitude +
                  _referencePx[i].$1 * metersPerPx * degPerMeter / lonScale,
            ),
          ),
        ),
    ],
  );
}

void main() {
  group('건물 판정', () {
    test('다른 건물이면 null이다', () {
      // 랜드마크는 더현대 1F 캡처에서만 뽑았다. 다른 건물에 그 각도를 쓰면
      // 근거 없는 방위선을 그리게 된다.
      expect(cardinalCalibrationForBuilding('somewhere-else'), isNull);
      expect(
        cardinalCalibrationForBuilding('somewhere-else', floorPlan: _plan()),
        isNull,
      );
    });

    test('도면이 없으면 내장 랜드마크로 계산한다', () {
      final result = cardinalCalibrationForBuilding(_buildingId);
      expect(result, isNotNull);
      expect(result!.landmarkCount, 5);
      expect(result.northMapBearingDeg, inInclusiveRange(0, 360));
    });

    test('랜드마크가 하나라도 없으면 내장 좌표로 폴백한다', () {
      final missing = cardinalCalibrationForBuilding(
        _buildingId,
        floorPlan: _plan(names: _names.sublist(0, 4)),
      );
      final builtin = cardinalCalibrationForBuilding(_buildingId);
      expect(
        missing!.northMapBearingDeg,
        closeTo(builtin!.northMapBearingDeg, 1e-9),
      );
    });
  });

  group('불변성 — 여기가 깨지면 도면이 돌아간 채로 그려진다', () {
    test('도면을 통째로 옮겨도 북쪽은 그대로다', () {
      // centroid를 빼고 맞추므로 평행이동은 결과에 영향이 없어야 한다.
      final base = cardinalCalibrationForBuilding(
        _buildingId,
        floorPlan: _plan(),
      )!;
      final moved = cardinalCalibrationForBuilding(
        _buildingId,
        floorPlan: _plan(
          transform: (p) => LatLng(p.latitude + 0.01, p.longitude + 0.01),
        ),
      )!;

      expect(
        _angleDelta(moved.northMapBearingDeg, base.northMapBearingDeg).abs(),
        lessThan(0.5),
      );
    });

    test('도면을 통째로 확대해도 북쪽은 그대로다', () {
      // scale은 따로 푸는 값이라 회전에 섞이면 안 된다.
      const origin = LatLng(37.52570, 126.92830);
      final base = cardinalCalibrationForBuilding(
        _buildingId,
        floorPlan: _plan(),
      )!;
      final scaled = cardinalCalibrationForBuilding(
        _buildingId,
        floorPlan: _plan(
          transform: (p) => LatLng(
            origin.latitude + (p.latitude - origin.latitude) * 3,
            origin.longitude + (p.longitude - origin.longitude) * 3,
          ),
        ),
      )!;

      expect(
        _angleDelta(scaled.northMapBearingDeg, base.northMapBearingDeg).abs(),
        lessThan(0.5),
      );
    });

    test('도면을 30도 돌리면 북쪽도 30도 돈다', () {
      // **이것이 핵심이다.** 회전을 못 따라가면 방위선이 굳어 버리고, 도면을
      // 새로 뽑을 때마다 조용히 틀린 각도를 그린다.
      const origin = LatLng(37.52570, 126.92830);
      final base = cardinalCalibrationForBuilding(
        _buildingId,
        floorPlan: _plan(),
      )!;
      final turned = cardinalCalibrationForBuilding(
        _buildingId,
        floorPlan: _plan(transform: _rotate(30, origin: origin)),
      )!;

      expect(
        _angleDelta(turned.northMapBearingDeg, base.northMapBearingDeg).abs(),
        closeTo(30, 1.0),
      );
    });

    test('180도 돌리면 북쪽도 180도 돈다', () {
      const origin = LatLng(37.52570, 126.92830);
      final base = cardinalCalibrationForBuilding(
        _buildingId,
        floorPlan: _plan(),
      )!;
      final turned = cardinalCalibrationForBuilding(
        _buildingId,
        floorPlan: _plan(transform: _rotate(180, origin: origin)),
      )!;

      expect(
        _angleDelta(turned.northMapBearingDeg, base.northMapBearingDeg).abs(),
        closeTo(180, 1.0),
      );
    });
  });

  group('정답을 아는 입력 — 차이가 아니라 값을 못 박는다', () {
    // 위의 불변성 테스트만으로는 부족하다. 모든 경우에 똑같이 더해지는 오차
    // (예: atan2 인자를 뒤바꿔 90° 밀리는 것)는 차이를 재는 테스트를 그대로
    // 통과한다. 실제로 그런 오타 둘을 넣어 봤더니 아홉 개가 다 통과했다.
    //
    // 그래서 **답을 아는 입력**을 만든다. 레퍼런스 캡처는 북고정이므로 그
    // 좌표를 그대로 도면으로 쓰면 맞춤이 찾을 회전은 0이고 북쪽은 0°다.

    test('레퍼런스 좌표를 그대로 도면으로 쓰면 북쪽은 0도다', () {
      final result = cardinalCalibrationForBuilding(
        _buildingId,
        floorPlan: _referencePlan(),
      )!;

      expect(_angleDelta(result.northMapBearingDeg, 0).abs(), lessThan(1.0));

      // **반전은 true가 정답이다.** 도면 좌표계는 남쪽이 +y이고
      // (`floorY = -latitude`) 레퍼런스 캡처는 북쪽이 +y다. 두 좌표계를 겹치려면
      // y축을 뒤집어야 하므로, 올바른 맞춤은 항상 반전을 고른다.
      //
      // 이 한 줄이 반전 판정 부등호가 뒤집히는 오타를 잡는다. 각도만 보면
      // 그 오타도 통과한다.
      expect(result.reflected, isTrue);

      // 완전히 겹치는 배치라 잔차도 거의 0이어야 한다.
      expect(result.rmsErrorPx, lessThan(1.0));
    });

    test('도면을 시계 방향으로 돌린 만큼 북쪽 각도가 커진다', () {
      // 도면을 시계 방향으로 θ 돌리면, 도면 좌표에서 본 북쪽은 반시계로 θ만큼
      // 움직인 것처럼 보인다. 부호까지 못 박아야 "돌아간 방향"이 반대인 버그가
      // 걸린다.
      for (final deg in [30.0, 90.0, 180.0, 270.0]) {
        final result = cardinalCalibrationForBuilding(
          _buildingId,
          floorPlan: _referencePlan(rotateDeg: deg),
        )!;
        expect(
          _angleDelta(result.northMapBearingDeg, deg).abs(),
          lessThan(1.5),
          reason: '$deg도 회전에서 북쪽이 $deg도가 아니다',
        );
      }
    });
  });

  group('결과 값', () {
    test('bearing은 항상 0~360 범위다', () {
      const origin = LatLng(37.52570, 126.92830);
      for (final deg in [0.0, 45.0, 90.0, 135.0, 200.0, 300.0, 359.0]) {
        final result = cardinalCalibrationForBuilding(
          _buildingId,
          floorPlan: _plan(transform: _rotate(deg, origin: origin)),
        )!;
        expect(
          result.northMapBearingDeg,
          inInclusiveRange(0, 360),
          reason: '$deg도 회전에서 범위를 벗어났다',
        );
      }
    });

    test('rms 오차는 회전·평행이동에 영향받지 않는다', () {
      // 오차는 맞춤이 얼마나 잘 맞았는지의 척도다. 도면을 돌렸다고 커지면
      // 그 값으로 품질을 판단할 수 없다.
      const origin = LatLng(37.52570, 126.92830);
      final base = cardinalCalibrationForBuilding(
        _buildingId,
        floorPlan: _plan(),
      )!;
      final turned = cardinalCalibrationForBuilding(
        _buildingId,
        floorPlan: _plan(transform: _rotate(75, origin: origin)),
      )!;

      expect(
        turned.rmsErrorPx,
        closeTo(base.rmsErrorPx, base.rmsErrorPx * 0.02),
      );
    });
  });
}
