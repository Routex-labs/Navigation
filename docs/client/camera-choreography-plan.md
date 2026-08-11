# 카메라 연출 — 안내 시작·층 전환

안내를 시작하는 순간과 층이 바뀌는 순간에 **카메라를 어떻게 움직이는지**.
원래는 다른 세션에 넘길 계획 문서였고, 지금은 구현된 내용과 그렇게 정한 이유를
남긴 기록이다.

- 파일·심볼 참조는 브랜치 `feature-motion` 기준이다.
- [4. 함정](#4-먼저-알아야-할-함정)은 구현하며 실제로 밟은 것들이라, 이 근처를
  고칠 때 먼저 읽는 편이 빠르다.

---

## 1. 하려는 것

프로모션 영상(`프로모션.mp4`)의 안내 화면처럼, 안내가 시작되는 순간 카메라가
**한 번 크게 물러서 경로 전체를 보여 주는** 연출을 넣는다.

| 순간 | 그림 | 연출 |
|---|---|---|
| 길안내 시작 | 지금 층 경로 전체가 한눈에 | 700ms 줌아웃 + 경로 축으로 회전 |
| 층 전환 | 새 층 경로 기준으로 재배치 | **없음** — 스크림 뒤에서 조용히 |
| 재탐색 | — | **없음** |

"재배치되는 듯한" 극적인 효과는 **안내당 한 번만** 준다. 매 걸음마다 카메라가
크게 움직이면 연출이 아니라 멀미다.

---

## 2. 어떻게 정했나

계획 단계에서 갈림길 네 개를 먼저 정하고 들어갔다.

| | 물음 | 정한 것 |
|---|---|---|
| Q1 | 개요 뒤에 "진행 화면"(카메라 추종)까지 갈까 | **개요만.** 추종은 그 자체로 한 차수 분량이고, 개요만으로도 가치의 대부분이 나온다 |
| Q2 | 층 전환에서 스크림 앞뒤 어디서 움직일까 | **스크림 뒤에서 조용히.** 걷힌 뒤 연출하면 층마다 반복돼 피로하다 |
| Q3 | 회전을 경로 축에 맞출까, 층 축을 유지할까 | **경로 축.** 갈 방향이 세로로 서야 읽힌다 |
| Q4 | 연출 시간 | 700ms(개요) — 진입 900ms보다 짧고 층 전환 500ms보다 길다 |

**Q1을 "개요만"으로 정하면 빚이 하나 따라온다.** 카메라가 걸음을 따라가지 않는데
안내 중에는 하단 바가 통째로 접혀([shouldFoldGuidanceChrome]) 사용자가 화면을
자기 위치로 되돌릴 수단이 없다. 그래서 [`GuidanceRecenterButton`](../../client/lib/widgets/guidance_recenter_button.dart)을
함께 넣었다 — 접힌 층 선택기 자리에, 안내 중에만.

---

## 3. 구현

### 3.1 기존 코드를 대체했다

이 작업의 실제 모양은 "새로 만들기"가 아니라 **대체**였다. 안내 시작에는 이미
`_fitCameraToIndoorRoute`가 있었고, 그게 `newLatLngBounds`를 써서 **bearing을 0으로
되돌리고 있었다**([4.1](#41-newlatlngbounds는-지도를-정북으로-되돌린다)). 진입·층
전환에서 애써 세로로 세운 도면이 안내를 시작하는 순간 도로 비스듬히 눕던 자리다.

### 3.2 지금 구조

```
_animateCameraToFitBox(box, center, topChromePx, bottomChromePx, duration)
  ├─ portraitBearingFor(box.longAxis, 현재 bearing)   긴 축을 화면 세로로
  ├─ zoomToFitRotatedBox(..., 가용 높이 = 화면 − 위아래 chrome)
  ├─ max(fitZoom, indoorExitZoomThreshold + 0.3)      실내 유지 하한
  ├─ offsetByMeters(center, bearing, chrome 보정)     가려지지 않는 띠 한가운데로
  └─ animateCamera(newCameraPosition(...))

    ↑ 공통 몸통. 상자를 어떻게 구하느냐만 호출부가 정한다.

_fitCameraToActiveFloor    minAreaBoxFor(층 외곽선)        chrome 132 / 112
_fitCameraToRouteSegment   routeBoxFor(경로 점, minSide)   chrome  92 /  92
```

chrome 보정과 줌 하한을 한 함수에만 둔 이유는, 각자 갖게 두면 한쪽만 고쳐져
**도면을 맞춘 화면과 경로를 맞춘 화면에서 같은 지점이 다른 높이에 오기** 때문이다.

`routeBoxFor`(`building_orientation.dart`)는 `minAreaBoxFor`와 같은 상자를 구하되
퇴화한 입력을 견딘다 — 자세한 것은 [4.7](#47-경로-상자는-퇴화한다).

### 3.3 언제 발화하나

| 시점 | 자리 | 연출 |
|---|---|---|
| 안내 시작 | `showIndoorRouteTo` → `_computeAndShow*(playOverview: true)` | 700ms 개요 |
| 층 전환 | `_swapIndoorFloorSmoothly`, 스크림이 덮인 동안 | `Duration.zero` |
| 층 전환 후 재계산 | `_rerouteAfterVerticalTransfer` | 없음 |
| 경로 이탈 재탐색 | `_rerouteIndoorFromCurrentPosition` | 없음 |

`playOverview`에 **기본값을 두지 않았다.** 안내 시작이냐 재탐색이냐에 따라 답이
정반대라, 빠뜨리면 조용히 틀린 쪽으로 굴러간다.

"안내당 한 번"은 **별도 플래그 없이** 지켜진다 — 켜는 자리가 사용자가 목적지를
고른 순간 하나뿐이기 때문이다.

---

## 4. 먼저 알아야 할 함정

### 4.1 `newLatLngBounds`는 지도를 정북으로 되돌린다

이 API는 항상 정북 정렬 기준으로 계산해서 bearing이 0으로 리셋된다
(`widgets/floor_plan_view.dart`의 같은 주석 참고). 야외용
`_fitCameraToRoute(DirectionsRoute)`는 아직 이걸 쓰는데, 야외에는 세워 둘 도면이
없어서 문제가 되지 않는다. **실내 경로에는 쓰지 말 것.**

### 4.2 자동 경로는 카메라를 가져가지 않기로 했다

`_applyRoute`는 `_userDestination != null`일 때만 `_fitCameraToRoute`를 부른다.
GPS가 잡힐 때마다 자동 계산되는 "건물 입구까지" 경로가 화면을 도시 축척으로
끌고 가던 것을 막은 결정이다. **이 분기를 되돌리지 말 것.**

### 4.3 카메라 추종은 없다 — 되돌릴 수단이 대신 있다

`_syncPdrCurrentLayer`는 마커 레이어만 갱신한다. 걸어도 카메라는 그대로다.
개요로 물러선 뒤 사용자가 화면을 되돌리는 수단은 `GuidanceRecenterButton`이다
(안내 중에만, 접힌 층 선택기 자리).

그 버튼은 **카메라만 옮긴다.** 이름이 비슷한 "위치 보정"은 PDR 앵커를 다시 잡는
추정 보정이라 다른 조작이다 — 걷는 도중에 앵커를 다시 잡으면 진행률과 이탈
판정의 기준이 통째로 바뀐다. 그래서 아이콘도 `Icons.near_me`로 달리 뒀다.

### 4.4 줌아웃 하한은 이탈 임계값이다

`indoorEntryTransitionForZoom`은 `indoorExitZoomThreshold`(15.6) **아래**에서만
`exit`을 낸다. 경로가 길어 그보다 축소해야 다 담기는 경우, 그대로 두면 도면이
닫히고 야외로 튕긴다.

→ `max(fitZoom, indoorExitZoomThreshold + 0.3)`으로 막고, **다 담기지 않는 것을
받아들인다.** 경로 끝이 조금 잘리는 쪽이 실내에서 쫓겨나는 것보다 낫다.

### 4.5 층 전환 스크림과 겹친다

층이 바뀌는 구간에는 `FloorTransitionScrim`이 화면을 덮는다. 스크림이 덮인 동안
카메라를 움직이면 사용자는 그 움직임을 못 보고, 걷히는 순간 이미 다른 자리에 가
있어 "순간이동"으로 읽힌다 — **그걸 노렸다**(Q2). 덮인 동안 `Duration.zero`로
옮겨 두면 사용자는 새 층을 이미 맞춰진 상태로 만난다.

### 4.6 chrome 높이는 상태에 따라 다르다

`_floorFitTopChromePx`(132)는 검색창 + 카테고리 줄 기준이다. **안내 중에는 그
줄들이 접혀 있다** — 칩 줄은 통째로 사라지고 상단 바도 도착지 한 줄로 줄어들며,
하단 바는 아예 안 그려지고 ETA 카드만 남는다. 그래서 안내용으로
`_guidanceFitTopChromePx`(92) / `_guidanceFitBottomChromePx`(=`_bottomBarLiftPx`)를
따로 뒀다.

### 4.7 경로 상자는 퇴화한다

건물 외곽선과 달리 경로는 넓이가 없을 수 있고, 그러면 두 곳에서 깨진다.

- **점이 둘뿐인 곧은 경로**(복도 한 구간)는 `minAreaBoxFor`가 3점을 요구해 null을
  낸다 → 연출이 통째로 사라진다.
- **일직선 경로**는 짧은 변이 0으로 수렴한다. `zoomToFitWidth`가
  `log(가용폭 / 폭)`이라 **zoom이 무한대로 발산하고 지도가 사라진다.**

`routeBoxFor`가 중점을 끼워 3점을 만들고 두 변을 `_routeFitMinSideM`(12 m)으로
받친다. 긴 축 방위각은 손대지 않는다 — 곧은 경로에서도 갈 방향은 그대로 나와야
카메라를 세울 수 있다.

---

## 5. 검증 기준

구현 전에 합의하고, 그 기준으로 확인했다.

### 기능

- [x] 안내를 시작하면 지금 층 경로 전체가 화면 안에 들어온다.
- [x] 그 배율에서 실내 도면이 유지된다 — 야외로 튕기지 않는다([4.4](#44-줌아웃-하한은-이탈-임계값이다)).
- [x] 층이 바뀌면 새 층 세그먼트 기준으로 다시 배치된다(스크림 뒤).
- [x] 재탐색에서는 연출이 발화하지 않는다.
- [x] 연출은 안내당 한 번만 일어난다.

### 실패 조건 (이게 더 중요하다)

- [x] 경로가 아주 짧을 때(바로 옆 매장) 발산하지 않는다 — 5 m 미만은 건너뛰고,
      상자 변은 12 m로 받친다. `tests/unit_test/building_orientation_test.dart`의
      `경로 상자` 그룹이 지킨다.
- [x] 경로가 아주 길 때 이탈 임계값 아래로 내려가지 않는다.
- [x] 연출 도중 화면을 벗어나거나 안내를 끝내도 `mounted` 검사로 안전하게 끝난다.
- [x] 걷는 동안 카메라가 크게 움직이지 않는다 — 걸음에 걸린 연출이 없다.
- [ ] **연출 도중 사용자가 지도를 만지면 연출이 사용자를 이기지 않는다.**
      아직 이 판정이 없다 — [7. 남은 것](#7-남은-것) 참고.

### 회귀

- [x] 건물 탭 → 진입 연출(900ms, 세로 정렬)이 그대로다.
- [x] 층 선택기 층 전환(500ms 재정렬)이 그대로다.
- [x] 야외 "건물 입구까지" 자동 경로가 카메라를 가져가지 않는다([4.2](#42-자동-경로는-카메라를-가져가지-않기로-했다)).

---

## 6. 실기기에서 확인할 것

값을 눌러 보고 정해야 하는 것들이다. 진입 900ms·층 전환 500ms를 그렇게 정한
것처럼, 아래도 화면에서 봐야 안다.

- 개요 700ms가 "물러선다"로 읽히는지, 굼뜨게 느껴지는지.
- `_guidanceFitTopChromePx`(92)가 실제 안내 화면의 상단 바와 맞는지. 계산으로
  뽑은 값이라 기기 노치·SafeArea에서 어긋날 수 있다.
- 경로 축 회전(Q3-A)이 층 전환마다 얼마나 크게 도는지. 너무 심하면 Q3-B(층 축
  유지)로 되돌리는 것이 선택지다. 층 전환은 에스컬레이터를 실제로 타지 않아도
  볼 수 있다 — 디버그 모드를 켜면 다층 안내 중 왼쪽 아래에 **강제 층 전환**
  버튼이 뜬다(`_debugForceFloorTransition`, 시작→확정 경로를 합성 transition으로
  태우므로 보이는 것이 곧 실제 연출이다).
- `_walkingViewZoom`(18.0 = `indoorTilesMaxZoom`)이 걷는 화면으로 적당한지.

---

## 7. 남은 것

**연출 도중 사용자 조작 판정.** 700ms 개요가 도는 중에 사용자가 지도를 잡으면
지금은 연출이 이긴다. MapLibre의 카메라 이동 원인(제스처/API)을 구분해 받아야
해서 이번 범위에서 뺐다. 실제로 밟으려면 안내 시작 직후 700ms 안에 지도를
만져야 하고, 만져도 연출이 끝나면 조작이 다시 먹는다.

**카메라 추종**(Q1-B)은 의도적으로 안 넣었다. 넣기로 하면 "사용자가 지도를
만지면 추종을 멈춘다" 같은 판정이 줄줄이 붙으므로, 위 항목과 함께 한 차수로
다루는 편이 맞다.

---

## 8. 시작 지점

```
client/lib/screens/outdoor_map/outdoor_map_screen.dart
  _animateCameraToFitBox(...)          ← 공통 몸통. 여기부터 읽는다
  _fitCameraToRouteSegment(...)        ← 안내 개요
  _fitCameraToActiveFloor(...)         ← 층 도면 fit
  _swapIndoorFloorSmoothly(...)        ← 층 전환(스크림 뒤 재배치)
  _recenterOnCurrentPosition(...)      ← "내 위치로"
  _applyRoute                          ← 4.2 결정을 건드리지 말 것

client/lib/screens/outdoor_map/building_orientation.dart   ← 기하 도구·routeBoxFor
client/lib/screens/outdoor_map/indoor_entry_zoom.dart      ← zoom 정책·임계값
client/lib/widgets/guidance_recenter_button.dart           ← 안내 중 되돌릴 수단
client/lib/domain/guidance_chrome.dart                     ← 안내 중 chrome 규칙
```

기하 계산은 부호 하나만 틀려도 조용히 90도 어긋난다. 새로 만드는 계산은
`tests/unit_test/building_orientation_test.dart`처럼 **방위를 아는 입력을 만들어
되찾아 오는지** 확인하는 테스트를 함께 둔다.
