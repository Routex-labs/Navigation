import 'pdr_local_point.dart';
import 'quality.dart';

/// 주황(accel preview) 경로 스냅샷. 독립 거리 관측치이자 품질 신호다.
/// confirmed(초록) 위치·거리·걸음수에는 절대 반영하지 않는다.
class PdrPreview {
  const PdrPreview({
    required this.position,
    required this.path,
    required this.steps,
    required this.distanceM,
  });

  final PdrLocalPoint position;
  final List<PdrLocalPoint> path;
  final int steps;
  final double distanceM;
}

/// Android RoNIN 자동보폭 비교 경로.
///
/// STEP_COUNTER와 기존 heading은 confirmed 경로와 동일하고, 한 걸음 거리만
/// RoNIN 수평 속도/cadence 후보로 바꾼다. 제품 위치에는 사용하지 않는다.
class PdrRoninTrack {
  const PdrRoninTrack({
    required this.supported,
    required this.modelReady,
    required this.position,
    required this.path,
    required this.steps,
    required this.distanceM,
    required this.effectiveStrideM,
    required this.model,
    required this.status,
    this.rawStrideM,
    this.speedMps,
    this.speedStdMps,
    this.cadenceHz,
  });

  const PdrRoninTrack.empty()
    : supported = false,
      modelReady = false,
      position = PdrLocalPoint.zero,
      path = const [PdrLocalPoint.zero],
      steps = 0,
      distanceM = 0,
      effectiveStrideM = 0.70,
      model = null,
      status = 'unsupported',
      rawStrideM = null,
      speedMps = null,
      speedStdMps = null,
      cadenceHz = null;

  final bool supported;
  final bool modelReady;
  final PdrLocalPoint position;
  final List<PdrLocalPoint> path;
  final int steps;
  final double distanceM;
  final double effectiveStrideM;
  final String? model;
  final String status;
  final double? rawStrideM;
  final double? speedMps;
  final double? speedStdMps;
  final double? cadenceHz;
}

/// 코어가 내보내는 관측 스냅샷. UI는 이것을 구독해 렌더한다.
class PdrSnapshot {
  const PdrSnapshot({
    required this.position,
    required this.path,
    required this.steps,
    required this.distanceM,
    required this.walkingHeadingDeg,
    required this.hasHeading,
    required this.preview,
    required this.quality,
    this.ronin = const PdrRoninTrack.empty(),
  });

  /// 초록 confirmed 센서 원본 위치. 로컬 미터, 세션 시작점 기준.
  ///
  /// 제품 현재 위치는 클라이언트가 이 원본을 복도 graph 제약 상태기에 넣어
  /// 별도로 유지한다. 원본은 진단·비교를 위해 수정하지 않는다.
  final PdrLocalPoint position;
  final List<PdrLocalPoint> path;
  final int steps;
  final double distanceM;

  /// fused heading + walkOffset 보정이 들어간 실제 보행 방향(자북 기준일 때).
  final double walkingHeadingDeg;
  final bool hasHeading;

  final PdrPreview preview;
  final PdrRoninTrack ronin;
  final PdrQuality quality;
}
