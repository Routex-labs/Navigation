# PDR Phase 2 마감 설계

## 목표

현재 구현된 iOS `PdrMotionBridge`와 Dart `IndoorNavigationDriver`를 메인 앱 수명주기에
연결하고, 센서 오류를 계약으로 노출하며, 실제 iPhone에서 센서 → Swift → Dart →
`PdrSession` → `PdrSnapshot` 전체 흐름을 재현 가능한 headless 하니스로 검증한다.

지도 렌더링, 제품 화면, `local_m` 파서와 anchor 좌표 정밀화는 Phase 3 또는 UI 트랙의
범위로 남긴다.

## 완료 기준

Phase 2는 다음 조건을 모두 충족해야 완료로 기록한다.

1. 앱 범위에서 `IosPdrMotionSource`와 `IndoorNavigationDriver`가 각각 하나만 생성된다.
2. 앱 background/foreground 전이가 PDR pause/resume과 native 센서 stop/start로 전달된다.
3. 센서 시작 실패와 EventChannel 오류가 처리되지 않은 비동기 오류로 새지 않고
   `PdrRuntimeStatus.degraded` 및 warning code로 노출된다.
4. degraded 상태에서 이후 방출되는 `PdrSnapshot.quality`도 degraded이며 같은 warning을
   포함한다.
5. 단위 테스트가 start/stop, lifecycle, 오류 전파, 세션 유지와 quality 합성을 검증한다.
6. iOS 시뮬레이터 빌드가 성공한다.
7. 연결된 실제 iPhone에서 headless integration test로 heading 수신, 걷기 후 snapshot 갱신,
   stop 후 이벤트 중단을 확인한다.

실기기 권한 승인과 보행은 사용자가 수행한다. 기기 또는 서명 상태 때문에 7번을 실행할 수
없으면 Phase 2를 완료로 표시하지 않고, 자동 검증 완료와 실기기 차단 사유를 분리해 기록한다.

## 접근 방식

### 앱 범위 소유권

기존 `client/lib/core/service_locator.dart` 패턴에 맞춰 다음 두 인스턴스를 전역 final로 둔다.

- `PdrMotionSource pdrMotionSource = IosPdrMotionSource()`
- `IndoorNavigationDriver indoorNavigationDriver = IndoorNavigationDriver(source: pdrMotionSource)`

화면은 이후 계약을 통해 같은 드라이버를 사용한다. IndoorMap과 RouteGuide 전환은 드라이버를
재생성하거나 세션을 reset하지 않는다.

### 앱 lifecycle

`NavigationApp`을 `StatefulWidget`으로 바꾸고 state가 `WidgetsBindingObserver`를 구현한다.

- `inactive`, `paused`, `detached`, `hidden` → 드라이버 background 처리
- `resumed` → 드라이버 foreground 처리

중복 lifecycle 이벤트는 드라이버에서 멱등 처리한다. background에서는 tracking timeline을
pause하고 EventChannel 구독을 취소해 CoreMotion/CMPedometer를 멈춘다. foreground에서는 먼저
센서 스트림을 다시 시작한 뒤 timeline을 resume한다. 안내 중이 아닐 때는 아무 플랫폼 호출도
하지 않는다.

### 비동기 명령 계약

플랫폼 센서 호출은 실패할 수 있으므로 `IndoorNavigationIntents`의 다음 메서드를
`Future<void>`로 변경한다.

- `startGuidance`
- `stopGuidance`
- `changeFloor`

anchor 확인 메서드는 기존처럼 `Future<void>`를 유지한다. 호출자는 완료 또는 오류 상태 반영을
기다릴 수 있다. 컨트롤러는 예상 가능한 플랫폼 실패를 runtime status로 변환하고 호출 자체는
정상 종료시켜 UI에 처리되지 않은 예외를 강제하지 않는다.

### Runtime status 계약

`contract/pdr_runtime_status.dart`에 다음 공개 타입을 추가한다.

```dart
enum PdrRuntimeState { idle, starting, running, paused, stopping, degraded }

class PdrRuntimeStatus {
  final PdrRuntimeState state;
  final List<String> warnings;
}
```

`IndoorNavigationView`는 다음을 노출한다.

```dart
Stream<PdrRuntimeStatus> get runtimeStatuses;
PdrRuntimeStatus get currentRuntimeStatus;
```

warning은 UI 문구가 아니라 안정된 식별자다.

- `sensorStartFailed`
- `sensorStreamError`
- `sensorResumeFailed`
- `pedometerResetFailed`

첫 native 이벤트를 받기 전에는 `starting`, 첫 이벤트 이후 `running`으로 전이한다. 오류가
발생하면 `degraded`로 전이한다. 정상적인 명시 stop은 `stopping`을 거쳐 `idle`이 된다.

### Snapshot quality 합성

센서 오류는 client/platform 계층의 책임이므로 pure Dart 코어에 플랫폼 예외를 넣지 않는다.
컨트롤러가 코어 snapshot을 UI로 전달할 때 runtime이 degraded라면 다음 규칙으로 복사한다.

- `quality.state = PdrQualityState.degraded`
- 기존 quality warnings를 보존한다.
- runtime warning을 중복 없이 추가한다.
- position, path, steps, distance, preview와 features는 변경하지 않는다.

세션 시작 전에는 snapshot이 없으므로 UI는 `currentRuntimeStatus`를 사용해 권한·센서 오류를
표시할 수 있다.

## Headless 실기기 하니스

`client/integration_test/pdr_device_smoke_test.dart`를 추가한다. 기존 미추적
`health_check_test.dart`는 수정하지 않는다.

하니스는 제품 화면을 추가하지 않고 다음 순서만 실행한다.

1. Flutter integration test binding 초기화
2. 독립 `IosPdrMotionSource`와 `IndoorNavigationDriver` 생성
3. `startGuidance(floorId: 'device-smoke-floor')`
4. runtime이 `running`이 될 때까지 기다려 native heading/event 수신 확인
5. 안내 메시지를 출력하고 최대 45초 동안 사용자의 보행을 기다림
6. `snapshot.steps > 0`, `snapshot.distanceM > 0`, position 원점 이탈 확인
7. `stopGuidance()` 후 짧은 관찰 구간 동안 추가 이벤트가 없는지 확인
8. driver dispose

하니스는 simulator에서 skip하고 iOS 실기기에서만 실행한다. 시간 제한 실패는 어느 구간이
실패했는지 heading/start/walking/stop 단계별 메시지를 남긴다.

## 테스트 전략

모든 동작 변경은 TDD로 구현한다.

1. 계약 fake 테스트: runtime status와 async intents conformance
2. 컨트롤러 테스트: starting → running, start 오류 → degraded, stream 오류 → degraded,
   degraded quality 합성
3. lifecycle 테스트: 안내 중 background stop/pause, foreground start/resume, 중복 이벤트 멱등성
4. 앱 테스트: `NavigationApp` lifecycle observer가 앱 범위 드라이버에 전이를 전달하도록
   주입 가능한 callback 경계를 검증
5. 기존 코어 10개와 계약/컨트롤러 14개 회귀 테스트
6. PDR 경로 analyze, 전체 Flutter test, iOS simulator build
7. 연결된 iPhone에서 integration smoke test

전체 `client` analyze는 사용자의 기존 미추적 `dio`/`riverpod` WIP 오류를 별도 baseline으로
기록한다. 이번 변경 경로에는 신규 analyze error가 없어야 한다.

## 변경 파일

- 수정: `client/lib/core/service_locator.dart`
- 수정: `client/lib/app.dart`
- 수정: `client/lib/features/indoor_navigation/contract/indoor_navigation_intents.dart`
- 수정: `client/lib/features/indoor_navigation/contract/indoor_navigation_view.dart`
- 수정: `client/lib/features/indoor_navigation/contract/indoor_navigation_contract.dart`
- 생성: `client/lib/features/indoor_navigation/contract/pdr_runtime_status.dart`
- 수정: `client/lib/features/indoor_navigation/application/indoor_navigation_controller.dart`
- 수정: `client/test/features/indoor_navigation/contract_test.dart`
- 수정: `client/test/features/indoor_navigation/controller_test.dart`
- 생성: `client/test/features/indoor_navigation/app_lifecycle_test.dart`
- 생성: `client/integration_test/pdr_device_smoke_test.dart`
- 수정: `docs/pdr-ui-contract.md`
- 수정: `docs/pdr-migration-plan.md`

## 범위 밖

- IndoorMap/RouteGuide 위젯에 PDR 경로 표시
- meter-space 렌더러
- `FloorMapModel` 및 `north_alignment`
- anchor 자동 선택과 좌표 정밀화
- Android 센서 구현
- 초록/주황 fusion 튜닝
- 기존 미추적 API, map, riverpod 작업 수정
