# PDR 제품 이식 설계 (v4)

연구 앱(`.local/indoor-sensor-navigation-mock/app`)에서 검증한 PDR을 메인 Flutter 앱
(`client`)에 제품 모듈로 이식하기 위한 설계 문서. 코드 검증과 검토(Codex + Claude)를 반영했다.

- 설명·주석은 한국어, 코드·식별자는 영어 (AGENTS.md 규칙).
- 이 문서는 설계만 담는다. 구현은 Phase 0부터 단계별로 진행하고 각 단계마다 테스트 후
  한국어 커밋을 만든다.
- **범위: 로직 + UI 연동 계약까지.** 위젯·화면·렌더러 등 표현 계층은 별도 트랙(UI팀)에서
  진행되며 이 문서의 구현 범위가 아니다 (결정 C).

---

## 0. 확정 방향과 선결 결정

### 그대로 가는 3대 방향

1. **`local_m` 기반 custom renderer로 전환** — 실내 지도는 flutter_map(LatLng 전용)이 아니라
   meter-space 커스텀 렌더러로 그린다. flutter_map은 야외 전용으로 유지한다.
2. **RoNIN/TFLite/ML asset은 제품 이식 범위에서 제외** — 파랑 경로는 거리 44~56% 과소추정으로
   제품 후보가 아니다. 메인 앱 의존성에 넣지 않는다.
3. **초록/주황 역할 분리** — 초록(confirmed PDR)은 제품 위치·경로 이탈 기준, 주황(accel preview)은
   독립 품질 신호이자 future fusion 연구 대상. 위치 좌표 평균·자동 전환에 쓰지 않는다.

### 선결 결정

| 결정 | 확정안 | 근거 |
|---|---|---|
| **A. untracked WIP 처리** | **손대지 않는다.** PDR 이식 범위와 충돌하지 않으면 그대로 둔다. 충돌하면 파일별 소유자·목적을 먼저 확인하고, 사용자가 명시적으로 승인한 경우에만 별도 백업 브랜치에 보존한다. riverpod은 도입하지 않는다. | `client/lib/features/`, `lib/state/`, `lib/data/`, `lib/core/config/`, `integration_test/`, `api/tests/integration/test_buildings_api.py` 등은 미추적 상태다. import되지 않는다는 사실만으로 죽은 코드로 확정할 수 없고, 테스트·API 파일은 사용자의 진행 중 작업일 수 있다. 삭제는 실질적으로 미추적 작업 삭제다. |
| **B. 실내 렌더링 기판** | **meter-space 커스텀 렌더러**(CustomPaint + InteractiveViewer). flutter_map은 야외 전용. **단, 렌더러 구현은 UI팀 몫**(결정 C 참조). 우리는 렌더러가 소비할 좌표·모델·변환만 제공. | 백엔드가 navigation geometry를 `local_m`으로 내려주고 PDR도 로컬 미터다. flutter_map에 얹으려면 가짜 투영이 필요하다. `CrsSimple` 대안은 보류 항목. |
| **C. UI 범위 분리** | **UI(위젯·화면·렌더러·캘리브레이션 제스처·품질 indicator)는 별도 작업으로 진행된다. 우리 범위는 "로직 + UI가 붙을 계약(인터페이스)"까지다.** 실제 픽셀을 그리는 코드는 만들지 않는다. | 지도 렌더러·화면·overlay는 다른 트랙에서 개발된다. 로직/계약과 표현을 분리하면 양쪽이 병렬 작업할 수 있고, 코어의 테스트 가능성도 지켜진다. |

### 범위 경계 (결정 C 상세)

| 영역 | 우리(로직·계약) | UI팀(표현) |
|---|---|---|
| PDR 계산 코어 (`indoor_pdr_core`) | ✅ 전부 | — |
| 센서 브릿지 + 세션 lifecycle 컨트롤러 (headless) | ✅ | — |
| 좌표 변환·anchor·캘리브레이션 **상태기계** | ✅ | — |
| `FloorMapResponse` local_m **파서/모델** | ✅ | — |
| 품질 판정 (`PdrQuality`, features, 임계값) | ✅ | — |
| meter-space **렌더러**(CustomPaint) | — | ✅ |
| IndoorMap/RouteGuide **화면**, overlay 위젯 | — | ✅ |
| 캘리브레이션 **UI**(핀/방향 제스처) | — | ✅ |
| quality **indicator 위젯**, debug 주황 toggle | — | ✅ |

원칙:
- 우리는 순수 `Stream`/인터페이스/값 타입만 노출하고 **어떤 상태관리(riverpod 등)도 강제하지 않는다.** UI팀이 감싼다.
- 세션 lifecycle 컨트롤러는 **우리가 headless 로직으로 소유**한다. UI는 관찰만 한다 (Phase 2).
- UI가 붙을 계약은 **Phase 1 직후 별도 산출물**로 앞당겨 확정한다. UI팀이 코어 완성을 기다리지 않고 병렬 작업하도록.

---

## 1. 현 구조 조사 결과 — 이식 가능/불가능 영역

### 메인 앱 (client)
- 화면 흐름: Splash → OutdoorMap → **IndoorMap → Destination → RouteGuide** → Arrival.
  라우팅은 `lib/app.dart` 정적 테이블.
- DI: `lib/core/service_locator.dart` — 전역 final + 테스트 교체용 함수 변수 패턴. **이 패턴을 따른다.**
- **권한 준비 완료**: Info.plist `NSMotionUsageDescription`, 스플래시에서 `activityRecognition`
  요청, Android `ACTIVITY_RECOGNITION`. Phase 2에서 추가 작업 최소.
- `lib/models/floor_plan.dart`는 mock GeoJSON(LatLng) 파서로 백엔드 `local_m` 스키마보다 뒤처진
  레거시. IndoorMap/RouteGuide 현재 위치는 더미(`indoor_map_screen.dart:146`).

### 백엔드 API — 좌표계 경계 (중요)
- **navigation 핵심 geometry는 전부 `local_m`**: route `path_points`, edge `geometry_local_m`
  (`buildingService.py:153`), stores/pois/footprint (`floor_map.py`의 `*_local_m`).
- **`vector_map`(SVG 벽/장식 레이어)만 `svg_viewbox_px`**(`floor_map.py:21`, 단위 px).
  **px ↔ local_m 변환 필드는 어디에도 없다.**
- 없는 것: 진북 정렬각, 지자기 편차, 지리참조 anchor. → 산출물 4에서 API 확장으로 해결.

### 연구 앱 — 이식 분류

| 분류 | 모듈 | 비고 |
|---|---|---|
| 그대로 추출 (Flutter 비의존) | `stride_estimator`, `pedometer_batch_processor`, `tracking_timeline`, `heading_timeline`(GPS 비교 함수 제외), `heading_tracker`(HeadingHistory/SwingDetector/WalkOffsetEstimator), `angle_utils`, `realtime_candidate_metrics`, `native_motion_event`, `pdr_types` | 복사 후 재작성. 원본 read-only |
| Offset 교체 후 추출 | `path_accumulator`, `accel_preview_track` | `dart:ui Offset` → 자체 `PdrLocalPoint` |
| 참조만 (재작성) | `pdr_engine`(763줄) | `ValueNotifier`(flutter/foundation) + GPS·IMU v3·ML·export 혼재. 오케스트레이션만 참고 |
| 이식 제외 | `gps_reference_track`, `gps_path_comparison`, `imu_v3_recorder`, `pdr_export`, `ml/**`, `mlObservations` | 정책 6·7 |
| Swift bridge 이식 부분 | CoreMotion deviceMotion 100Hz(fused heading, attitude, walkDir), CMPedometer, native accel peak, thermal/LPM | 741줄 중 절반 이하 |
| Swift bridge 제외 부분 | CLLocationManager GPS(client는 geolocator), IMU v3 100Hz export 버퍼 | |

---

## 2. 의존성 경계

```
[읽기 전용] .local/…/app  ──(코드 참조·복사만, import 절대 금지)──▶

packages/indoor_pdr_core/          ← pure Dart (dart:math만. Flutter SDK 의존 0)          [우리]
    ▲ path dependency
client/lib/features/indoor_navigation/
    platform/     typed PdrMotionSource + iOS bridge adapter   ← flutter/services 허용     [우리]
    application/  IndoorNavigationController(앱 범위 세션 소유, headless)                   [우리]
    mapping/      FloorCoordinateTransform, PdrAnchor, FloorMapModel(local_m 파서)          [우리]
    ── 위까지가 우리 범위. 아래는 계약(Stream/인터페이스)으로만 연결 ──
    presentation/ meter-space 렌더러, overlay, quality indicator, 캘리브레이션 UI          [UI팀]
```

- `indoor_pdr_core`는 주입된 이벤트와 clock만 사용. 내부 타이머·플랫폼 채널·JSON export 금지.
  진단 데이터는 구조체로 노출하고 직렬화는 client 몫.
- raw `Map`은 platform adapter에서 typed event로 변환 후 폐기. core에 `Map<dynamic,dynamic>` 금지.
- **UI 경계는 계약으로만 넘는다**: 우리 쪽은 `Stream<PdrSnapshot>`·상태·순수 함수를 노출하고,
  UI팀은 그걸 구독/호출한다. 우리 코드는 위젯을 import하지 않고, UI팀 코드는 우리 내부 구현을
  import하지 않는다(계약 파일만). 상태관리 방식은 UI팀 자유.

---

## 3. Public Dart API 초안 (`packages/indoor_pdr_core`)

```dart
// ── domain ──
class PdrLocalPoint { final double eastM, northM; }          // Offset 대체

class HeadingEvent {
  final int tMs;
  final double fusedHeadingDeg;                  // reference에 따라 자북 또는 arbitrary
  final bool headingStable;
  final double? walkDirDeg, walkDirConfidence;   // WalkOffsetEstimator 입력
  final double? pitchDeg, rollDeg;               // quality feature
}

class PedometerBatchEvent {
  final int receivedAtMs, steps; final int? stepSessionId, sessionStartMs;
  final double? timestampMs, distanceM, cadenceHz, paceSecPerM;
  final bool? distanceAvailable, cadenceAvailable, paceAvailable;
  final List<double>? stepPeakTimes;
}

class AccelPeakEvent { final int count; final int? latestPeakMs; final num? motionTimestampMs; }

class PdrSnapshot {
  final PdrLocalPoint position;           // 초록 confirmed (제품 위치)
  final List<PdrLocalPoint> path;
  final int steps; final double distanceM;
  final double walkingHeadingDeg;
  final PdrPreview preview;               // 주황: position/path/steps/distanceM
  final PdrQuality quality;
}

enum PdrQualityState { healthy, caution, degraded }
class PdrQuality {
  final PdrQualityState state;
  final List<String> warnings;            // realtime_candidate_metrics.warnings 계승
  final PdrQualityFeatures features;      // 산출물 5 (fusion 학습용 원자료)
}

// ── application ──
class PdrSession {
  PdrSession({PdrSessionConfig config});
  void onHeading(HeadingEvent e);
  void onPedometerBatch(PedometerBatchEvent e);
  void onAccelPeak(AccelPeakEvent e);
  void pause({required int atMs});        // TrackingTimeline 전이
  void resume({required int atMs});
  void reset({int? newStepSessionId});    // 층 변경 시
  PdrSnapshot get snapshot;
  Stream<PdrSnapshot> get snapshots;      // confirmed step 반영 시 emit
}
```

client 쪽 계약:

```dart
abstract interface class PdrMotionSource {   // 연구 앱 Stream<Object?>의 typed 승격판
  Stream<PdrMotionEvent> get events;         // heading | pedometer | accelPeak sealed union
  Future<int?> resetPedometer();
  Future<void> start(); Future<void> stop();
}
```

---

## 4. Anchor / 캘리브레이션 데이터 계약

### 좌표계 정의
- PDR frame: 원점 = 세션 시작점, +east/+north.
  **heading reference는 고정이 아니다** (아래 참조).
- Floor frame: API `local_m` (원점·축은 ETL 산출물 고유).
- 변환: `floorPoint = R(rotationDeg) · pdrPoint + anchorLocalM` (2D rigid transform).

### Heading reference 처리 (필수)
연구 앱 iOS bridge(`PdrMotionBridge.swift:250-254`)는 `.xMagneticNorthZVertical`을 우선 쓰되,
미가용 시 `.xArbitraryCorrectedZVertical`로 fallback한다. 후자는 yaw가 자북 기준이 아니다.

```dart
enum HeadingReference { magneticNorth, arbitraryCorrected }

class PdrAnchor {
  final String floorId;
  final PdrLocalPoint anchorLocalM;             // PDR 원점이 놓이는 floor 좌표
  final double rotationDeg;                      // PDR heading frame → floor frame 회전
  final HeadingReference headingReference;
  final bool requiresManualRotationCalibration;  // arbitrary면 항상 true
  final AnchorSource source;                     // entranceGate | userPin | manualHeadingCal
  final double confidence;
}
class FloorCoordinateTransform { PdrLocalPoint toFloor(PdrLocalPoint pdr); }
```

- **`magneticNorth` reference일 때만** 서버의 `magnetic_north_offset_deg`를 적용한다.
- **`arbitraryCorrected` fallback이면** 서버 오프셋을 쓰지 않고 반드시 수동 방향 보정 또는
  입구 진행방향 보정을 강제한다(`requiresManualRotationCalibration = true`).

### API 확장 제안 (`FloorMapResponse`)
```
north_alignment: {
  magnetic_north_offset_deg: float   # floor local_m +y축과 자북 사이 각
  calibrated: bool                   # false면 클라이언트는 "지도 정렬 미보정" 모드
}
```
- 자북 기준으로 정의해 지자기 편차(declination) 문제를 회피(PDR heading도 자북 기준이면 상쇄).
- anchor 위치 후보는 이미 존재: `StoreResponse.entrance_local_m`, gate 타입 `PoiResponse` —
  건물 진입 판정 시 진입 gate를 anchor로.
- **`calibrated:false`이거나 anchor 미확정이면 지도 위 위치를 그리지 않는다.** 대신 ① 입구 시작 안내,
  ② 상대 궤적만 별도 표시, ③ 수동 캘리브레이션 UI(핀 + 진행방향)를 노출. (제약 6)

### SVG 벽 레이어 정합 계약 (Phase 3 필수)
`vector_map`은 `svg_viewbox_px`이고 px↔m 변환이 없다. 따라서:
- meter-space 렌더러는 **local_m 레이어(footprint/edges/stores/pois/route/PDR)만 정합을 보장**한다.
- **SVG `vector_map` 벽 레이어는 백엔드가 `local_m` geometry 또는 `svg_viewbox_px→local_m` affine을
  제공하기 전까지 정합을 주장하지 않는다** (미제공 시 렌더 생략 또는 "미정합" 표기).
- 백엔드 이슈로 발행: vector geometry의 `local_m` 제공 또는 변환 계약.

---

## 5. 초록/주황 품질 상태와 future fusion 데이터 계약

### 품질 입력 (`PdrQualityFeatures` — fusion 라벨 데이터와 동일 스키마)
```
greenOrangeDistanceDivergencePct   // |orange−green|/green
orangeStepRatio                    // orangeSteps/greenSteps
orangeOvercountLikely              // accelOvercountLikely (임계 1.3× — 잠정)
pedometerHealth                    // undercountScan 결과 (flaggedSpanS 등)
peakRejectHistogram                // tooDense/stepLeadCap/…
headingStableRatio, cadenceHz, batchGapMs, pitchDeg/rollDeg
headingReference                   // magneticNorth | arbitraryCorrected
```

### 판정 규칙 (전부 config 주입 잠정치)
- `degraded`: 센서 오류/권한 상실/heading 장기 unstable/`pedometerUndercountSuspected`+
- `caution`: divergence > 10% **또는** `orangeOvercountLikely` **또는** batch 지연 과다
- `healthy`: 그 외
- **divergence 단독으로 degraded 판정 금지.** 근거: 13-49 세션은 divergence 18.2%였지만 초록
  closure 3.5%로 정상(주황 과검출). 기존 1.3× 임계도 이 세션(1.198×)을 못 잡으므로 **Phase 5
  라벨 데이터로 재보정 대상**임을 config 주석에 명시.
- undercount 플래그는 진단 전용, **초록→주황 자동 전환에 사용 금지**
  (`realtime_candidate_metrics.dart:88-96`의 오탐 모드: 제자리 흔들기·에스컬레이터).

### Fusion 연구 계약 (Phase 5, 연구 앱에서 수행)
- 대상은 **구간 거리만**. 초록·주황이 heading 계통 공유(accel_preview_track도 같은 `headingAt` 사용).
- 라벨: known-distance 직선 / known-loop / 실측 복도. 기록은 기존 `pdr_sensor_lab.session.v3` +
  실측 거리 필드만 추가.
- 위치 좌표 평균·endpoint-only 보정·근거 없는 고정 가중치 금지 (정책 3).

---

## 6~7. 단계별 계획 + 파일/테스트/완료 기준

### Phase 0 — baseline 정리 (비파괴)
- 작업: **untracked WIP은 손대지 않는다.** `flutter analyze` 현 상태 확인,
  `client/pubspec.yaml`에 `indoor_pdr_core` path 의존성 자리 확보(빈 패키지 스캐폴딩).
- 완료 기준: 기존 위젯 테스트 통과, analyze 신규 error 0, untracked 파일 변경 0건.

### Phase 1 — `packages/indoor_pdr_core` + 재작성 + replay parity
- 생성: 산출물 3의 domain/application 전부. `PdrSession`은 pdr_engine 오케스트레이션 재작성.
  `Offset`→`PdrLocalPoint`, `ValueNotifier`→`Stream`.
- 테스트 ① synthetic typed event 단위 테스트 (stride 우선순위, batch split, heading 보간, peak gate).
- 테스트 ② **거리·걸음수 회귀 (기존 두 세션)**: `eventLog.pedometerBatches`(full-fidelity)를 재생 →
  - 13-55: 초록 102.63m/131보, 주황 107.57m/139보
  - 13-49: 초록 61.73m/81보, 주황 72.97m/97보
  - 경로 길이 = Σ(stride distance)로 heading과 무관하므로 사실상 정확 재현이 목표.
- 테스트 ③ **shape/closure parity**: 이건 100ms downsampled heading 손실·이벤트 순서에 민감하므로
  기존 세션으로는 근사만 확인하고, **향후 세션부터 정렬된 typed event trace를 v3 export에 추가**해
  정밀 검증한다(아래 스키마).
  ```
  trace 항목: sequence, receivedAtMs, sensorTimestampMs, eventKind,
              heading|pedometer|accelPeak payload, trackingTransition
  ```
- 완료 기준: `dart test` 통과 + 거리·걸음수 정확 재현.

### Phase 1.5 — UI 연동 계약 확정 (앞당김, UI팀 병렬 착수 지점)
UI팀이 코어 완성을 기다리지 않도록 계약을 먼저 못박는다. 코드가 아니라 **인터페이스 + 문서**가 산출물.
- 생성:
  - `client/lib/features/indoor_navigation/contract/`에 UI가 의존할 공개 타입만 모은 배럴 —
    `PdrSnapshot`(재노출), `IndoorNavigationView`(관찰용 인터페이스: `Stream<PdrSnapshot> snapshots`,
    `Stream<CalibrationState> calibration`, `PdrQuality get quality`),
    `IndoorNavigationIntents`(UI→우리: `confirmAnchorByPin`, `confirmAnchorByHeading`, `changeFloor`,
    `startGuidance`, `stopGuidance`).
  - `FloorCoordinateTransform.toFloor(PdrLocalPoint)` 시그니처 확정(순수 함수).
  - `CalibrationState` 열거/상태 정의(미보정·핀대기·방향대기·확정, `requiresManualRotationCalibration` 포함).
  - `docs/pdr-ui-contract.md`: UI가 구독하는 것 / 주는 것 / 좌표를 지도에 얹는 법 / 미보정 시 "위치
    그리지 않기" 규약(§4) 명시.
- 테스트: 계약 타입만으로 컴파일되는 fake 구현 + 계약 준수 테스트.
- 완료 기준: UI팀이 이 계약만 보고 렌더러/화면 작업을 병렬 시작할 수 있다. 위젯 코드 0.

### Phase 2 — iOS typed bridge + session lifecycle (headless)
- 생성: `PdrMotionBridge.swift` 최소 이식판(CoreMotion+CMPedometer+peak, GPS/IMUv3 제외)을 client
  `ios/Runner/`에, `platform/ios_pdr_motion_source.dart`, `application/indoor_navigation_controller.dart`.
- **세션 owner 단일화**: `IndoorNavigationController`(앱 범위)가 세션을 소유한다.
  - anchor 확정 + 실내 안내 시작 시 `start`.
  - IndoorMap ↔ RouteGuide ↔ calibration sheet 전환에는 **세션 유지**(stop/reset 안 함).
  - 실내 안내 종료·층 변경·명시 reset에서만 stop/reset.
  - `AppLifecycleState` background → pause(`TrackingTimeline` 전이), foreground → resume.
  - 권한 거부 → `degraded` + 안내.
- 테스트: fake `PdrMotionSource`로 controller 단위 테스트(구독/해제/화면 전환 시 세션 유지/pause 경계),
  실기기 스모크.
- **헤드리스 검증 하니스**: 제품 UI 대신, 코어→브릿지→컨트롤러가 도는지 확인하는 최소 example/CLI 또는
  위젯 테스트 하니스(제품 화면 아님). UI팀도 이걸 참고해 개발.
- 완료 기준: 실기기 세션 시작→걷기→snapshot 갱신(하니스 로그로 확인), 화면 전환 시 세션 유지, 안내 종료
  시 정지 확인. **위젯/화면 코드는 만들지 않는다.**

### Phase 3 — 좌표계 로직 + local_m 파서 + anchor/캘리브레이션 상태기계 (렌더링 제외)
UI팀이 그릴 렌더러·화면·캘리브레이션 제스처는 **범위 밖**. 우리는 그들이 소비할 로직·모델만 만든다.
- 생성: `FloorMapModel`(FloorMapResponse `local_m` 파서, 레거시 GeoJSON 파서 대체),
  `mapping/`의 `PdrAnchor`/`FloorCoordinateTransform`(순수), 캘리브레이션 **상태기계**
  (Phase 1.5의 `CalibrationState` 구현 — 미보정/핀대기/방향대기/확정 전이),
  heading reference 분기(magneticNorth vs arbitraryCorrected, §4).
- SVG 벽 레이어 정합 계약(§4): 변환 없으면 파서는 px geometry를 "미정합"으로 표시만 하고 local_m로
  올리지 않는다. 실제 렌더 판단은 UI팀 몫이지만, 데이터에 정합 여부 플래그를 실어 보낸다.
- API: `north_alignment` 필드 확장(백엔드 이슈, 값 없으면 `calibrated:false` 경로).
- 테스트: transform 왕복, 파서, 캘리브레이션 상태 전이, arbitrary reference 시
  `requiresManualRotationCalibration=true` 확인. **위젯 테스트 없음(위젯이 없으므로).**
- 완료 기준: UI팀이 `FloorCoordinateTransform`으로 PDR 좌표를 지도 좌표로 변환 가능, 미보정/미정합
  상태가 데이터로 정확히 노출됨.

### Phase 4 — 품질 판정 로직 + 진단 데이터 노출 (위젯 제외)
quality indicator 위젯·debug 주황 toggle은 **UI팀**. 우리는 판정 로직과 노출 데이터만.
- 생성: `PdrQuality`/`PdrQualityFeatures` 계산(§5), 세션 진단 요약 구조체(직렬화 가능, v3 부분집합),
  임계값 config.
- 테스트: 13-49 재생 시 "divergence 18%이지만 degraded 아님" 회귀 케이스 고정, 품질 상태 전이 테스트.
- 완료 기준: 임계값 전부 config 주입(하드코딩 0), 품질 상태·features가 계약(Phase 1.5)대로 스트림에 실림.

### Phase 5 — labeled route conditional distance fusion 실험 (연구 앱, 제품 코드 무수정)
- known-distance/known-loop 수집 프로토콜 + 실측 거리 필드, feature 세트는 §5와 동일 스키마.
- 완료 기준: 초록·주황 조건별 오차 리포트. 제품 반영은 별도 결정 후.

### Phase 6 — Android adapter
- `AndroidPdrMotionSource` 설계+구현: SensorManager(ROTATION_VECTOR/heading), Step Counter/Detector,
  CMPedometer 부재 대응(distance/cadence 없음 → stride fallback 검증), 동일 typed contract.
- 완료 기준: iOS와 동일 unit/replay 테스트를 Android 이벤트 시뮬레이션으로 통과 + 실기기 검증.

각 Phase 종료마다: 테스트 통과 → 한국어 커밋.

---

## 8. 보류 항목과 이유

| 항목 | 이유 |
|---|---|
| untracked WIP 삭제/이동 | 미추적 사용자 작업일 수 있음. 명시 승인 없이 손대지 않음 (결정 A) |
| riverpod 도입 | 필요 근거 없음. service locator 패턴으로 충분 |
| flutter_map `CrsSimple` 실내 렌더 | meter-space 캔버스가 기각될 때의 차선책으로만 |
| SVG 벽 레이어 정합 | 백엔드 px↔local_m 변환 계약 전까지 정합 미주장 |
| fusion 제품 적용 | Phase 5 라벨 데이터 전까지 근거 없음 (정책 4) |
| map matching / route constraint | PDR core 밖 후속 계층 |
| RoNIN/TFLite/ML asset | 거리 44~56% 과소추정, 제품 후보 아님 (정책 6) |
| 진북/지자기 편차 자동 보정 | 자북 기준 계약으로 회피. 필요 시 별도 설계 |
| 백그라운드 센서 동작 | 세션은 화면 활성 중만 (제약 7) |
| undercount 플래그의 자동 경로 전환 활용 | 오탐 모드 때문에 진단 전용 유지 |

---

## 변경 이력
- **v4**: UI 범위 분리(결정 C) — 위젯·화면·렌더러·캘리브레이션 제스처·품질 indicator는 UI팀 몫,
  우리는 로직 + 계약까지. 범위 경계 표(§0), UI 경계는 계약으로만(§2), Phase 1.5(UI 연동 계약 앞당김)
  신설, Phase 2에 헤드리스 하니스 추가, Phase 3(렌더링 제외·좌표/파서/상태기계만)·Phase 4(위젯
  제외·판정 로직만) 재정의.
- v3: untracked WIP 비파괴 처리(결정 A), SVG px↔local_m 정합 계약(§4), heading reference
  fallback 처리(§4 `HeadingReference`), replay parity를 거리 회귀(기존 세션)+shape trace(향후)로 분리
  (Phase 1), 세션 owner 단일화(Phase 2).
- v2: LatLng affine → local_m rigid transform, 렌더링 기판 결정 추가, 코어 추출/재작성 명시.
- v1: Codex 초안.
