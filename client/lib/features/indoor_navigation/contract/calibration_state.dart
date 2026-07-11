import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import 'pdr_anchor.dart';

/// 캘리브레이션 상태기계 단계.
///
/// - [uncalibrated]: anchor 없음. 지도 위 위치를 그리지 않는다(§4).
/// - [awaitingPin]: 사용자가 현재 위치를 지도에 찍기를 기다린다.
/// - [awaitingHeading]: arbitrary reference라 진행 방향 보정을 기다린다.
/// - [calibrated]: anchor 확정. 지도 위 위치 렌더 가능.
enum CalibrationPhase { uncalibrated, awaitingPin, awaitingHeading, calibrated }

/// 캘리브레이션 상태. UI는 이걸 구독해 캘리브레이션 UI/위치 렌더 여부를 정한다.
class CalibrationStatus {
  const CalibrationStatus({
    required this.phase,
    required this.headingReference,
    required this.requiresManualRotationCalibration,
    this.anchor,
  });

  /// 아직 heading을 못 받았거나 anchor가 없는 초기 상태.
  const CalibrationStatus.uncalibrated()
      : phase = CalibrationPhase.uncalibrated,
        headingReference = HeadingReference.arbitraryCorrected,
        requiresManualRotationCalibration = true,
        anchor = null;

  final CalibrationPhase phase;
  final HeadingReference headingReference;

  /// arbitrary reference라 서버 자북 정렬각을 못 쓰고 수동 방향 보정이 필요한지.
  final bool requiresManualRotationCalibration;

  /// [CalibrationPhase.calibrated]일 때만 non-null.
  final PdrAnchor? anchor;

  /// 지도 위에 실제 위치를 그려도 되는지. anchor가 확정됐을 때만 true(§4).
  bool get canRenderPosition =>
      phase == CalibrationPhase.calibrated && anchor != null;
}
