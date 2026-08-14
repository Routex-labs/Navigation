import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../domain/geo/geo_transform.dart';

/// anchor 확정 근거.
///
/// [verticalTransfer]는 기압계가 층 이동을 확인해 새 층의 도착 노드로 위치를
/// 옮긴 경우다. 사용자 pin과 달리 회전값은 직전 anchor에서 그대로 물려받는다 —
/// 같은 센서 세션이라 heading frame이 끊기지 않기 때문이다.
enum AnchorSource { entranceGate, userPin, manualHeadingCal, verticalTransfer }

/// PDR 로컬 미터 좌표를 floor `local_m` 좌표에 고정하는 데 필요한 데이터(§4).
///
/// 변환은 `floor = axes·R(rotationDeg)·pdr + anchorLocalM`이다.
///
/// PDR 좌표는 언제나 +east/+north지만, 평면도 `local_m`은 데이터셋에 따라
/// +y가 남쪽이거나 축이 회전돼 있을 수 있다. [PdrToFloorAxes]가 이 좌표계
/// 차이를 흡수하고, [rotationDeg]는 자북을 얻지 못한 기기의 수동 heading
/// 보정에만 쓴다.
class PdrAnchor {
  const PdrAnchor({
    required this.floorId,
    required this.anchorLocalM,
    required this.rotationDeg,
    required this.headingReference,
    required this.requiresManualRotationCalibration,
    required this.source,
    required this.confidence,
    this.axes = const PdrToFloorAxes.identity(),
  });

  final String floorId;

  /// PDR 원점(세션 시작점)이 놓이는 floor 좌표(local_m). eastM=x_m, northM=y_m.
  final PdrLocalPoint anchorLocalM;

  /// PDR heading frame → floor frame 회전각(도).
  final double rotationDeg;

  /// heading이 자북 기준인지. arbitrary corrected fallback이면 수동 보정이 필요하다.
  final HeadingReference headingReference;

  /// 서버 자북 정렬각을 못 쓰는 상태(arbitrary reference)라 수동 방향 보정이 필수인지.
  final bool requiresManualRotationCalibration;

  final AnchorSource source;

  /// 0~1. anchor 신뢰도.
  final double confidence;

  /// 이 floor의 local axis 규약. anchor를 확정할 때와 이후 경로를 그릴 때
  /// 반드시 같은 값을 써야, anchor 직전의 센서 이동도 올바르게 상쇄된다.
  final PdrToFloorAxes axes;
}

/// 0°=북쪽, 90°=동쪽인 bearing을 PDR 동·북 단위 벡터로 바꾼다.
PdrLocalPoint pdrDirectionForBearing(double bearingDeg) {
  final radians = bearingDeg * math.pi / 180;
  return PdrLocalPoint(math.sin(radians), math.cos(radians));
}

/// PDR 동·북 방향 벡터를 0° 이상 360° 미만의 bearing으로 바꾼다.
double pdrBearingForDirection(PdrLocalPoint direction) => normalizePdrBearing(
  math.atan2(direction.eastM, direction.northM) * 180 / math.pi,
);

double normalizePdrBearing(double bearingDeg) {
  final normalized = bearingDeg % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}

/// 두 bearing 사이의 최단 회전각을 -180° 이상 180° 미만으로 정규화한다.
double normalizePdrRotation(double rotationDeg) {
  final normalized = (rotationDeg + 180) % 360;
  return (normalized < 0 ? normalized + 360 : normalized) - 180;
}

/// 현재 지도 카메라를 기준으로 고른 화면 방향을 floor-local 방향으로 바꾼다.
///
/// 화면 위쪽은 camera bearing, 오른쪽은 camera bearing+90°가 가리키는 실제
/// 동·북 방향이다. 컨트롤러는 이 floor 방향을 [PdrToFloorAxes.inverseApply]로
/// 되돌린 뒤 arbitrary PDR heading과 비교한다.
PdrLocalPoint floorDirectionForScreenDirection({
  required double cameraBearingDeg,
  required double screenClockwiseOffsetDeg,
  required PdrToFloorAxes axes,
}) => axes.apply(
  pdrDirectionForBearing(cameraBearingDeg + screenClockwiseOffsetDeg),
);

/// 나침반 bearing 보정각을 PDR east/north 벡터에 적용한다.
///
/// bearing은 0°=북쪽, 90°=동쪽이며 시계 방향으로 증가한다. 따라서 일반적인
/// Cartesian 반시계 회전 행렬과 부호가 반대다.
PdrLocalPoint rotatePdrBearing(PdrLocalPoint point, double bearingDeg) {
  final theta = bearingDeg * math.pi / 180.0;
  final cosT = math.cos(theta);
  final sinT = math.sin(theta);
  return PdrLocalPoint(
    point.eastM * cosT + point.northM * sinT,
    -point.eastM * sinT + point.northM * cosT,
  );
}

/// PDR 좌표를 floor 좌표로 옮기는 순수 변환. UI는 이 결과 좌표만 렌더한다.
///
class FloorCoordinateTransform {
  FloorCoordinateTransform(this.anchor, {PdrToFloorAxes? axes})
    : axes = axes ?? anchor.axes;

  final PdrAnchor anchor;
  final PdrToFloorAxes axes;

  /// PDR 로컬 좌표를 floor local_m 좌표로 변환한다.
  PdrLocalPoint toFloor(PdrLocalPoint pdr) {
    final rotated = rotatePdrBearing(pdr, anchor.rotationDeg);
    final floorDelta = axes.apply(rotated);
    return PdrLocalPoint(
      anchor.anchorLocalM.eastM + floorDelta.eastM,
      anchor.anchorLocalM.northM + floorDelta.northM,
    );
  }

  /// PDR bearing을 위치와 동일한 회전·축 변환으로 floor bearing으로 바꾼다.
  ///
  /// `walkingHeading + rotation`만 하면 y축 반전이나 회전된 도면에서 방향
  /// 마커와 복도 각도가 어긋난다. 단위 방향 벡터를 실제 좌표 변환에 통과시켜
  /// 위치와 heading이 항상 같은 frame을 쓰게 한다.
  double toFloorBearing(double pdrBearingDeg) {
    final direction = pdrDirectionForBearing(pdrBearingDeg);
    final rotated = rotatePdrBearing(direction, anchor.rotationDeg);
    return pdrBearingForDirection(axes.apply(rotated));
  }

  /// tracker의 floor-local bearing을 지도/WGS84 기준 bearing으로 되돌린다.
  ///
  /// 복도 보정기는 floor graph 각도로 동작하지만 위치 마커 heading은 true
  /// north 기준을 기대한다. 축 반전·회전이 있는 도면에서 floor 각도를 그대로
  /// 넘기면 마커만 반대로 보이므로 같은 선형 변환의 역변환을 거친다.
  double floorBearingToMapBearing(double floorBearingDeg) {
    final floorDirection = pdrDirectionForBearing(floorBearingDeg);
    final alignedPdrDirection = axes.inverseApply(floorDirection);
    if (alignedPdrDirection == null || alignedPdrDirection.distance < 1e-12) {
      return normalizePdrBearing(floorBearingDeg);
    }
    return pdrBearingForDirection(alignedPdrDirection);
  }
}
