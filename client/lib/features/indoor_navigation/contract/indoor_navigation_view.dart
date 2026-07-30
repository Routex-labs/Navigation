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

  /// 지금 세션이 붙어 있는 층. 세션을 한 번도 시작하지 않았으면 null.
  ///
  /// 확정되는 anchor에는 **이 값**이 층으로 찍힌다([PdrAnchor.floorId]). 그리고
  /// 위치 마커·경로는 `anchor.floorId == 화면이 보여주는 층`일 때만 그려진다.
  /// 그래서 UI는 위치를 다시 지정하기 전에 이 값이 지금 층과 같은지 확인하고,
  /// 다르면 [IndoorNavigationIntents.changeFloor]로 맞춰야 한다 — 그러지 않으면
  /// 새로 찍은 anchor가 옛 층으로 기록돼 화면에 아무것도 나타나지 않는다.
  String? get currentFloorId;
}
