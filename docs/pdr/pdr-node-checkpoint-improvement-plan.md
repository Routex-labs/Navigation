# PDR 실시간 위치·방향·길안내·체크포인트 개선 계획

- 작성일: 2026-08-06
- 상태: 구현 중 — Phase 0~3 적용, shadow 실측 뒤 Phase 4 활성화
- 범위: Flutter 클라이언트 PDR 표시 위치, heading, 경로 진행, node 체크포인트, 디버그 기록
- 코드 대조 기준: `main@e4b269a` 별도 checkout 검증 결과와 로컬 `codex/pdr-route-floor-transition@1eb7b7c`
- 관련 문서: [PDR 경로 추종·층 전환 개선 계획](pdr-route-and-floor-transition-improvement-plan.md)

이 문서는 주황 accel preview의 빠른 반응을 실제 마커에 사용하면서, 길안내 진행률의 안정화가
마커 위치와 방향까지 붙잡는 문제를 제거하고, 활성 안내 경로의 waypoint를 이용해 누적 위치 오차를
구간별로 끊는 후속 계획이다.

기존 confirmed/optimistic beam, junction transition zone, 경로 재탐색과 층 전환 구조는 관련 문서를
단일 출처로 삼는다. 이번 문서는 그 위에서 **위치·방향·길안내 진행률·체크포인트의 책임을 분리**하는
변경만 다룬다.

이번 범위에서 waypoint는 위치 체크포인트로만 사용한다. waypoint 사이 거리와 주황 peak 수로
보폭을 자동 학습하는 기능은 구현하지 않는다.

### 2026-08-06 구현 현황

- Phase 0: 야외 recorder 결선, 네 heading·peak traversal·route signed 이동·measured/display
  진행률과 세션 종료 경계를 schema v14에 기록한다.
- Phase 1: 실제 마커는 항상 optimistic tracker 위치를 쓰고, 화살표는
  `orientationHeadingDeg`만 사용한다.
- Phase 2: heading-only 100°/120° 제품 판정을 제거하고, 서로 다른 preview peak 3개와 누적
  1.2m를 초기값으로 쓰는 `TravelDirectionState`로 안내를 이관했다.
- Phase 3: 활성 경로의 graph node ID·순서와 9m 간격을 쓰는 checkpoint shadow ledger를
  적용했다. 모든 비정상 방향·모호·재배치·재탐색 상태는 commit 예상 판정에서 제외한다.
- Phase 4의 실제 soft rebase와 최근 궤적 presentation은 아직 제품 위치에 적용하지 않는다.
  계획에 적은 대로 shadow fixture·실측에서 1~1.5m 상한과 오탐을 확인한 뒤 활성화한다.

---

## 1. 구현 전에 고정할 검증 기준

다음 조건을 모두 만족해야 구현이 완료된 것으로 본다.

| 구분 | 완료 기준 |
|---|---|
| 마커 반응성 | 유효한 accel peak가 들어오면 다음 preview snapshot에서 실제 마커와 최근 보행선이 이동한다. confirmed batch나 길안내 진행률 승인을 기다리느라 한 보폭 이상 멈추지 않는다. |
| 위치 독립성 | 길안내 진행률을 보류하거나 이전 값으로 유지해도 실제 마커는 `CorridorPositionTracker`의 optimistic 위치를 계속 따른다. |
| 방향 독립성 | 마커 화살표는 기기 orientation heading을 따르고, 경로 접선·간선 접선·복도 heading bias가 화살표를 강제로 돌리지 않는다. |
| 역방향 반응 | 첫 강한 역방향 preview 걸음부터 마커와 최근 보행선은 즉시 반대로 이동한다. 안내 문구는 2~3개의 독립 걸음 증거 뒤에 확정한다. |
| 진행률 안정성 | 한 프레임의 위치 재배치·투영 점프는 남은 거리와 파란선을 흔들지 않는다. 이 안정화가 실제 마커 위치로 역전파되지 않는다. |
| 체크포인트 정확도 | 활성 안내 경로의 다음 waypoint만 순서대로 처리한다. 강한 회전점과 조건을 통과한 직선 waypoint 외에는 위치를 재기준화하지 않는다. |
| soft rebase 연속성 | 약한 체크포인트 확정 프레임의 마커 점프는 0.5m 이하이고, 0.5~1.5m residual은 정상 걸음 2~4개에 걸쳐 제거한다. |
| 배치 독립성 | 같은 peak·heading 입력은 pedometer batch 크기와 도착 시점이 달라도 같은 마커 시계열, 역방향 상태와 체크포인트 결과를 만든다. |
| 이동 사건 무결성 | 한 peak가 node를 넘어가도 전체 이동거리가 한 번만 기록되고 부호가 뒤집히지 않는다. leader 재배치는 걸음 거리와 방향 증거에 포함되지 않는다. |
| 지연 내성 | iOS 첫 confirmed batch가 15~20초 늦거나 중간 batch가 일시적으로 끊겨도 정상 주황 위치가 고정되지 않는다. |
| 궤적 가독성 | 같은 복도를 되돌아가 기존 회색선과 겹쳐도 최근 3~5m의 이동 방향을 구분할 수 있다. |
| 재생 가능성 | JSON 하나로 주황 걸음, 네 heading, 진행률 후보·표시값, 역방향 상태와 체크포인트 전후 위치를 재생할 수 있다. |

### 1.1 실패 조건

다음 중 하나라도 발생하면 배포하지 않는다.

- 길안내 진행률의 경로 투영점을 실제 마커 위치로 사용한다.
- 진행률 후퇴를 보류하면서 실제 역방향 마커까지 이전 위치에 고정한다.
- heading만 120° 이상 바뀌었다는 이유로 걸음 없이 `wrongWay`를 확정한다.
- 기존 100° 회귀 보류와 120° `wrongWay` 판정을 새 이동 방향 상태기와 동시에 제품 판정에 사용한다.
- `mapMatchedHeading` 또는 `routeHeading`으로 마커 화살표를 회전한다.
- 정방향 회복 뒤 실제 마커를 파란 경로 투영점으로 다시 끌어당긴다.
- 경로에 이미 투영된 화면 마커를 근거로 “경로 위에 있다”거나 “waypoint에 가깝다”고 판정한다.
- 주황 누적 거리만으로 node 도착을 판단하고 같은 주황 peak 수로 보폭까지 계산한다.
- 자유보행의 직선 node, 순서가 아닌 waypoint 또는 모호한 분기에서 재기준화한다.
- `reverseCandidate`, `reverseConfirmed`, `forwardCandidate`, `offRoute`에서 체크포인트를 확정한다.
- 1.5m를 넘는 약한 waypoint 오차를 waypoint가 진실이라고 보고 조용히 강제 보정한다.
- 체크포인트마다 native sensor 또는 `CMPedometer`를 stop/start한다.
- 체크포인트 때문에 세션 전체 진단 거리와 과거 보행 궤적이 사라진다.

---

## 2. 구현 전 동작과 문제

### 2.1 실제 마커가 길안내 진행률에 종속돼 있다

현재 길안내가 활성화되면 실제 마커는 tracker의 `previewPosition`이 아니라 `_routeProgress`의
`projectedPoint`를 사용한다. 현재 간선이 경로 간선이거나, 재획득 전이고 경로 오차가 4m 미만이며
이탈 증거가 3회 미만이면 마커를 계속 파란 경로 위에 둔다.

진행거리 후보가 2m 넘게 뒤로 갈 때도 heading이 역방향이라는 근거가 확인되기 전에는 이전
`_routeProgress`를 유지한다. 진행률 안정화 자체는 필요하지만 같은 값을 마커 위치에도 사용하므로,
실제 사용자가 반대로 걸어도 마커가 늦게 반응할 수 있다.

### 2.2 heading은 일부만 분리돼 있다

현재 마커 심볼 source는 위치 또는 heading이 바뀌면 다시 갱신된다. 카메라는 별도로 12° deadband를
두므로 작은 방향 변화에서는 화살표만 돌고 지도는 그대로 있는 것이 의도된 동작이다.

다만 현재 `CorridorTrackingResult.deviceHeadingDeg`는 이름과 달리 순수 기기 orientation이 아니다.
PDR의 `walkingHeading`에 복도 tracker가 학습한 heading bias를 더한 값이다. 따라서 마커 화살표,
걸음 적분, 복도 가설, 경로 판정이 아직 명시적인 타입으로 완전히 분리돼 있지 않다.

### 2.3 역방향 상태가 순간 heading 판정이다

현재 `RouteProgress.wrongWay`는 경로 간선 위에서 heading 오차가 120° 이상이면 바로 true가 된다.
걸음 없는 제자리 회전과 실제 역방향 보행을 시간 상태로 구분하지 않는다.

이와 별도로 진행거리 후보가 2m 넘게 후퇴했을 때 사용하는 `shouldHoldRouteRegression`은 heading 오차가
100° 미만이면 이전 진행률을 유지한다. 즉 현재 코드에는 목적이 다른 두 임계가 공존한다.

| 기존 판정 | 현재 역할 | 문제 | 새 구조에서의 대체 |
|---|---|---|---|
| heading 오차 `< 100°` | 2m 초과 진행률 후퇴 보류 | 실제 역방향 걸음의 표시까지 늦출 수 있음 | peak 기반 방향 상태와 display 진행률 안정화로 대체 |
| heading 오차 `>= 120°` | `RouteProgress.wrongWay = true` | 제자리 회전도 즉시 오안내 가능 | `reverseConfirmed` 상태에서만 안내 action 생성 |

두 값을 새 임계 하나로 합치지 않는다. 둘 다 heading-only 제품 판정에서 제거하고, heading은 실제 signed
걸음 증거를 보조하는 신호로만 남긴다. Phase 2 전환 뒤에는 기존 판정과 새 상태기를 병행하지 않는다.

반대로 같은 경로 간선에서 실제로 뒤로 걸으면 `onRouteEdge == true`이므로 기존 이탈 재탐색 조건에는
들어가지 않는다. 역방향 안내와 재탐색의 책임을 별도로 정의해야 한다.

### 2.4 회색선은 방향을 보여주지 않는다

길안내 시작 뒤 graph-matched 보행 궤적은 confirmed 이력에 optimistic preview 꼬리를 붙여 회색으로
표시한다. 실제 역방향 이동도 geometry에는 들어가지만 같은 복도를 되돌아가면 기존 선과 정확히
겹쳐 현재 이동 방향을 알 수 없다.

---

## 3. 2026-08-06 실측 로그에서 확인한 사실과 한계

대상 로그는 iOS 앱 1.5.1 build 7에서 약 143초 동안 기록됐다.

| 항목 | 값 | 해석 |
|---|---:|---|
| confirmed | 145걸음 / 102.0m | 첫 증가는 시작 약 18.5초 뒤였다. |
| preview | 201걸음 / 141.1m | 시작부터 반응했으며 사용자의 현장 체감은 실제 이동 거리와 비슷했다. |
| 첫 confirmed 시점 preview | 30걸음 | 초반 반응 차이는 batch 지연의 영향을 받았다. |
| 내보내기 상태 | `running` | 종료·최종 정산된 세션이 아니다. |
| `pedometer_finalize` | `null` | live 걸음과 사후 재조회 걸음을 비교할 수 없다. |
| tracker 입력·복도 보정 표본 | 0건 | node 통과, optimistic 이동과 역방향 상태를 재생할 수 없다. |

이 로그에는 실제 보행 거리나 수동 waypoint 통과 시각 같은 ground truth가 없다. 따라서
`orangeOvercountLikely`는 주황 과검출의 증명이 아니다. 주황과 초록 중 어느 쪽이 실제 걸음 수에
가까운지도 이 파일만으로 확정할 수 없다.

confirmed 102.0m를 기존 진단 matcher로 graph에 붙인 결과는 183.2m로 부풀었고, 2m를 넘는 구간
점프가 20개, 최대 점프가 약 15.1m였다. 이 fallback matcher의 nearest/recovery 결과를 실제 마커,
역방향 또는 체크포인트 판정에 사용하면 안 된다. 연결된 가설을 유지하는
`CorridorPositionTracker`의 optimistic topology를 사용해야 한다.

---

## 4. 분리할 제품 상태

### 4.1 위치와 진행률

```text
actualMarkerPosition
  = CorridorPositionTracker.previewPosition
  + 활성 soft correction residual

measuredRouteProgress
  = actualMarkerPosition을 파란 경로에 투영한 매 snapshot 후보

displayRouteProgress
  = 점프·회귀·이탈 히스테리시스를 통과해 UI가 수용한 진행률
```

역할은 다음처럼 고정한다.

| 상태 | 소비자 | 다른 상태에 미치는 영향 |
|---|---|---|
| `actualMarkerPosition` | 실제 마커, 카메라 중심, 최근 회색 보행선, 재탐색 출발점 | 길안내 진행률이 이 값을 되돌려 쓰지 않는다. |
| `measuredRouteProgress` | 역방향·이탈 증거, 진단 | 직접 파란선과 ETA를 흔들지 않는다. |
| `displayRouteProgress` | 남은 파란선, ETA, 다음 행동, 완료된 계획선 분할 | 실제 마커를 경로 투영점으로 옮기지 않는다. |

정방향으로 회복해 “경로에 재합류”하는 대상은 `displayRouteProgress`와 길안내 UI다. 실제 마커는
항상 tracker 위치를 유지한다. 에스컬레이터 탑승처럼 별도 센서 근거로 위치를 고정하는 상태만
명시적인 예외로 둔다.

### 4.2 네 종류 heading

| 이름 | 정의 | 용도 |
|---|---|---|
| `orientationHeading` | walkOffset과 복도 bias 적용 전, 기기 전방축의 안정화된 `fusedHeading` | 마커 화살표, 카메라 bearing |
| `walkingHeading` | `fusedHeading + walkOffset` | 주황·초록 걸음 벡터 적분 |
| `mapMatchedHeading` | optimistic edge 접선과 이동 부호 | 복도 가설, node 진출, 실제 정·역방향 이동 판정 |
| `routeHeading` | 현재 파란 경로 segment의 목적지 방향 접선 | 길안내 정·역방향 비교 |

`orientationHeading`은 `PdrSnapshot`의 제품 필드로 승격한다. 진단용 quality map에서 값을 꺼내
제품 UI에 쓰지 않는다. 플랫폼 raw `deviceHeading`도 의미가 다를 수 있으므로 이름만 보고 대신
사용하지 않는다.

마커 화살표 source는 `orientationHeading`이 바뀔 때마다 갱신한다. 카메라만 기존 12° deadband와
센서 smoothing을 유지한다.

---

## 5. 실제 이동 방향 상태기

### 5.1 판정 원칙

사용자가 바라보는 방향과 실제 이동 방향을 구분한다. heading이 반대라는 사실만으로 역방향
보행을 확정하지 않는다.

주된 관측값은 accepted preview peak 하나가 tracker topology에서 만든 실제 이동 사건이다. 현재와 다음
snapshot의 `optimisticEdgeProgressM`을 단순히 빼서 만들면 안 된다. node를 건널 때 새 edge progress가
0 부근으로 바뀌고, beam leader가 교체될 때도 위치가 바뀌므로 정상 정방향 걸음을 큰 음수 이동으로
오판할 수 있다.

tracker는 peak 적용 시점에 다음 불변 사건을 노출한다.

```text
OptimisticStepAdvance
  peakId
  occurredAt
  hypothesisId
  parentHypothesisId
  distanceM
  traversals[]
    edgeId
    fromProgressM
    toProgressM
  crossedNodeIds[]
  leaderRelocated
```

`traversals`는 직전 공개 leader와 새 공개 leader의 차이가 아니라, 선택된 가설이 자기 parent에서
해당 peak를 적용하며 이동한 경로다. 한 peak가 node를 건너 여러 edge 조각을 지난 경우에도 실제
순서대로 보존한다. 단일 `fromEdgeId → toEdgeId`와 progress 차이만 저장하지 않는다.
`leaderRelocated == true`여도 그 peak의 traversal과 leader 교체 offset을 합치지 않는다. traversal은
표시 거리와 진단에 남기되, lineage 교체가 만든 불확실성 때문에 해당 사건은 방향 확정 증거에서
제외한다.

길안내 계층은 이 사건과 활성 route의 edge 방향을 결합해 다음 값을 만든다.

```text
RouteStepAdvance
  peakId
  signedRouteDistanceM
  relation: forward | reverse | offRoute | ambiguous | relocated
  crossedRouteWaypointIds[]
```

`signedRouteDistanceM`은 파란 경로 목적지 방향을 양수로 정규화한다. tracker가 route를 직접 알게 하지
않고 route adapter가 각 traversal을 경로의 edge 방향과 비교해 계산한다. node 경계, 반대 방향으로
저장된 graph edge와 여러 edge를 지난 한 걸음에서도 부호가 유지돼야 한다.

해당 peak 시각의 `orientationHeading`과 `routeHeading` 차이는 보조 관측으로 함께 기록한다. 다만
실제 traversal이 없으면 상태를 `reverseCandidate`나 `reverseConfirmed`로 바꾸지 않는다.

### 5.2 상태

| 상태 | 진입 조건 | 표시·안내 동작 |
|---|---|---|
| `forward` | 기본 정상 보행 | 마커 즉시 이동, 진행률 정상 갱신, 체크포인트 허용 |
| `reverseCandidate` | 첫 강한 음수 방향 preview 걸음 | 마커·최근 궤적은 즉시 반영, 기존 안내 문구는 잠시 유지, 체크포인트 금지 |
| `reverseConfirmed` | 서로 다른 peak 2~3개가 연속 음수 방향이고 최소 역방향 거리를 충족 | `RouteGuidanceAction.wrongWay` 생성, 진행률 후퇴 허용, 체크포인트 금지 |
| `forwardCandidate` | `reverseConfirmed` 뒤 첫 정방향 걸음 | 마커 즉시 반영, 안내는 아직 반대 방향 상태 유지, 체크포인트 금지 |
| `offRoute` | 다른 경로 간선 진입 또는 지속 이탈 | 마커는 실제 위치 유지, 재탐색, 체크포인트 금지 |

정확한 걸음 수와 최소 역방향 거리는 replay로 정한다. 초기 실험값은 서로 다른 peak 2~3개와
누적 약 1.2m지만, 코드 상수로 확정하기 전에 정상 코너·제자리 회전·폰 흔들기 fixture를 비교한다.

상태 enum은 `TravelDirectionState`처럼 기존 필드와 구분되는 이름을 사용한다. Phase 2에서 기존
`RouteProgress.wrongWay` bool은 제거하고 모든 소비처를 새 enum으로 한 번에 이관한다. 사용자 안내에
쓰는 `RouteGuidanceAction.wrongWay`는 제품 문구의 의미이므로 유지하되,
`TravelDirectionState.reverseConfirmed`일 때만 생성한다. 기존 bool과 새 enum이 동시에 제품 판단을
내리는 중간 상태는 허용하지 않는다.

### 5.3 기존 회귀·역방향 판정 교체 규칙

- `shouldHoldRouteRegression`의 100° heading 분기는 제거한다.
- display 진행률의 큰 후퇴는 `reverseConfirmed` 전에는 UI 안정화를 위해 보류할 수 있지만, 실제
  마커와 `measuredRouteProgress`는 즉시 후퇴한다.
- `reverseConfirmed`에 들어가면 실제 peak가 만든 후퇴를 display 진행률에도 수용한다.
- `RouteProgress.wrongWay`의 120° 즉시 판정은 제거한다.
- heading 오차는 `RouteStepAdvance`의 부호와 충돌할 때 `ambiguous` 또는 낮은 confidence를 만드는
  보조값으로만 사용하며, 단독으로 상태를 전이하지 않는다.
- leader 재배치, graph/anchor 교체와 floor transition은 방향 걸음으로 세지 않는다.

### 5.4 재탐색 정책

- 같은 경로 간선에서 역방향 지속: 즉시 재탐색하지 않고 “돌아가세요” 안내를 유지한다.
- 역방향으로 이전 decision node를 넘어 다른 간선에 진입: 현재 실제 위치에서 재탐색한다.
- 경로 간선이 아니거나 강한 이탈 증거가 지속: 기존 이탈 재탐색을 사용한다.
- 정방향 2~3걸음 회복: `displayRouteProgress`를 현재 measured 후보로 다시 수용한다.

같은 간선 역방향만으로 재탐색하면 대부분 동일 경로를 다시 계산하므로 피한다.

---

## 6. waypoint 체크포인트 분류

| 종류 | 근거 | 처리 |
|---|---|---|
| 층 전환점 | 기압·전환 상태·정확한 도착 node | 기존 층 전환 상태기가 소유하는 강한 체크포인트 |
| 고유한 회전점 | 활성 경로의 다음 node, 고유한 분기 구조, outgoing 2~3걸음 | 강한 자동 체크포인트 |
| 직선 경로 waypoint | 활성 경로 순서, 경로 간선·방향 일치, 1~1.5m 이내 작은 오차 | 조건부 약한 soft rebase |
| 자유보행 직선 node | 독립적인 node 도착 근거 없음 | 재기준화하지 않고 shadow 로그만 기록 |
| 모호·불확실·역방향·이탈 | 신뢰 조건 불충족 | 재기준화 금지 |

### 6.1 공통 gate

강한·약한 체크포인트 모두 다음 조건을 만족해야 한다.

1. 활성 길안내 중이다.
2. 경로상 바로 다음 checkpoint waypoint다.
3. tracker의 optimistic 현재 간선이 안내 경로 간선과 일치한다.
4. `RouteStepAdvance.relation`이 `forward`다.
5. 이동 방향 상태가 `forward`다.
6. tracker가 `uncertain`이 아니다.
7. preview 후보가 모호하지 않다.
8. 대표 간선 재배치 프레임이 아니다.
9. 경로 재탐색이 진행 중이 아니다.
10. 동일 route generation에서 같은 waypoint를 이미 처리하지 않았다.

현재 간선과 waypoint 거리는 경로에 투영된 화면 마커가 아니라 tracker의 독립적인 optimistic 상태로
계산한다. 그렇지 않으면 경로에 붙여 놓은 결과로 다시 “경로 위”를 증명하는 순환 판정이 된다.

### 6.2 직선 waypoint 추가 조건

- raw route polyline의 모든 geometry 점이 아니라 실제 graph node ID를 사용한다.
- 직선상의 촘촘한 degree-2 node는 route 누적거리 기준 최소 8~10m 간격으로 축약한다.
- 직전 checkpoint 이후 경로 누적거리가 최소 간격을 충족한다.
- waypoint와 tracker `previewPosition` 차이가 1.5m 이하다.
- incoming/outgoing edge가 사실상 같은 방향이며 분기 선택이 발생하지 않는다.
- 직전 여러 `RouteStepAdvance.signedRouteDistanceM`이 양수로 단조 누적된다.

한 waypoint는 route generation별로 한 번만 처리한다. 유턴 후 다시 지나더라도 기존 길안내가 유지되는
동안은 약한 checkpoint를 반복하지 않는다. 재탐색으로 새 route generation이 생기면 ledger를 새로 연다.

### 6.3 회전점 추가 조건

- incoming과 outgoing edge가 해당 node에서 실제로 연결된다.
- 관측된 회전 방향이 node의 고유한 분기 구조와 일치한다.
- outgoing 방향의 서로 다른 preview peak가 2~3개 연속 유지된다.
- 회전 후보 사이 점수 차가 ambiguous margin 밖이다.

강한 회전점도 무제한 위치 점프 권한은 아니다. 1.5m를 넘는 보정이 필요하면 조용히 waypoint로
순간이동시키지 않고 `checkpointDisputed`를 기록해 tracker 재평가 또는 재탐색으로 넘긴다. 층 전환은
별도 센서와 전환 UI가 있으므로 이 제한의 예외다.

---

## 7. soft rebase와 표시 residual

### 7.1 좌표 재기준화만으로는 오차가 사라지지 않는다

마커가 waypoint보다 1m 앞선 상태에서 내부 원점만 waypoint로 바꾸면 두 선택지가 생긴다.

- 1m 표시 offset을 영구 보존하면 화면은 연속이지만 기존 위치 오차도 그대로 남는다.
- offset을 즉시 버리면 위치 오차는 없어지지만 마커가 1m 순간이동한다.

따라서 약한 체크포인트는 residual을 명시적으로 상태로 가진다.

```text
residual = checkpoint 직전 표시 위치 - waypoint

actualMarkerPosition
  = waypoint
  + checkpoint 이후 optimistic 이동
  + residualCorrection
```

### 7.2 보정량별 처리

| waypoint 오차 | 처리 |
|---:|---|
| 0~0.5m | 내부 원점을 waypoint로 바꾸고 residual을 즉시 제거한다. |
| 0.5~1.5m | 확정 프레임에는 residual을 유지하고 이후 정상 정방향 걸음 2~4개에 걸쳐 0으로 줄인다. |
| 1.5m 초과 | 약한 체크포인트를 거부하고 기존 추적을 유지하며 오류 로그만 남긴다. |

residual 제거는 시간만으로 진행하지 않는다. 정지 중 마커가 혼자 미끄러지지 않도록 서로 다른 정상
preview peak가 들어올 때만 한 단계씩 줄인다. 방향 상태가 `forward`가 아니거나 재배치가 발생하면
제거를 중단하고 체크포인트를 dispute 처리한다.

### 7.3 원자적 재기준화

체크포인트 commit은 다음을 한 화면 갱신으로 처리한다.

1. checkpoint peak 시각을 새 PDR 시간 경계로 설정한다.
2. native sensor, heading과 누적 peak baseline은 유지한다.
3. 주황·초록 경로 누적값을 새 segment의 0으로 재기준화한다.
4. checkpoint 뒤 판정에 사용한 buffered preview peak를 새 원점에서 정확히 한 번 재적용한다.
5. anchor, core path, corridor tracker, residual을 같은 공개 상태로 교체한다.
6. 과거 보행선은 별도 `GuidanceTrailSession` segment로 보존한다.
7. 세션 전체 거리·걸음 수는 recorder가 segment 합계로 별도 보존한다.

`rebase → 다음 snapshot에서 preview tail 복구`처럼 두 프레임으로 나누면 순간 정지나 후퇴가 보이므로
허용하지 않는다. 늦은 confirmed batch도 시간 경계 이전 걸음을 새 원점 뒤에 다시 붙이지 않아야 한다.

---

## 8. 주황 우선 위치와 초록 안전장치

### 8.1 고정 누적 step cap은 사용하지 않는다

`주황 누적 걸음 ≤ 초록 누적 걸음 + N`은 초록이 실제보다 적게 세거나 첫 batch가 늦으면 화면을
다시 멈춘다. 이번 로그에서도 첫 confirmed까지 약 18.5초가 걸렸다.

초록은 다음처럼 사용한다.

| 상태 | 처리 |
|---|---|
| 첫 batch 전·finalize 전 | 정상 주황 위치를 표시하고 초록 누적 차이만으로 제한하지 않는다. |
| 최근 confirmed 시간창이 정상 | 시간상 아직 확인되지 않은 preview tail만 제한 후보로 본다. 세션 전체 누적 차이에는 적용하지 않는다. |
| confirmed 장기 지연·undercount 의심 | 초록 cap으로 마커를 세우지 않는다. graph 연결성, peak 간격, cadence와 최대 속도로 보호한다. |
| 주황 이상 의심 | 이미 보여 준 위치를 뒤로 보내지 않고 새 peak를 보류한다. 정상 리듬·confirmed 감사가 회복되면 재개한다. |

### 8.2 peak 안전장치

- `tooDense`, 동일 timestamp batch, 불가능한 cadence가 실제로 거부되는지 확인한다. 진단 이름만
  `Rejected`이고 경로에는 적용되는 상태가 없어야 한다.
- 긴 정지 뒤 첫 `tooSparse` peak는 새 보행 시작일 수 있으므로 한 건만으로 버리지 않는다.
- 최대 속도는 순간 한 걸음이 아니라 짧은 시간창으로 검사한다.
- 보류 peak를 나중에 한꺼번에 풀어 마커가 순간이동하지 않게 queue 상한과 폐기 정책을 기록한다.

구체 threshold는 shadow replay에서 정상 보행, 휴대폰 흔들기, 정지 후 재출발과 confirmed 20초 지연을
비교한 뒤 정한다.

---

## 9. 실제 보행선 표시

회색선의 데이터는 실제 graph-matched 궤적을 유지한다. 방향을 보이기 위한 별도 presentation layer를
추가한다.

- 전체 과거 궤적: 기존 회색 실선
- 최근 optimistic 3~5m: 더 진한 회색 또는 짧은 점선
- 최근 tail 위: 간격을 둔 작은 chevron 또는 방향 화살표
- 체크포인트·층 전환·큰 재배치: 서로 다른 LineString segment

최근 tail은 저장된 확정 이력을 덮어쓰지 않는다. 다음 snapshot에서 preview가 되돌아가면 임시 layer만
갱신한다. 화살표는 선의 실제 진행 순서로 만들고 `orientationHeading`으로 억지 회전하지 않는다.

---

## 10. 진단 JSON 보강

### 10.1 위치·heading·진행률

- `actual_marker_position`
- `confirmed_position`, `optimistic_position`, 활성 `residual`
- `orientation_heading_deg`, `walking_heading_deg`, `map_matched_heading_deg`, `route_heading_deg`
- peak별 `OptimisticStepAdvance`: traversal 목록, node 통과, 이동거리와 `leaderRelocated`
- peak별 `RouteStepAdvance`: route signed 거리, relation과 통과 waypoint
- `measured_route_progress`와 `display_route_progress`
- 진행률 hold 여부와 `pendingDeviation`, `implausibleJump`, `regression` 사유

### 10.2 방향 상태

- `forward`, `reverseCandidate`, `reverseConfirmed`, `forwardCandidate`, `offRoute` 전이
- 전이에 사용한 peak ID와 누적 signed distance
- heading error와 step 이동 부호
- `reverseConfirmed` 지속 시간, `RouteGuidanceAction.wrongWay` 생성 시각, node 통과와 재탐색 여부

### 10.3 체크포인트

- route generation, waypoint node ID와 강한/약한 분류
- candidate/commit/reject/dispute 사유
- waypoint 거리, residual 시작값과 step별 감소량
- checkpoint 기준 peak ID와 재적용한 buffered peak ID
- 체크포인트 전후 raw·corrected·optimistic·display 위치
- 새 trail segment ID와 화면 점프 거리

### 10.4 수집 경로 수정

실내·야외 화면 모두 `CorridorTrackingSession.update` 결과와 실제 observation을 recorder에 전달한다.
현재처럼 tracker는 실행됐지만 `tracker_input_events`와 `corridor_correction_samples`가 비는 경로를
없앤다.

---

## 11. 구현 단계

### Phase 0 — 관측 가능성

- 야외 화면 recorder 결선을 실내 화면과 맞춘다.
- 네 heading, `OptimisticStepAdvance`, `RouteStepAdvance`, measured/display 진행률을 JSON에 추가한다.
- preview 경로·batch와 waypoint 후보를 재생 가능하게 기록한다.
- 경로 종료 내보내기와 sensor stop/finalize 내보내기를 구분한다.

완료 조건: 알고리즘을 바꾸지 않고도 실제 마커가 진행률 때문에 멈춘 프레임과 역방향 peak를 한
파일에서 재생할 수 있다.

### Phase 1 — 마커·heading·진행률 분리

- 실제 마커를 항상 optimistic tracker 위치에서 만든다.
- measured와 display 진행률을 별도 상태로 나눈다.
- `orientationHeading`을 snapshot 제품 필드로 추가해 마커 화살표에 연결한다.
- 기존 진행률 hold는 파란선·ETA에만 적용한다.

완료 조건: 진행률 회귀를 보류한 상태에서도 마커와 화살표가 실제 입력에 즉시 반응한다.

### Phase 2 — 실제 이동 방향 상태기

- tracker peak 적용 지점에서 `OptimisticStepAdvance`를 만들고 route adapter가 `RouteStepAdvance`로
  변환한다.
- `forward → reverseCandidate → reverseConfirmed → forwardCandidate` 상태기를 추가한다.
- 기존 100° 회귀 보류와 `RouteProgress.wrongWay` 120° 즉시 판정을 제거하고 소비처를 새 상태기로
  원자적으로 이관한다.
- 같은 간선 `reverseConfirmed`와 실제 off-route 재탐색을 분리한다.
- 모든 비정상 방향 상태에서 waypoint 체크포인트를 금지한다.

완료 조건: 제자리 회전은 `reverseConfirmed`가 되지 않고, 첫 역방향 걸음부터 마커가 움직이며,
2~3걸음 뒤 안내만 확정된다. 제품 판정 경로에 기존 heading-only 분기가 남아 있지 않다.

### Phase 3 — shadow 체크포인트

- 활성 경로의 checkpoint waypoint 목록을 graph node ID와 route 누적거리로 만든다.
- 회전점 강한 후보와 직선 waypoint 약한 후보를 분류한다.
- 제품 위치를 바꾸지 않고 candidate/commit/reject/dispute 예상 결과만 기록한다.
- 8~10m 간격과 1~1.5m 보정 상한을 fixture·실측으로 검증한다.

완료 조건: 실제 경로 waypoint를 순서대로 잡고 모호·역방향·이탈·촘촘한 node를 거부한다.

### Phase 4 — soft rebase와 최근 궤적

- checkpoint 시간 경계, buffered peak 재적용과 residual 제거를 원자적으로 구현한다.
- 과거 trail segment를 보존한다.
- 최근 3~5m 강조선과 방향 표시를 추가한다.
- confirmed 사후 반박을 dispute로 기록하고 즉시 롤백하지 않는다.

완료 조건: 마커 점프·후퇴·peak 중복 없이 누적 위치가 waypoint 구간별로 재기준화된다.

### Phase 5 — 실기기 A/B

- 같은 알려진 경로를 기존 방식과 새 방식으로 각각 걷는다.
- 정방향, 같은 복도 역방향, node 유턴과 경로 이탈을 모두 포함한다.
- 현장에서 waypoint 통과 버튼 또는 영상 timestamp를 독립 ground truth로 남긴다.
- 마커 반응 지연, `reverseConfirmed` 판정 지연, checkpoint 오탐·누락과 다음 waypoint 오차를
  비교한다.
- sensor를 멈춘 뒤 finalize된 JSON도 함께 저장한다.

완료 조건: 진행률 안정성을 잃지 않으면서 마커 역방향 반응이 즉시 보이고, soft rebase가 다음
waypoint까지의 누적 위치 오차를 줄인다.

---

## 12. 테스트 행렬

### 12.1 위치·진행률 분리

- 진행률 후보가 3m 후퇴해 display 진행률 hold → 실제 마커는 optimistic 위치로 즉시 후퇴
- off-route 증거 1~2회 → 파란선은 유지하지만 마커는 실제 다른 간선에 표시
- 정방향 회복 → display 진행률만 현재 measured 후보로 재합류, 마커 좌표 불변
- leader 재배치 → 실제 trail은 새 segment, 진행률은 implausible jump hold

### 12.2 heading

- 위치 고정 + orientation 30° 회전 → 화살표 즉시 회전, 카메라는 deadband에 따라 회전
- walkingHeading만 변경 → 걸음 방향은 바뀌지만 화살표에 walkOffset이 섞이지 않음
- map-matched 직선 간선 이동 → 간선 접선이 같아도 화살표가 orientation을 계속 따름
- 코너에서 routeHeading만 변경 → 걸음 없이 화살표가 경로 방향으로 강제 회전하지 않음

### 12.3 실제 이동 방향

- 제자리 180° 회전, 걸음 없음 → `forward` 유지
- heading 오차 110°, 걸음 없음 → 기존 100°/120° 사이여도 `forward` 유지
- heading 오차 130°, 정방향 traversal → 반대 방향 안내 없음
- sensor heading 갱신이 늦은 역방향 traversal → 첫 걸음부터 `reverseCandidate`
- 역방향 preview 1걸음 → `reverseCandidate`, 마커 즉시 이동, 안내 유지
- 역방향 3걸음 → `reverseConfirmed`, `RouteGuidanceAction.wrongWay` 안내
- `reverseConfirmed` 뒤 정방향 1걸음 → `forwardCandidate`
- 정방향 3걸음 → `forward`, 진행률 갱신 재개
- 같은 간선 `reverseConfirmed` 지속 → 불필요한 재탐색 없음
- 이전 junction을 넘어 다른 간선 진입 → 재탐색
- 정방향 한 걸음으로 node·edge 전환 → traversal 합은 한 보폭, reverse 증거 없음
- graph 저장 방향이 반대인 edge로 정상 진입 → route 기준 signed 거리는 양수
- leader 재배치로 edge progress가 감소 → 위치·진단만 갱신, 방향 상태 불변
- 기존 `RouteProgress.wrongWay` 소비처 검색 → 제품 코드 참조 0건

### 12.4 waypoint

- 직선 waypoint 0.3m 오차 → 즉시 soft rebase, 마커 점프 0.5m 이하
- 직선 waypoint 1.2m 오차 → 2~4걸음 residual 제거
- 직선 waypoint 1.6m 오차 → reject, 위치 불변
- 5m 간격 degree-2 node 연속 → 8~10m 축약 기준으로 일부만 후보
- 회전점 outgoing 3걸음 → 강한 checkpoint 한 번 commit
- `reverseCandidate`·`reverseConfirmed`·`forwardCandidate` 각각에서 waypoint 통과 → commit 없음
- 경로 재탐색 뒤 같은 node → 새 route generation에서만 다시 후보
- 자유보행 직선 node 통과 → 위치 변경 없음

### 12.5 시간축·수명주기

- preview 3걸음 → checkpoint → confirmed 3걸음: 위치 불변, 중복 없음
- 첫 confirmed 20초 지연: 정상 preview가 cap에서 멈추지 않음
- checkpoint 직후 background/foreground
- checkpoint 직후 수동 위치 재지정
- checkpoint 후보 중 경로 재탐색·층 전환
- graph·anchor·층 변경과 checkpoint가 같은 프레임에 발생
- recorder 표본 상한 뒤에도 direction·commit·dispute 전이 쌍 보존

---

## 13. 보폭 자동 학습 보류

node 도착과 보폭을 같은 주황 누적 거리로 동시에 맞추면 순환 논리가 된다. 주황 이중 검출도
`graph 거리 / 주황 peak 수` 계산에서 작은 보폭으로 흡수돼 정확해진 것처럼 보일 수 있다.

다음 정보가 충분히 모일 때만 별도 실험 문서를 만든다.

- 주황 거리와 독립적인 수동 waypoint 통과 timestamp 또는 외부 기준 위치
- 고유한 회전 구조를 가진 A·B decision waypoint 쌍
- 10~15m 이상이며 우회·코너 커팅 영향이 작은 구간
- 여러 주행에서 반복되는 `graph 거리 / 주황 peak 수` 분포
- 나중에 들어온 confirmed가 해당 waypoint sequence를 크게 반박하지 않았다는 기록

실험하더라도 한 구간 후보를 즉시 적용하지 않는다. 물리적 보폭 범위를 벗어난 값을 버리고, 여러
구간 중앙값이나 bounded EMA를 사용하며 한 checkpoint의 변경량을 약 ±3%로 제한한다.

이 조건이 충족되기 전에는 보폭 후보를 제품 상태에 반영하지 않는다.

---

## 14. 최종 결정

1차 제품 변경의 우선순위는 다음과 같다.

1. 실제 마커 위치를 길안내 투영점에서 분리한다.
2. 마커 orientation, 걸음 적분, 맵매칭, 경로 접선 heading을 분리한다.
3. peak 단위 topology traversal로 route signed 이동을 만들고 역방향 상태기를 구성한다.
4. 활성 경로의 회전점은 강한 체크포인트, 8~10m 간격의 직선 waypoint는 1~1.5m 이내 약한
   soft rebase로 사용한다.
5. `reverseCandidate`, `reverseConfirmed`, `forwardCandidate`, `offRoute`에서는 모든 waypoint
   재기준화를 금지한다.
6. 보폭 자동 학습은 독립 ground truth가 쌓일 때까지 제외한다.

이 구조에서 주황은 실제 마커의 실시간 이동을 담당하고, 초록은 사후 감사와 sensor 이상 감지를
담당한다. 길안내 진행률은 파란선과 안내 문구를 안정화하지만 실제 위치와 화살표를 바꾸지 않는다.
