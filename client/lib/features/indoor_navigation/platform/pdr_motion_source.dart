import 'native_pdr_event.dart';

/// PDR 센서 이벤트의 플랫폼 중립 경계.
///
/// 연구 앱 `MotionSource`의 typed 승격판. iOS/Android 구현이나 테스트 fake는 이
/// 인터페이스 뒤에 숨는다. 컨트롤러/코어는 어느 플랫폼이 raw 이벤트를 만들었는지
/// 모른다. GPS/IMUv3/JSON export는 이식 범위에서 제외했다.
abstract interface class PdrMotionSource {
  /// 파싱된 센서 이벤트 스트림.
  Stream<NativePdrEvent> get events;

  /// 센서 스트림 시작.
  Future<void> start();

  /// 센서 스트림 정지.
  Future<void> stop();

  /// CMPedometer를 "지금"부터 재시작한다. 새 stepSessionId를 반환한다.
  Future<int?> resetPedometer();

  /// 안내 종료 직전 native 센서가 이미 관측한 마지막 걸음 수를 확정한다.
  ///
  /// Android의 STEP_COUNTER는 비동기·배치 방식이라 stop 직전에 한 번 동결하지
  /// 않으면, 폰을 내려놓는 동안 도착한 callback이 종료된 path를 다시 늘릴 수
  /// 있다. iOS도 같은 호출 표면을 제공해 lifecycle을 플랫폼별로 갈라놓지 않는다.
  ///
  /// native가 돌려준 동결 결과를 그대로 반환한다. iOS는 여기에 세션 구간을
  /// 사후 재조회한 `queriedSteps`를 함께 담는다 — live stream이 초반 구간을
  /// 적게 세는 문제의 원인을 가리는 진단값이며, 경로 보정에는 쓰지 않는다.
  Future<Map<String, Object?>?> finalizePedometer();

  /// 리소스 해제.
  Future<void> dispose();
}

/// PDR 네이티브 브리지가 없는 플랫폼의 명시적 구현.
///
/// Linux CI·macOS 데스크톱·웹에서 iOS/Android EventChannel을 잘못 열면
/// `MissingPluginException`이 비동기 서비스 오류로 새어 앱 부팅 자체가
/// 실패한다. 빈 이벤트 스트림을 제공하되 직접 시작 요청은 명확히 실패시켜,
/// 호출자가 미지원 상태를 정상적인 degraded 경로로 처리하게 한다.
class UnsupportedPdrMotionSource implements PdrMotionSource {
  const UnsupportedPdrMotionSource();

  @override
  Stream<NativePdrEvent> get events => const Stream.empty();

  @override
  Future<void> start() =>
      Future.error(UnsupportedError('PDR sensors are not supported'));

  @override
  Future<void> stop() async {}

  @override
  Future<int?> resetPedometer() async => null;

  @override
  Future<Map<String, Object?>?> finalizePedometer() async => null;

  @override
  Future<void> dispose() async {}
}
