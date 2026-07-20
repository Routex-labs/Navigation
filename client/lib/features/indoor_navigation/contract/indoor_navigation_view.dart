import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import 'calibration_state.dart';
import 'pdr_heading_observation.dart';
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

  /// 위치·걸음과 독립적으로 갱신되는 휴대폰 실시간 방위(최대 20Hz).
  Stream<PdrHeadingObservation> get headingObservations;

  /// 가장 최근 휴대폰 방위. 센서 샘플을 아직 못 받았으면 null.
  PdrHeadingObservation? get currentHeadingObservation;

  /// 캘리브레이션 상태 스트림. 위치 렌더 여부·캘리브레이션 UI를 이걸로 결정한다.
  Stream<CalibrationStatus> get calibration;

  /// 가장 최근 캘리브레이션 상태.
  CalibrationStatus get currentCalibration;

  /// 플랫폼 센서 파이프라인 실행 상태 스트림.
  Stream<PdrRuntimeStatus> get runtimeStatuses;

  /// 가장 최근 센서 파이프라인 실행 상태.
  PdrRuntimeStatus get currentRuntimeStatus;
}
