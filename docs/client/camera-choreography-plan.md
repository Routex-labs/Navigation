# 카메라 연출 계획 — 안내 시작·층 전환 (핸드오프)

안내를 시작하는 순간과 층이 바뀌는 순간에 **카메라를 어떻게 움직일지**를 정하는
문서. 다른 세션이 이어받아 구현하는 것을 전제로, "무엇을 왜"와 "무엇이 충족되면
맞다고 볼지"까지 적는다.

- 아래 파일·심볼 참조는 브랜치 `worktree-promo-flow-ux`의 `2741a72` 기준으로
  실제 코드를 열어 확인한 값이다.
- 이 문서는 **결정을 대신하지 않는다.** 갈림길은 [6. 사람이 정해야 할
  것](#6-사람이-정해야-할-것)에 모아 두었다. 거기부터 읽고 고른 뒤 3장으로
  돌아오면 된다.

---

## 1. 하려는 것

프로모션 영상(`프로모션.mp4`)의 안내 화면처럼, 두 순간에 카메라가 **한 번 크게
움직여 상황을 다시 보여 주는** 연출을 넣는다.

| 순간 | 원하는 그림 |
|---|---|
| 길안내 시작 | 전체 경로가 한눈에 들어오는 크기로 줌아웃/줌인하며 재배치 |
| 층 전환 | 새 층에서 같은 방식으로 다시 배치 |

"재배치되는 듯한" 극적인 효과는 **처음 한 번만** 준다. 매 걸음마다 카메라가
크게 움직이면 연출이 아니라 멀미다.

---

## 2. 지금 코드가 어디까지 와 있나

**새로 만들 것이 생각보다 적다.** 필요한 기하 계산과 애니메이션 경로는 이미
있고, 대부분은 "무엇을 입력으로 주느냐"만 바꾸면 된다.

### 2.1 그대로 쓸 수 있는 도구

| 심볼 | 파일 | 하는 일 |
|---|---|---|
| `minAreaBoxFor(footprint)` | `screens/outdoor_map/building_orientation.dart` | 점 목록을 감싸는 **최소 넓이 직사각형**(긴 변 길이·짧은 변 길이·긴 축 방위각) |
| `portraitBearingFor(...)` | 〃 | 긴 축을 화면 세로로 세우는 카메라 bearing. 두 후보 중 덜 도는 쪽을 고른다 |
| `offsetByMeters(origin, azimuthDeg, meters)` | 〃 | 목표점을 화면 위/아래로 밀어 chrome이 가리지 않는 띠 한가운데에 놓을 때 |
| `zoomToFitRotatedBox(...)` | `screens/outdoor_map/indoor_entry_zoom.dart` | 돌려 세운 상자를 가로·세로 **둘 다** 담는 zoom |
| `visibleWidthMeters(zoom, px, lat)` | 〃 | zoom ↔ 미터 환산 (px당 미터가 필요할 때 `availablePx: 1`) |
| `indoorExitZoomThreshold` | 〃 | 이 아래로 내려가면 실내에서 이탈 판정 (= 줌아웃 하한) |

`minAreaBoxFor`는 **건물 외곽선 전용이 아니다.** 임의의 점 목록을 받으므로
경로 폴리라인(`IndoorRoute.points`)을 그대로 넣을 수 있다. 경로는 대개 길쭉하니
"긴 축을 세로로" 규칙이 그대로 들어맞는다.

### 2.2 참고할 기존 구현

`OutdoorMapBodyState._fitCameraToActiveFloor({Duration duration})`
(`screens/outdoor_map/outdoor_map_screen.dart`)가 **이미 원하는 연출의 절반**이다.
지금 층 외곽선을 받아 → 최소 넓이 상자 → 세로 정렬 bearing → 여백 포함 fit →
chrome 띠 보정 → `animateCamera(duration:)` 까지 한다.

경로용 연출은 이 함수의 **입력만 바꾼 형제**로 만드는 것이 가장 짧다.

관련 상수(같은 파일):

| 상수 | 값 | 뜻 |
|---|---|---|
| `_indoorZoomInDuration` | 900ms | 건물 탭 → 실내 진입 |
| `_floorSwitchZoomDuration` | 500ms | 층 선택기로 층 전환 |
| `_floorFitFillRatio` | 0.86 | 사방 여백(7%씩) |
| `_floorFitTopChromePx` / `_floorFitBottomChromePx` | 132 / 112 | 위·아래 chrome 높이 |

### 2.3 경로 데이터가 어디 있나

| 심볼 | 내용 |
|---|---|
| `_indoorRouteSegment` (`IndoorRoute?`) | **지금 층** 세그먼트. `.points`가 wgs84 폴리라인 |
| `_indoorMultiFloorRoute` (`MultiFloorRoute?`) | 다층 경로 전체. `.segmentForFloor(floor)`, `.destinationSegment` |
| `_indoorRouteDestination` (`PoiSearchResult?`) | 목적지 매장 |
| `_guidance.displayProgress` | 진행률(남은 거리 등) |

**전체 경로 = 지금 층 세그먼트다.** 다층 경로 전체를 담으려 하면 화면에 없는
층의 좌표까지 상자에 들어가 엉뚱하게 축소된다. 층마다 따로 담는 것이 맞고,
그래서 층 전환 때 다시 배치하는 것이 자연스럽게 이어진다.

---

## 3. 제안하는 방식

### 3.1 뼈대 — `_fitCameraToRouteSegment`

`_fitCameraToActiveFloor`와 같은 자리에 형제 함수를 만든다.

```
입력: 지금 층 경로 점 목록(_indoorRouteSegment.points), duration
 1. minAreaBoxFor(routePoints)          → 경로를 감싸는 최소 상자
 2. portraitBearingFor(box.longAxis, 현재 bearing)
 3. zoomToFitRotatedBox(short/ratio, long/ratio, 가용 폭, 가용 높이(띠))
 4. max(fitZoom, indoorExitZoomThreshold + 여유)   ← 실내 유지 하한
 5. offsetByMeters(경로 중심, bearing, chrome 보정)
 6. animateCamera(newCameraPosition(...), duration: ...)
```

`_fitCameraToActiveFloor`와 4·5·6단계가 같으므로, **공통부를 private 헬퍼로 빼고
입력 점 목록만 달리 주는 형태**를 권한다. 두 함수가 각자 chrome 보정을 갖게 되면
한쪽만 고쳐져 도면과 경로의 배치 기준이 어긋난다.

### 3.2 "극적인 재배치" — 두 단계 연출

한 번의 `animateCamera`로는 "재배치"가 잘 안 읽힌다. 영상의 느낌은 **두 박자**다.

```
[1] 개요(overview)   전체 경로가 다 보이도록 줌아웃 + 경로 축으로 회전   ~700ms
        ↓ 잠깐 멈춤 (~600ms)   ← 사용자가 "어디로 가는지"를 읽는 시간
[2] 진행(follow-in)  현재 위치로 줌인, 진행 방향이 위로 오도록            ~700ms
```

[2]를 넣을지는 **카메라 추종을 도입할지**에 달려 있다 → [6번](#6-사람이-정해야-할-것).
추종을 안 넣기로 하면 [1]만 하고 끝내도 그림은 성립한다(전체 경로를 보여 준 채
사용자가 알아서 조작).

구현은 `await`로 잇는다:

```dart
await _fitCameraToRouteSegment(duration: kRouteOverviewDuration);
await Future<void>.delayed(kRouteOverviewHold);
if (!mounted) return;
await _zoomToWalkingView();   // [2]를 채택한 경우에만
```

### 3.3 언제 발화하나

| 시점 | 훅 | 비고 |
|---|---|---|
| 안내 시작 | `showIndoorRouteTo`가 세그먼트를 채운 직후 | 경로가 실제로 생긴 뒤여야 담을 것이 있다 |
| 층 전환 | `_enqueueFloorTransition` → `_switchOverlayFloor` 뒤 | 스크림이 걷히는 타이밍과 겹치지 않게 |
| 재탐색 | `_rerouteIndoorFromCurrentPosition` | **연출을 넣지 않는다** — 걷는 중에 카메라가 크게 움직이면 방해다 |

"처음에만"을 지키려면 **한 번 했는지 기억하는 플래그**가 필요하다. 경로 세그먼트가
새로 생길 때마다 발화하면 재탐색·층 전환마다 개요 연출이 반복된다.

---

## 4. 먼저 알아야 할 함정

여기서 시간을 잃기 쉬운 것들이다. 전부 실제 코드에서 확인했다.

### 4.1 `newLatLngBounds`는 지도를 정북으로 되돌린다

야외용 `_fitCameraToRoute(DirectionsRoute)`가 이 API를 쓴다. **실내 경로에 그대로
쓰면 안 된다** — 이 API는 항상 정북 정렬 기준으로 계산해서 bearing이 0으로
리셋되고, 방금 세로로 세워 둔 도면이 다시 비스듬히 눕는다
(`widgets/floor_plan_view.dart`의 같은 주석 참고).

→ 회전을 유지하려면 3.1처럼 `newCameraPosition`으로 직접 계산해야 한다.

### 4.2 자동 경로는 카메라를 가져가지 않기로 했다

`_applyRoute`는 `_userDestination != null`일 때만 `_fitCameraToRoute`를 부른다.
GPS가 잡힐 때마다 자동 계산되는 "건물 입구까지" 경로가 화면을 도시 축척으로
끌고 가던 것을 막은 결정이다. **이 분기를 되돌리지 말 것.**

### 4.3 지금은 카메라 추종이 없다

`_syncPdrCurrentLayer`는 마커 레이어만 갱신한다. 걸어도 카메라는 그대로다.
사용자가 화면을 되돌리는 수단은 하단 **위치 보정**(`recalibrate`) 버튼인데,
**안내 중에는 그 버튼이 접혀 있다**(`shouldFoldGuidanceChrome`).

→ 개요로 줌아웃만 해 두고 추종을 넣지 않으면, 사용자는 걷는 동안 화면을 자기
위치로 되돌릴 방법이 없다. 3.2의 [2]단계를 빼기로 한다면 **되돌릴 수단을 함께
설계해야 한다**(예: 안내 중에도 위치 보정 버튼만 남기기).

### 4.4 줌아웃 하한은 이탈 임계값이다

`indoorEntryTransitionForZoom`은 `indoorExitZoomThreshold`(15.6) **아래**에서만
`exit`을 낸다. 경로가 길어 그보다 축소해야 다 담기는 경우, 그대로 두면 도면이
닫히고 야외로 튕긴다.

→ `max(fitZoom, indoorExitZoomThreshold + 여유)`로 막되, **다 담기지 않을 수
있음을 받아들이는 것**이 맞다. 억지로 담으려다 실내에서 쫓겨나는 쪽이 나쁘다.

### 4.5 층 전환 스크림과 겹친다

층이 바뀌는 구간에는 `FloorTransitionScrim`이 화면을 덮는다(`widgets/
floor_transition_overlay.dart`). 스크림이 덮인 동안 카메라를 움직이면 사용자는
그 움직임을 못 보고, 걷히는 순간 이미 다른 자리에 가 있어 "순간이동"으로 읽힌다.

→ 스크림이 걷히는 시점(`_floorScrimOpacity`가 0으로 가는 때)에 맞춰 시작하거나,
반대로 **스크림 뒤에서 조용히 옮기고 연출을 생략**하는 선택지가 있다.

### 4.6 chrome 높이는 상태에 따라 다르다

`_floorFitTopChromePx`(132)는 검색창 + 카테고리 줄 기준이다. **안내 중에는 그
줄들이 접혀 있어** 실제 위쪽 여백이 훨씬 작다. 안내 연출에 같은 값을 쓰면 도면이
필요 이상으로 아래로 내려간다.

→ 안내 중용 chrome 높이(상단 초안 바 한 줄 + 하단 안내 배너)를 따로 잡아야 한다.

---

## 5. 검증 기준

구현 전에 합의할 것. 항목마다 이걸 통과한 뒤 다음으로 넘어간다.

### 기능

- [ ] 안내를 시작하면 **지금 층 경로 전체**가 화면 안에 들어온다(양 끝이 잘리지 않음).
- [ ] 그 배율에서 실내 도면이 유지된다 — 야외로 튕기지 않는다.
- [ ] 층이 바뀌면 **새 층 세그먼트** 기준으로 다시 배치된다.
- [ ] 재탐색(경로 이탈 후 재계산)에서는 연출이 발화하지 않는다.
- [ ] 연출은 안내당 **한 번만** 일어난다.

### 실패 조건 (이게 더 중요하다)

- [ ] 경로가 아주 짧을 때(바로 옆 매장) 발산하지 않는다 — 상자 폭이 0에 가까우면
      건너뛴다(`_fitCameraToRoute`의 `distanceMeters < 5` 가드와 같은 취지).
- [ ] 경로가 아주 길 때 이탈 임계값 아래로 내려가지 않는다(4.4).
- [ ] 연출 도중 사용자가 지도를 만지면 **연출이 사용자를 이기지 않는다**.
      (지금 코드에 이 판정이 없다 — 새로 필요하다.)
- [ ] 연출 도중 화면을 벗어나거나 안내를 끝내도 `mounted` 검사로 안전하게 끝난다.
- [ ] 걷는 동안 카메라가 크게 움직이지 않는다.

### 회귀

- [ ] 건물 탭 → 진입 연출(900ms, 세로 정렬)이 그대로다.
- [ ] 층 선택기 층 전환(500ms 재정렬)이 그대로다.
- [ ] 야외 "건물 입구까지" 자동 경로가 카메라를 가져가지 않는다(4.2).

---

## 6. 사람이 정해야 할 것

구현 전에 답이 필요한 갈림길. **여기가 이 문서의 핵심이다.**

### Q1. 개요 뒤에 "진행 화면"으로 들어갈 것인가

- **A안 — 개요만.** 전체 경로를 보여 주고 카메라를 놓아둔다. 구현이 가장 작다.
  대신 4.3 때문에 **안내 중 되돌릴 수단**을 같이 만들어야 한다.
- **B안 — 개요 → 진행.** 영상에 가깝다. 잠깐 멈춘 뒤 현재 위치로 줌인하고,
  이후 걸음을 따라 카메라가 따라간다. **추종 로직을 새로 만들어야 하고**,
  그때부터 "사용자가 지도를 만지면 추종을 멈춘다" 같은 판정이 줄줄이 붙는다.

권하는 쪽은 **A안으로 시작**이다. B안의 추종은 그 자체로 한 차수 분량이고,
개요 연출의 가치는 A안만으로도 대부분 나온다.

### Q2. 층 전환에서 스크림과 어떻게 나눌 것인가

- **A안 — 스크림 뒤에서 조용히.** 걷히면 이미 새 배치. 연출은 없지만 매끄럽다.
- **B안 — 걷힌 뒤 연출.** 극적이지만 층 전환마다 반복돼 피로할 수 있다.

### Q3. 회전을 경로 축에 맞출 것인가, 층 축을 유지할 것인가

경로의 긴 축과 층의 긴 축이 다르면 층 전환 때마다 지도가 크게 돈다.

- **A안 — 경로 축.** 갈 방향이 세로로 서서 읽기 좋다. 대신 회전이 잦다.
- **B안 — 층 축 유지.** 도면 배치가 안정적이다. 대신 경로가 비스듬히 눕는다.

### Q4. 연출 시간

3.2의 700 / 600 / 700ms는 **근거 없는 초안**이다. 진입 900ms·층 전환 500ms를
실기기에서 정한 것처럼, 이 값도 눌러 보고 정해야 한다.

---

## 7. 시작 지점

```
client/lib/screens/outdoor_map/outdoor_map_screen.dart
  _fitCameraToActiveFloor(...)        ← 이 함수를 읽고 시작한다. 형제를 만든다.
  showIndoorRouteTo(...)              ← 안내 시작 훅
  _onFloorChipSelected / _switchOverlayFloor  ← 층 전환 훅
  _applyRoute                          ← 4.2 결정을 건드리지 말 것

client/lib/screens/outdoor_map/building_orientation.dart   ← 기하 도구
client/lib/screens/outdoor_map/indoor_entry_zoom.dart      ← zoom 정책·임계값
client/lib/domain/guidance_chrome.dart                     ← 안내 중 chrome 규칙
```

기하 계산은 부호 하나만 틀려도 조용히 90도 어긋난다. 새로 만드는 계산은
`tests/unit_test/building_orientation_test.dart`처럼 **방위를 아는 입력을 만들어
되찾아 오는지** 확인하는 테스트를 함께 둔다.
