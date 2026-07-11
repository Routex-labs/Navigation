/// iOS 센서 파이프라인의 앱 범위 실행 상태.
enum PdrRuntimeState { idle, starting, running, paused, stopping, degraded }

/// UI가 센서 준비·실행·오류 상태를 관찰하는 안정된 계약.
///
/// [warnings]는 사용자 문구가 아니라 UI/telemetry가 해석할 식별자다.
class PdrRuntimeStatus {
  const PdrRuntimeStatus({required this.state, this.warnings = const []});

  const PdrRuntimeStatus.idle()
    : state = PdrRuntimeState.idle,
      warnings = const [];

  final PdrRuntimeState state;
  final List<String> warnings;
}
