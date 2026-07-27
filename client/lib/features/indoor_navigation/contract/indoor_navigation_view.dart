import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import 'calibration_state.dart';
import 'pdr_runtime_status.dart';

/// UI가 **구독**하는 읽기 전용 관찰 계약.
///
/// 구현체(Phase 2의 IndoorNavigationController)는 headless 로직이고, UI는 이
/// 인터페이스만 보고 렌더한다. 상태관리 방식(riverpod 등)은 UI팀 자유다.
abstract interface class IndoorNavigationView {
  /// PDR 스냅샷 스트림(초록 위치·경로, 주황 preview, 품질). confirmed step/preview
  /// 갱신 시 이벤트가 나온다.
  Stream<PdrSnapshot> get snapshots;

  /// 가장 최근 스냅샷. 세션 시작 전이면 null.
  PdrSnapshot? get currentSnapshot;

  /// 캘리브레이션 상태 스트림. 위치 렌더 여부·캘리브레이션 UI를 이걸로 결정한다.
  Stream<CalibrationStatus> get calibration;

  /// 가장 최근 캘리브레이션 상태.
  CalibrationStatus get currentCalibration;

  /// 플랫폼 센서 파이프라인 실행 상태 스트림.
  Stream<PdrRuntimeStatus> get runtimeStatuses;

  /// 가장 최근 센서 파이프라인 실행 상태.
  PdrRuntimeStatus get currentRuntimeStatus;

  /// heading이 자리를 잡았는지.
  ///
  /// 세션 시작 직후에는 CoreMotion의 자북 reference가 아직 수렴하지 않았거나
  /// 사용자가 몸을 돌리는 중이라 방향이 흔들린다. 그 사이에 앵커를 확정하면
  /// 첫 걸음들이 틀어진 방향으로 눕는다(실측: 첫 4걸음이 복도 대비 17.6° 어긋남).
  /// native의 `headingStable`은 기기 기울기만 보므로 이 판단에 쓸 수 없다.
  bool get isHeadingConverged;

  /// 마지막 [IndoorNavigationIntents.stopGuidance]에서 native가 돌려준 pedometer
  /// 동결 결과. 세션을 끝내기 전이면 null.
  ///
  /// iOS는 여기에 세션 구간 재조회 결과(`queriedSteps`)를 함께 담는다. live
  /// stream이 초반 구간을 적게 세는 원인을 가리기 위한 **진단 전용** 값이고,
  /// 경로·거리 보정에는 쓰지 않는다.
  Map<String, Object?>? get lastPedometerFinalizeInfo;
}
