# PDR 앱 이식 구조와 기능 안내

> 기준 브랜치: `feature/pdr-indoor-navigation` · 기준일: 2026-07-11
> 대상: 앱 개발자, UI팀, 지도/node·백엔드 담당자

## 한눈에 보기

PDR(Pedestrian Dead Reckoning)은 GPS가 약한 실내에서 iPhone의 움직임·걸음 센서를 이용해
사용자의 **상대 이동 거리와 방향**을 계산하는 모듈이다. 이번 이식으로 iOS 센서부터 Flutter
앱의 PDR snapshot까지의 경로는 연결·검증됐다.

다만 아직 기존 `IndoorMap`/`RouteGuide` 화면이 PDR을 시작하거나 위치를 지도에 그리지는 않는다.
PDR 결과는 세션 시작점을 원점으로 하는 `PdrLocalPoint`(미터)이고, 실제 층 지도 `local_m` 좌표로
올리는 anchor·node 정합은 Phase 3 범위다.

| 구분 | 현재 상태 |
|---|---|
| iOS 센서 → PDR 계산 → snapshot | 완료 및 iPhone 실기기 검증 |
| 앱 background/foreground lifecycle | 완료 |
| UI가 사용할 공개 계약 | 완료 |
| IndoorMap/RouteGuide에서 안내 시작·위치 표시 | 아직 미연결 |
| floor node/local_m 기반 실제 지도 좌표 정합 | Phase 3 대기 |
| Android | 미구현 |

## 1. 기존 앱 구조

기존 Flutter 앱은 화면 라우팅과 repository 중심으로 실외·실내 안내 화면을 제공한다.

```mermaid
flowchart LR
  Splash["Splash"] --> Outdoor["OutdoorMap\nGPS / TMap"]
  Outdoor --> Indoor["IndoorMap\n기존 GeoJSON·더미 위치"]
  Indoor --> Destination["Destination"]
  Destination --> Guide["RouteGuide\n기존 GeoJSON·더미 위치"]
  Guide --> Arrival["Arrival"]

  Service["service_locator\nRepository / 위치 서비스"] --> Outdoor
  Service --> Indoor
  Service --> Guide
```

### 기존 실내 화면의 한계

- `IndoorMap`과 `RouteGuide`는 `FloorPlan.fromGeoJson()`의 `LatLng` 모델을 사용한다.
- 현재 실내 위치 마커는 corridor 또는 POI 첫 좌표를 쓰는 더미 값이다.
- 이 좌표계는 PDR이 내보내는 미터 기반 좌표와 다르다.

따라서 PDR을 단순히 기존 `LocationMarker`에 넣으면 안 된다. 먼저 PDR 로컬 미터를 floor `local_m`으로
변환하고, UI팀의 meter-space 렌더러가 이를 그려야 한다.

## 2. PDR은 앱 어디에 붙었나

PDR은 특정 화면의 `State`가 아니라 **앱 범위 단일 세션 서비스**로 붙었다.

```mermaid
flowchart TB
  App["NavigationApp\nWidgetsBindingObserver"] -->|background / foreground| Driver
  Locator["core/service_locator.dart"] -->|단일 인스턴스| Source
  Locator -->|단일 인스턴스| Driver

  subgraph PDR["features/indoor_navigation"]
    Source["IosPdrMotionSource"] -->|typed NativePdrEvent| Driver["IndoorNavigationDriver\nheadless controller"]
    Driver --> Session["PdrSession\nindoor_pdr_core"]
    Session --> Driver
    Driver --> Contract["IndoorNavigationController\n공개 계약"]
  end

  UI["향후 IndoorMap / RouteGuide / calibration UI"] <-->|"snapshots, runtime, intents"| Contract
```

### 실제 연결 지점

| 기존 앱 위치 | PDR가 붙은 방식 | 역할 |
|---|---|---|
| `client/lib/core/service_locator.dart` | `pdrMotionSource`, `indoorNavigationDriver` 전역 단일 인스턴스 | 화면 전환 중에도 같은 센서 세션을 유지 |
| `client/lib/app.dart` | `WidgetsBindingObserver` | background에서 pause/센서 stop, foreground에서 센서 start/resume |
| `client/ios/Runner/AppDelegate.swift` | Flutter EventChannel/MethodChannel 등록 | iOS native bridge와 Dart 연결 |
| `client/ios/Runner/PdrMotionBridge.swift` | CoreMotion·CMPedometer 수집 | heading, step peak, pedometer batch를 EventChannel으로 전달 |
| `client/lib/features/indoor_navigation/` | platform/application/contract 계층 | raw sensor → typed event → PDR 계산 → UI 계약 |

### 연구 앱 디렉터리에서 메인 앱으로의 이식 위치

원본 연구 앱은 `.local/indoor-sensor-navigation-mock/app/`에 보존한다. 메인 앱이 이
디렉터리를 import하지는 않으며, 제품에 필요한 책임만 아래 위치로 분리해 이식했다.

| 원본 연구 앱 위치 | 메인 앱 이식 위치 | 이식한 책임 |
|---|---|---|
| `lib/src/pdr/` | `packages/indoor_pdr_core/lib/src/` | 걸음·보폭·heading·경로 누적·품질 계산의 pure Dart 코어 |
| `lib/src/platform/` | `client/lib/features/indoor_navigation/platform/` | Dart 플랫폼 이벤트 타입과 iOS EventChannel adapter |
| `ios/Runner/PdrMotionBridge.swift` | `client/ios/Runner/PdrMotionBridge.swift` | CoreMotion·CMPedometer 기반 heading/peak/pedometer 수집 |
| `lib/src/pdr/pdr_engine.dart`의 앱 제어 책임 | `client/lib/features/indoor_navigation/application/` | 세션 시작·종료, lifecycle, 오류 상태, snapshot 전달 |
| `lib/src/ui/pdr_screen.dart`가 소비하던 상태 | `client/lib/features/indoor_navigation/contract/` | UI가 의존할 공개 타입·상태·intent 계약 |
| `test/`, 기록 세션 | `packages/indoor_pdr_core/test/`, `client/test/`, `client/integration_test/` | 계산 회귀와 실기기 하니스 검증 |

GPS 비교·세션 export·IMU 녹화·RoNIN/TFLite 실험 코드는 제품 이식 범위에서 의도적으로 제외했다.
따라서 기존 `IndoorMap` 화면에 로직을 직접 끼워 넣은 구조가 아니라,
`client/lib/features/indoor_navigation/` 독립 모듈을 앱 전역 lifecycle에 연결한 구조다.

### 이식 파일별 상세 책임

아래는 UI·지도 팀이 연결할 때 알아야 하는 추가/변경 파일의 실제 책임이다. `contract/` 밖의
구현 파일은 UI가 직접 import하지 않는다.

| 파일 | 입력 → 출력 | 상세 책임 / 변경 시 주의점 |
|---|---|---|
| `client/lib/app.dart` | Flutter lifecycle → driver 호출 | `WidgetsBindingObserver`로 앱 background/foreground를 감지해 PDR 세션을 pause/resume한다. 화면 전환만으로는 stop하지 않는다. |
| `client/lib/core/service_locator.dart` | 앱 시작 → 전역 단일 인스턴스 | `IosPdrMotionSource`와 `IndoorNavigationDriver`를 한 번 생성한다. 화면별로 driver를 새로 만들면 경로가 끊기므로 금지한다. |
| `client/ios/Runner/AppDelegate.swift` | Flutter messenger → EventChannel/MethodChannel | `navigation_client/pdr_motion`, `navigation_client/pdr_motion_cmd` 채널을 Swift bridge에 등록한다. 채널 이름은 Dart adapter와 반드시 같아야 한다. |
| `client/ios/Runner/PdrMotionBridge.swift` | CoreMotion/CMPedometer → tagged native event | DeviceMotion, 보행 방향 보조 신호, step peak, CMPedometer 배치를 모아 Dart로 보낸다. GPS·IMU export는 포함하지 않으며 `resetPedometer` 명령도 처리한다. |
| `platform/pdr_motion_source.dart` | 플랫폼별 구현 → 공통 센서 인터페이스 | `events`, `start`, `stop`, `resetPedometer`만 정의한다. Android 구현도 이 인터페이스를 구현하면 된다. |
| `platform/native_pdr_event.dart` | raw EventChannel `Map` → `HeadingEvent`/`AccelPeakEvent`/`PedometerBatchEvent` | native payload의 형식 검증과 typed 변환 경계다. raw `Map`은 이 파일 바깥으로 새지 않는다. |
| `platform/ios_pdr_motion_source.dart` | EventChannel/MethodChannel → `NativePdrEvent` stream | iOS 채널 구독을 열고 닫으며, raw 이벤트를 parser에 전달한다. PDR 수학이나 UI 상태는 여기 두지 않는다. |
| `application/indoor_navigation_controller.dart` | typed sensor event → snapshot·calibration·runtime stream | 앱 범위 세션 owner다. start/stop, background pause, 층 변경 reset, 센서 오류, pin/heading anchor 확정을 처리한다. UI는 이 구현체가 아니라 계약만 본다. |
| `contract/indoor_navigation_contract.dart` | UI import → 공개 PDR 타입 | UI용 barrel이다. `PdrSnapshot`, controller view/intents, anchor 관련 타입을 한 곳에서 노출한다. |
| `contract/indoor_navigation_view.dart` | 로직 → UI | `snapshots`, calibration, runtime status의 읽기 전용 stream과 최신 값을 제공한다. 마커·상태 indicator는 이것을 구독한다. |
| `contract/indoor_navigation_intents.dart` | UI 제스처 → 로직 명령 | `startGuidance`, `stopGuidance`, pin/heading anchor, 층 변경 명령을 정의한다. UI가 세션 내부를 직접 조작하지 않게 한다. |
| `contract/calibration_state.dart`, `pdr_anchor.dart` | 사용자 pin/방향 + PDR local point → floor `local_m` | 캘리브레이션 단계와 rigid transform을 정의한다. `canRenderPosition`이 true일 때만 지도에 위치를 그린다. 실제 축·북쪽 정렬값 검증은 Phase 3이다. |
| `contract/pdr_runtime_status.dart` | 센서 실행 결과 → 상태·warning code | `idle`부터 `degraded`까지의 앱 실행 상태를 제공한다. warning은 사용자 문구가 아니라 UI/telemetry가 해석할 코드다. |
| `packages/indoor_pdr_core/lib/indoor_pdr_core.dart` | 패키지 소비자 → public API | 계산 코어의 barrel이다. client와 테스트는 원칙적으로 이 공개 API만 import한다. |
| `application/pdr_session.dart` | heading + peak + pedometer batch → `PdrSnapshot` | PDR 계산의 orchestration이다. confirmed(초록) 경로와 accel preview(주황) 경로, 거리·걸음·품질 snapshot을 조합한다. |
| `application/pedometer_batch_processor.dart`, `tracking_timeline.dart` | 늦게 도착한 CMPedometer batch → 추적 중 step만 반영 | batch 중복·stale 세션을 걸러내고 background 경계를 가르는 동안의 step만 남긴다. lifecycle 정확도의 핵심이다. |
| `application/stride_estimator.dart` | Apple distance/cadence/pace → step distance | Apple distance 우선, cadence·pace 다음, 0.70m fallback 순서로 보폭을 고르고 급격한 변화는 smoothing한다. |
| `application/heading_trackers.dart`, `path_accumulator.dart` | DeviceMotion heading + step 시각 → confirmed 경로 | 팔 흔들림을 분리하고 보행 방향 offset을 추정한다. 배치 안 step도 해당 시점 heading으로 분산 배치해 코너가 한꺼번에 꺾이지 않게 한다. |
| `application/accel_preview_track.dart`, `quality_metrics.dart` | accel peak + confirmed 경로 → 주황 preview·경고 | accel 기반 경로는 진단용이다. confirmed 위치를 대체하거나 평균내지 않으며, 과다/과소 계수 의심을 warning으로만 노출한다. |
| `application/pdr_session_config.dart` | 제품/실험 설정 → PDR core | fallback 보폭, 경로 point 상한, 품질 임계값을 주입한다. 현 임계값은 실측 데이터로 재보정 대상이다. |
| `domain/events.dart`, `snapshot.dart`, `pdr_local_point.dart`, `quality.dart` | 각 계층 간 값 전달 | 플랫폼·앱·UI 사이에서 공유하는 immutable 데이터 모델이다. PDR 좌표는 `eastM/northM` 미터이며 LatLng가 아니다. |
| `debug/pdr_device_harness.dart`, `integration_test/pdr_device_smoke_test.dart` | 실기기 센서 → PASS/FAIL receipt | 제품 화면 없이도 센서 시작·걷기 snapshot·중단을 검증하는 standalone 하니스다. 실제 화면 진입 흐름을 검증하는 테스트와는 구분한다. |

## 3. 센서부터 UI 계약까지의 데이터 흐름

```mermaid
sequenceDiagram
  participant iOS as CoreMotion / CMPedometer
  participant Swift as PdrMotionBridge.swift
  participant Source as IosPdrMotionSource
  participant Driver as IndoorNavigationDriver
  participant Core as PdrSession
  participant UI as UI 계약 소비자

  UI->>Driver: startGuidance(floorId)
  Driver->>Source: start()
  Source->>Swift: EventChannel 구독
  Swift->>iOS: motion / pedometer 시작
  iOS-->>Swift: heading, step peak, pedometer batch
  Swift-->>Source: raw Map 이벤트
  Source-->>Driver: NativePdrEvent
  Driver->>Core: typed heading / peak / pedometer 이벤트
  Core-->>Driver: PdrSnapshot
  Driver-->>UI: snapshots / calibration / runtimeStatuses
  UI->>Driver: stopGuidance()
  Driver->>Source: stop()
```

### 계층별 책임

| 계층 | 주요 파일 | 하는 일 | 하지 않는 일 |
|---|---|---|---|
| Native iOS | `ios/Runner/PdrMotionBridge.swift` | CoreMotion, CMPedometer, native peak 수집 | 지도·UI·경로 렌더링 |
| Platform adapter | `platform/ios_pdr_motion_source.dart`, `native_pdr_event.dart` | EventChannel raw Map을 typed 이벤트로 변환 | PDR 수학·UI 상태관리 |
| PDR core | `packages/indoor_pdr_core/` | 걸음·보폭·heading·초록/주황 경로·품질 계산 | Flutter, 플랫폼 채널, 지도, GPS export |
| App controller | `application/indoor_navigation_controller.dart` | 세션 lifecycle, 오류 상태, calibration, snapshot 전달 | 위젯·지도 그리기 |
| Public contract | `contract/` | UI가 구독·호출할 타입만 노출 | 구현체 내부 노출 |
| UI / 지도 | 별도 트랙 | meter-space 렌더러, 핀·방향 보정 UX | 센서·PDR 계산 소유 |

## 4. PDR이 제공하는 기능

### 위치·경로

`PdrSnapshot`은 세션 시작점을 `(0, 0)`으로 하는 로컬 미터 좌표를 제공한다.

- `position`, `path`: **confirmed(초록)** 위치·경로. 제품 위치 판단의 기준이다.
- `preview`: **accel preview(주황)** 위치·경로. 실시간 보조 품질 신호이며 초록 위치와 평균내거나
  자동 전환하지 않는다.
- `steps`, `distanceM`, `walkingHeadingDeg`: 보행량과 진행 방향이다.

### 센서 실행 상태와 오류

`PdrRuntimeStatus`는 UI가 센서 상태를 표시하거나 오류를 안내할 수 있게 한다.

| 상태 | 의미 |
|---|---|
| `idle` | 안내·센서 세션이 꺼져 있음 |
| `starting` | EventChannel을 열고 첫 이벤트를 기다림 |
| `running` | native 이벤트를 PDR core로 전달 중 |
| `paused` | 앱 background로 tracking·센서를 멈춤 |
| `stopping` | 명시적 종료 처리 중 |
| `degraded` | 권한·센서·채널 오류로 정상 추적을 보장할 수 없음 |

오류가 발생하면 warning code가 runtime status와 이후 snapshot quality에 함께 들어간다. 예를 들어
`sensorStartFailed`, `sensorStreamError`, `sensorResumeFailed`가 있다.

### 캘리브레이션과 anchor

PDR 좌표는 지도 좌표가 아니므로, 지도에 표시하기 전에 anchor가 필요하다.

```text
floorPoint = R(rotationDeg) × pdrPoint + anchorLocalM
```

- 사용자가 지도에서 현재 위치를 찍으면 `confirmAnchorByPin()`으로 평행이동 기준을 정한다.
- heading reference가 arbitrary이면 `confirmAnchorByHeading()`으로 회전도 정한다.
- anchor가 확정되기 전 `canRenderPosition`은 false다. UI는 위치 마커를 그리면 안 된다.

현재 타입과 기본 변환 함수는 있지만, 실제 floor node/local_m 데이터로 축·원점·회전을 검증하는 작업은
Phase 3에 남아 있다.

## 5. 기존 화면과의 현재 관계

```mermaid
flowchart LR
  Indoor["IndoorMap\n현재: GeoJSON / 더미 마커"]
  Guide["RouteGuide\n현재: GeoJSON / 더미 마커"]
  Driver["IndoorNavigationDriver\n현재: 앱 범위 headless 서비스"]
  Contract["IndoorNavigationController\nUI 공개 계약"]
  Future["Phase 3 + UI 트랙\nlocal_m transform / renderer / calibration"]

  Driver --> Contract --> Future
  Future -. 실제 연결 후 .-> Indoor
  Future -. 실제 연결 후 .-> Guide
```

현재 앱에서 `startGuidance()`를 호출하는 production 화면은 없다. 실기기 검증용 standalone harness만
PDR 세션을 시작한다. 즉 다음 화면 작업은 PDR을 새로 만드는 일이 아니라, 이미 이식된 서비스를
사용자 흐름에 연결하는 일이다.

## 6. UI·지도 팀이 붙을 때의 사용 규칙

UI는 구현체 파일이 아니라 아래 barrel만 의존한다.

```dart
import 'package:navigation_client/features/indoor_navigation/contract/indoor_navigation_contract.dart';
```

권장 흐름은 다음과 같다.

1. 실내 안내 진입 시 앱 범위 `IndoorNavigationController`에 `await startGuidance(floorId: ...)`를 호출한다.
2. `runtimeStatuses`가 `running`이 될 때까지 센서 준비 상태를 표시한다.
3. `calibration`이 `awaitingPin`이면 floor map에서 사용자가 현재 위치를 찍게 한다.
4. `confirmAnchorByPin()` 또는 필요 시 `confirmAnchorByHeading()`을 호출한다.
5. `canRenderPosition == true`가 된 뒤에만 `snapshot.position`을 floor `local_m`로 변환해 렌더링한다.
6. IndoorMap ↔ RouteGuide 화면 전환 중에는 stop/reset하지 않는다.
7. 실내 안내 종료에서만 `await stopGuidance()`를 호출한다.

## 7. Phase 3 전에 node 팀과 맞춰야 할 계약

실제 지도 위 위치 표시는 다음 정보가 없으면 정확하게 검증할 수 없다.

| 필요한 node/floor 데이터 | 용도 |
|---|---|
| `floorId`, node id, `x`, `y` | PDR 결과를 올릴 floor `local_m` 기준점 |
| 좌표 단위(m) | px·LatLng와 혼용 방지 |
| 원점·축 규약 | east/north 방향과 부호 확정 |
| `north_alignment` | PDR heading과 floor 축의 회전 차이 |
| 입구·시작 node | 자동 또는 핀 기반 anchor 후보 |

edge/route geometry는 route snapping·map matching에는 필요하지만, 첫 위치 표시에는 위 node 좌표가
우선이다.

## 8. 검증 상태

| 검증 | 결과 |
|---|---|
| `indoor_pdr_core` | 10 tests 통과, analyze clean |
| client PDR·lifecycle·harness | 27 tests 통과, PDR 경로 analyze clean |
| iOS simulator | debug build 통과 |
| iPhone 13 Pro | 무선 profile harness PASS: 8걸음, 5.81m, warning 0건, stop 후 이벤트 중단 확인 |

전체 `flutter analyze`의 기존 19건은 별도 미추적 API/map/riverpod WIP에서 발생하며 PDR 변경 경로에는
새 오류가 없다.

## 참고 파일

- [전체 이식 계획](pdr-migration-plan.md)
- [UI 연동 계약](pdr-ui-contract.md)
- [PDR 공개 계약](../client/lib/features/indoor_navigation/contract/indoor_navigation_contract.dart)
- [앱 범위 controller](../client/lib/features/indoor_navigation/application/indoor_navigation_controller.dart)
- [iOS native bridge](../client/ios/Runner/PdrMotionBridge.swift)
