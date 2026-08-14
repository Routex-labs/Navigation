# 야외 지도 화면 해체 (refactor/outdoor-map-decomposition)

`outdoor_map_screen.dart`의 `OutdoorMapBodyState` 하나를 완전히 해체하는 **장기 브랜치**의
계획서다. 이 브랜치는 기능을 추가하지 않는다. 동작이 한 줄이라도 달라지면 그건 실패다.

## 무엇을 해체하나

시작 시점(2026-08-14) 측정값이다.

| 항목 | 값 |
|---|---|
| 파일 | 8,569줄 |
| 메서드·게터 | 216개 (본문 8,134줄) |
| 상태 필드 | 156개 |

필드 156개는 성격이 뚜렷하게 갈린다 — **한 클래스에 상태 기계 7개가 얹혀 있다.**

| 상태 기계 | 필드 | 성격 |
|---|---|---|
| 실내 오버레이·층 | 49 | 진입 여부, 활성 층, 타일 소스 세대, 페이드 |
| 경로·안내 | 32 | 야외/실내/대중교통/보류 경로, 완료 이력, ETA |
| GPS·위치 | 16 | 구독, 최신 픽스, 정확도, 추적 |
| PDR·앵커 | 16 | 앵커, 배치 모드, 궤적, 보정 |
| 에스컬레이터·전환 | 13 | 탑승 판정, 활강, 전환 큐 |
| 지도·스타일·레이어 | 12 | 컨트롤러, 스타일 준비, 카메라 |
| 그 외 | 18 | 입구, 진행률, 리트라이 타이머 |

## 목표 상태

```
screens/outdoor_map/
  outdoor_map_screen.dart      위젯 + build + 상태 기계들의 조립(목표 1,000줄 이하)
  session/
    gps_session.dart           위치 구독·건물 판정
    pdr_anchor_session.dart    앵커 배치·세션 결속
    indoor_overlay_session.dart 진입 여부·활성 층·타일 세대
    route_presentation.dart    어떤 경로를 지금 그릴지
  layers/                      (이미 시작됨) 지도에 쓰기만 하는 모듈
    route_map_layers.dart  transit_map_layers.dart  pdr_debug_map_layers.dart
    indoor_overlay_layers.dart  location_layers.dart  …
  camera/                      카메라 명령(계산은 이미 widgets/floor_camera_*)
```

**에스컬레이터·층 전환(필드 13, 640줄)은 이 브랜치에서 건드리지 않는다.** 알고리즘
재작성이 예정돼 있어, 지금 옮기면 그 작업과 정면으로 충돌한다. 대신 그 주변에 이음매만
만들어 둔다.

## 깨면 안 되는 계약

셸이 `GlobalKey`로 부르는 19개다. 이름·시그니처가 바뀌면 다른 브랜치의 PR이 전부 깨진다.

```
clearAllRoutes clearHighlight currentFloor focusBuilding focusPoint focusStore
isAtIndoorBuilding outdoorSearchCenter reachFromCurrentPosition realignToActiveFloor
recalibrate resolveIndexEntry routeOriginPoint setInteractive showIndoorRouteTo
showIndoorToOutdoorRouteTo showOutdoorToIndoorRouteTo showRouteTo startLocationPlacement
```

해체가 끝나도 이 19개는 같은 자리에 같은 이름으로 남는다. 안쪽이 누구에게 위임하든
바깥에서 보이는 문은 그대로다.

## 이 브랜치의 제1 제약 — rebase로 살아남기

이 브랜치는 오래 살고, 그동안 `main`에는 다른 PR이 계속 들어온다. **해체 방식보다 rebase
생존성이 먼저다.** 아래 다섯 개는 취향이 아니라 규칙이다.

1. **한 커밋 = 한 관심사.** 섞으면 충돌이 어느 작업의 것인지 알 수 없다.
2. **옮길 때 고치지 않는다.** 본문·주석을 글자 그대로 옮긴다. 이름 변경은 `_` 프라이버시
   때문에 불가피할 때만. 옮기면서 다듬으면 충돌 해결이 "어느 쪽이 맞는지 판단"이 되고,
   그 판단을 rebase마다 반복하게 된다.
3. **이동 대장(MOVES.md)을 남긴다.** `옛 심볼 → 새 파일:새 심볼`. rebase 충돌이 나면
   "이 함수 어디 갔지"를 찾는 데 드는 시간이 대부분인데, 대장이 있으면 기계적으로 끝난다.
4. **안 변하는 곳부터 뗀다.** 디버그·레이어 등록처럼 남이 잘 안 건드리는 코드가 먼저고,
   경로·에스컬레이터처럼 활발한 코드가 나중이다. 충돌 총량이 줄어든다.
5. **필드를 옮기는 커밋은 마지막에.** 필드 참조는 파일 전체에 흩어져 있어 충돌 면적이
   가장 넓다. 메서드를 다 뗀 뒤에 남은 필드를 옮긴다.

## 순서

각 단계는 앞 단계가 끝나야 시작할 수 있다(의존 방향이 그렇다).

| # | 단계 | 대상 | 예상 |
|---|---|---|---|
| 1 | 레이어 쓰기 모듈화 | 위치·목적지·강조·스크림·건물·외곽선 sync | ~740줄 |
| 2 | 카메라 명령 분리 | fit·animate·recenter | ~660줄 |
| 3 | 지도 탭 판정 분리 | 탭 → 매장/노드 확정 | ~470줄 |
| 4 | GPS 세션 추출 | 필드 16 + 메서드 | ~460줄 |
| 5 | PDR 앵커 세션 추출 | 필드 16 + 메서드 | ~360줄 |
| 6 | 실내 오버레이 세션 추출 | 필드 49 + 타일 등록 | ~700줄 |
| 7 | 경로 표시 상태 추출 | 필드 32 + 표시 판단 | ~940줄 |
| 8 | build 분해 | 오버레이 위젯들 | ~780줄 |

1~3은 상태를 옮기지 않는다(호출부가 데이터를 넘긴다). 4부터가 진짜 해체다.

## 검증 게이트

단계마다 아래를 전부 통과해야 다음으로 넘어간다. 하나라도 빨간불이면 그 단계는 되돌린다.

- `flutter analyze` 0건
- `flutter test tests/unit_test/` + `flutter test test/` 전부 통과
- 공개 API 19개의 이름·시그니처 불변 (`grep`으로 확인)
- **동작 동일성의 근거를 커밋 메시지에 적는다.** "옮기기만 했다"면 그렇게, 로직이 한 줄이라도
  바뀌었으면 무엇이 왜 바뀌었는지.

### 데스크에서 증명할 수 없는 것

실내 도면 렌더링·PDR·층 전환은 책상에서 참/거짓이 갈리지 않는다
([현장 검증 체크리스트](field-verification-thehyundai.md)의 앞부분 참고). 그래서 이 브랜치는
**현장 검증을 통과하기 전까지 병합하지 않는다.** 단계 6(실내 오버레이)은 그중에서도 가장
위험해 — 실기기에서 도면이 통째로 검게 뜬 이력이 있는 코드다 — 현장 기준선을 잡은 뒤에
착수한다.
