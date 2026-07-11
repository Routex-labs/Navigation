# PDR 실내 내비게이션 — UI 연동 계약

UI팀이 실내 PDR 로직에 붙기 위한 계약. 이 문서 + `client/lib/features/indoor_navigation/contract/`
의 인터페이스만 보고 렌더러·화면·캘리브레이션 UI를 **병렬로** 개발할 수 있다.

- 로직/계약은 우리, 픽셀(위젯·렌더러·화면·제스처)은 UI팀 (설계 v4 결정 C).
- UI는 `contract/indoor_navigation_contract.dart` 배럴만 import한다. 구현체 내부는 import하지 않는다.
- 상태관리 방식(riverpod·provider·setState 등)은 UI팀 자유. 우리는 순수 `Stream`/인터페이스만 노출한다.

## 경계 요약

```
[로직/우리]                                   [계약]                    [UI/UI팀]
IndoorNavigationController (headless)  ──snapshots: Stream<PdrSnapshot>──▶  meter-space 렌더러
  · PdrSession(코어)                    ──calibration: Stream<Calib…>──▶   캘리브레이션 UI
  · 센서 브릿지 / 세션 lifecycle        ◀──Intents(start/stop/anchor)────   화면·제스처
  · FloorCoordinateTransform 제공                                          quality indicator
```

## 1. 읽기 — `IndoorNavigationView` (로직 → UI)

| 멤버 | 타입 | 의미 |
|---|---|---|
| `snapshots` | `Stream<PdrSnapshot>` | 초록 위치·경로, 주황 preview, 품질. confirmed step/preview 갱신 시 방출 |
| `currentSnapshot` | `PdrSnapshot?` | 최근 스냅샷(세션 시작 전 null) |
| `calibration` | `Stream<CalibrationStatus>` | 캘리브레이션 상태 변화 |
| `currentCalibration` | `CalibrationStatus` | 최근 캘리브레이션 상태 |

### `PdrSnapshot` (indoor_pdr_core 재노출)
- `position: PdrLocalPoint` — 초록 confirmed 위치(**PDR 로컬 미터**, 세션 시작점 기준). 지도에 얹으려면 §3 변환 필요.
- `path: List<PdrLocalPoint>` — 초록 경로.
- `steps`, `distanceM`, `walkingHeadingDeg`, `hasHeading`.
- `preview: PdrPreview` — 주황(accel) 위치·경로·걸음수·거리. **독립 품질 신호이며 위치의 진실값이 아니다.** 기본 UI는 디버그에서만 노출.
- `quality: PdrQuality` — `state`(healthy/caution/degraded), `warnings`, `features`.

## 2. 쓰기 — `IndoorNavigationIntents` (UI → 로직)

| 메서드 | 용도 |
|---|---|
| `startGuidance({floorId})` | 실내 안내 시작. anchor 확정 절차 개시 + 센서 세션 ON |
| `stopGuidance()` | 안내 종료. 세션 OFF |
| `confirmAnchorByPin({floorPointM})` | 사용자가 지도에 찍은 현재 위치(floor local_m)로 anchor 위치 확정 |
| `confirmAnchorByHeading({floorHeadingDeg})` | 진행 방향을 지도 기준으로 맞춰 회전 확정 (arbitrary reference에서 필수) |
| `changeFloor({floorId})` | 층 변경. 세션 reset + 새 층 anchor 재요구 |

세션은 앱 범위 컨트롤러가 소유한다. IndoorMap ↔ RouteGuide ↔ calibration sheet 화면 전환에는 세션이
유지된다. 화면 전환마다 start/stop을 호출하지 말 것.

## 3. 좌표 변환 — `FloorCoordinateTransform`

PDR 위치는 로컬 미터(세션 시작점 원점)다. 지도에 그리려면 floor `local_m`로 변환한다.

```dart
final t = FloorCoordinateTransform(anchor);   // anchor: 캘리브레이션 결과
final floorPoint = t.toFloor(snapshot.position);  // floor local_m
```

- `floor = R(rotationDeg)·pdr + anchorLocalM` (2D rigid transform, 순수 함수).
- 축·부호 규약은 Phase 3에서 실제 floor 데이터로 최종 검증한다.

## 4. 캘리브레이션 상태기계 — `CalibrationStatus`

| phase | UI 동작 |
|---|---|
| `uncalibrated` | **위치 마커를 그리지 않는다.** "입구에서 시작" 안내 |
| `awaitingPin` | 지도에 현재 위치 찍기 요청 → `confirmAnchorByPin` |
| `awaitingHeading` | 진행 방향 맞추기 요청 → `confirmAnchorByHeading` (arbitrary reference에서만) |
| `calibrated` | anchor 확정. 지도 위 위치 렌더 가능 |

- `canRenderPosition` — anchor 확정 시에만 true. **false면 지도 위 위치를 그리지 않는다**(없는 정확도를
  그리는 척 금지, §4).
- `requiresManualRotationCalibration` — heading이 arbitrary corrected fallback이라 서버 자북 정렬각을
  못 쓰고 수동 방향 보정이 필요한 상태. true면 `awaitingHeading`을 건너뛰지 말 것.
- `headingReference` — `magneticNorth` | `arbitraryCorrected`.

## 5. 품질 표시 — `PdrQuality`

- `state`: `healthy` / `caution` / `degraded`. indicator 색/문구는 UI팀 결정.
- `warnings`: 문자열 목록(예: `pedometerUndercountSuspected`, `distanceInflationLikely`).
- `features`: 진단·telemetry 원자료(§ 설계 v4 §5). 임계값은 잠정이며 Phase 5에서 재보정된다.
- 주황(preview) 경로 토글은 **디버그 빌드 한정** 권장.

## 참고
- 계약 코드: `client/lib/features/indoor_navigation/contract/`
- 계약 conformance/변환 테스트: `client/test/features/indoor_navigation/contract_test.dart`
- 전체 이식 설계: [pdr-migration-plan.md](pdr-migration-plan.md)
