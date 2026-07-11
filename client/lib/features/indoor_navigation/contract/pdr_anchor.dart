import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

/// anchor 확정 근거.
enum AnchorSource { entranceGate, userPin, manualHeadingCal }

/// PDR 로컬 미터 좌표를 floor `local_m` 좌표에 고정하는 데 필요한 데이터(§4).
///
/// 변환은 2D rigid transform이다: `floor = R(rotationDeg)·pdr + anchorLocalM`.
class PdrAnchor {
  const PdrAnchor({
    required this.floorId,
    required this.anchorLocalM,
    required this.rotationDeg,
    required this.headingReference,
    required this.requiresManualRotationCalibration,
    required this.source,
    required this.confidence,
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
}

/// PDR 좌표를 floor 좌표로 옮기는 순수 변환. UI는 이 결과 좌표만 렌더한다.
///
/// 축·부호 규약은 Phase 3에서 실제 floor 데이터로 검증한다. 여기서는 계약(rigid
/// transform 구조)과 시그니처를 고정한다.
class FloorCoordinateTransform {
  const FloorCoordinateTransform(this.anchor);

  final PdrAnchor anchor;

  /// PDR 로컬 좌표를 floor local_m 좌표로 변환한다.
  PdrLocalPoint toFloor(PdrLocalPoint pdr) {
    final theta = anchor.rotationDeg * math.pi / 180.0;
    final cosT = math.cos(theta);
    final sinT = math.sin(theta);
    final x = pdr.eastM * cosT - pdr.northM * sinT;
    final y = pdr.eastM * sinT + pdr.northM * cosT;
    return PdrLocalPoint(
      anchor.anchorLocalM.eastM + x,
      anchor.anchorLocalM.northM + y,
    );
  }
}
