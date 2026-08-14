# 클라이언트 구조 개편 계획

"함수 하나는 한 가지 일만", "테스트는 그 한 가지를 지킨다", "디렉터리는 그 성격을
드러낸다" — 이 셋을 위해 **무엇을 어디로 옮길지**를 측정값으로 정한 문서다.

[야외 지도 해체 계획](outdoor-map-decomposition.md)은 화면 하나를 다루고, 이 문서는
`client/lib` 전체를 다룬다. 겹치는 부분은 그쪽이 단일 출처다.

## 지금 값 (2026-08-14)

| 항목 | 값 |
|---|---|
| `lib/` | 52,812줄 / 204파일 |
| `test/` | 1,415개 통과 |
| 25줄 넘는 함수 | 288개 |

디렉터리별 크기.

| 디렉터리 | 줄 | 파일 |
|---|---|---|
| `lib/widgets` | 13,610 | 49 |
| `lib/screens/outdoor_map` | 11,355 | 24 |
| `lib/features/indoor_navigation/*` | 9,168 | 30 |
| `lib/domain` | 5,087 | 29 |
| `lib/screens/map_shell` | 3,233 | 2 |
| `lib/models` | 2,377 | 14 |
| 나머지 | 7,982 | 56 |

## 문제 1 — `lib/widgets/`가 잡동사니다

가장 큰 디렉터리인데 **성격이 넷 섞여 있다.**

| 성격 | 예 | 어디로 가야 하나 |
|---|---|---|
| 진짜 재사용 위젯 | `status_badge` `sheet_header` `filter_pill` | `widgets/` 그대로 |
| **위젯이 아닌 순수 규칙·스타일** | `store_label_fit` `floor_facility_style` `category_map_*` `floor_camera_*` `store_label_anchor` | `core/map/` — 위젯 트리 없이 시험되는 코드다 |
| 특정 화면 전용 시트·바 | `search_panel` `map_top_bar` `outdoor_poi_sheet` `route_field_results` | 그 화면 밑(`screens/<화면>/widgets/`) |
| 갓 위젯 | `floor_plan_view`(3,229줄) | ~~해체~~ → **지웠다.** 앱에서 닿지 않았다(문제 4) |

**위젯 클래스가 하나도 없는 파일이 20개 / 2,794줄**이다. `widgets/`에 있다는 이유로
"UI 코드"로 읽히지만 실제로는 순수 함수라 위젯 없이 시험된다. 자리를 옮기면 그 사실이
이름에서 드러난다.

## 문제 2 — 한 함수가 여러 일을 한다

길이만 보면 긴 위젯 트리가 상위를 다 먹는다. 그래서 **책임의 종류**를 셌다 —
바깥 왕복(`await`), 화면 상태 변경(`setState`), 지도 쓰기, 사용자에게 말 걸기.
서로 다른 종류를 여럿 하고 있으면 쪼갤 후보다.

| 함수 | 줄 | await | setState | 지도쓰기 | 말 걸기 | 섞인 것 |
|---|---|---|---|---|---|---|
| ~~`_onStyleLoaded` (floor_plan_view)~~ | 371 | 51 | 0 | 31 | 0 | 52줄로 줄인 뒤, 파일째 삭제(문제 4) |
| `_buildShell` (map_shell) | 372 | 0 | 4 | 0 | 0 | 레이아웃 + 상태 전이 |
| `_requestTransitRoute` (map_shell) | 152 | 6 | 1 | 0 | 5 | 조회 + 파싱 + 상태 + 안내 문구 |
| `_buildBody` (outdoor_map) | 432 | 0 | 0 | 0 | 0 | 오버레이 14종 조립 |
| `_startRoute` (map_shell) | 178 | 7 | 1 | 0 | 0 | 후보 확정 + 계산 + 표시 |
| `_search` (search_panel) | 163 | 4 | 4 | 0 | 0 | 경량 검색 + 의미 검색 + 상태 |
| `onAltitude` (escalator detector) | 331 | 0 | 0 | 0 | 0 | 판정 단계 6개가 한 함수 |

파일별로는 `floor_plan_view`(334점) · `map_shell_screen`(285) · `outdoor_map_screen_route`(186)
· `search_panel`(167) 순이었다. 1위가 삭제됐으니 **지금 남은 최악은 `map_shell_screen`**이고,
그 다음이 한 함수에 판정 6단계가 들어 있는 `onAltitude`(에스컬레이터 검출기)다.

**에스컬레이터 판정(`onAltitude`)은 손대지 않는다** — 알고리즘 재작성이 예정돼 있다.

## 문제 3 — 테스트

### 해결됨: 루트가 둘이던 것

`tests/unit_test/`에 83개가 평면으로 쌓여 있고 `test/`가 따로 있었다. CI가 한때
`tests/`만 돌려 `test/` 아래 337개가 **한 번도 실행되지 않은** 적이 있다.
`test/` 하나로 합치고 `lib/` 구조를 미러하게 했다(584e83a).

앞으로 규칙은 하나다 — **`lib/a/b/c.dart`의 테스트는 `test/a/b/c_test.dart`.**
`lib/`에서 파일을 옮기면 테스트도 같은 자리로 옮긴다.

### 해결됨: 한 파일이 여러 대상을 시험하던 것

`widgets_test.dart` 하나가 `LocationMarker`·`UncertaintyCircle`·`StatusBadge`·
`EtaCard`·`SearchPanel` 다섯을 시험하고 있었다. 대상별로 갈랐다(430829a).
`widget_test.dart`는 map_shell이 아니라 **앱 전체 스모크**여서 `test/app_test.dart`로
옮겼다. 이때 케이스 수는 1,415개 그대로였다(지금은 죽은 화면 삭제로 1,397개).

### 남은 것 2: 직접 테스트가 없는 모듈

같은 이름의 테스트 파일이 없는 `lib` 파일이 118개다. **이게 곧 "미검증"은 아니다** —
화면 전체를 띄우는 행동 테스트가 대신 덮는 코드가 많다. 다만 그런 테스트는 무엇이
깨졌는지 짚어 주지 못한다.

직접 테스트가 없으면서 큰 것들.

| 파일 | 줄 |
|---|---|
| `features/indoor_navigation/application/corridor_position_tracker.dart` | 2,093 |
| `features/indoor_navigation/application/indoor_guidance_session.dart` | 876 |
| `features/indoor_navigation/application/floor_map_matcher.dart` | 705 |
| `models/transit_route.dart` | 462 |
| `core/map/floor_facility_style.dart` | 390 |
| `screens/map_shell/directions_candidates.dart` | 280 |

## 문제 4 — 앱에서 닿지 않는 화면이 있었다 (해결: 5,135줄 삭제)

5단계(`floor_plan_view._onStyleLoaded` 분해)를 하다 발견했다. **이 저장소에서 가장 큰
파일이 실행 중인 앱에서 한 번도 그려지지 않았다.**

근거는 셋이다.

1. `FloorPlanView`를 쓰는 화면은 `route_guide`와 `debug/floor_map_preview` 둘뿐이다.
2. `route_guide`로 가는 유일한 길은 `destination` 화면인데, **`AppRoutes.destination`을
   push하는 코드가 없다.** `floor_map_preview`·`pdr_svg_test`·`api_health`도 마찬가지로
   라우트 표에만 있고 부르는 곳이 없다.
3. 이름 없는 네비게이션(`Navigator.push`/`MaterialPageRoute`)이 **0건**이고,
   AndroidManifest에도 딥링크 intent-filter가 없다(LAUNCHER 하나뿐).

### 경계를 손으로 고르지 않았다

처음 손으로 센 것은 4,185줄이었는데 **실제로는 5,135줄이었다.** 화면을 지우면
그 화면만 쓰던 파일이 죽고, 그 파일만 보던 테스트가 죽는다. 그래서 import
그래프의 **고정점**을 구했다 — 더 이상 새로 죽는 게 없을 때까지 반복.

뿌리를 잘못 잡으면 크게 틀린다. `main.dart` 하나만 뿌리로 두면 테스트 30여 개가
쓰는 mock 리포지토리까지 "죽음"으로 나온다. 뿌리는 **실제 진입점 전부**여야 한다 —
`main.dart`, 자기 `main()`을 가진 실기기 하니스, 그리고 살아남는 테스트들.

그렇게 해도 자동으로 안 끊기는 고리가 있었다. `FloorPlanView`와 그 테스트가
**서로를 살려주고 있었다** — 테스트가 파일을 import하니 파일이 "닿는다"로 세어지고,
그 파일을 쓰는 게 그 테스트뿐이니 테스트도 "살아 있다"로 세어진다. 여기서
기준은 사람이 정한다: **제품 코드에서 부르는 곳이 없으면 죽은 것이다. 테스트가
있다는 건 커버리지의 증거지 사용의 증거가 아니다.**

| 지운 것 | 줄 |
|---|---|
| `widgets/floor_plan_view.dart` | 2,772 |
| `core/map/floor_plan_layers.dart` | 508 |
| `screens/debug/pdr_svg_test_screen.dart` | 468 |
| `screens/route_guide/route_guide_screen.dart` | 335 |
| `screens/debug/floor_map_preview_screen.dart` | 266 |
| `screens/destination/destination_screen.dart` | 156 |
| `screens/arrival/arrival_screen.dart` | 115 |
| `screens/debug/api_health_check_screen.dart` | 73 |
| `core/floor_switch_timing.dart` | 68 |
| `widgets/uncertainty_circle.dart` | 24 |
| `repositories/mock_place_detail_repository.dart` | 12 |
| 테스트 3개 + `app_test.dart`의 7블록 | 274 |

### 살려 둔 것 — 자동 판정이 틀렸던 셋

| 파일 | 왜 살렸나 |
|---|---|
| `repositories/mock_*_repository.dart` | 테스트 30여 개가 쓰는 대역이다 |
| `features/indoor_navigation/debug/pdr_device_harness*` | 자기 `main()`을 가진 실기기 하니스 |
| `repositories/tmap_transit_repository.dart` | 카카오 키가 소진되면 되돌릴 대체 구현이라고 코드가 명시한다 |

### 남은 것

라우트가 **하나**가 됐다(`/` → `MapShellScreen`). `AppRoutes`에 상수 하나만
남긴 이유는 `initialRoute`와 `routes`가 같은 문자열을 봐야 하기 때문이다.

교훈 한 줄: **push가 없는 라우트는 죽은 코드다.** 화면 여섯 개가 라우트 표에만
등록된 채 5,135줄을 붙들고 있었고, 그중 하나는 저장소에서 가장 큰 파일이었다.

## 목표 구조

이미 잘 돼 있는 곳이 하나 있다 — `features/indoor_navigation/`이 `contract/`(계약) ·
`application/`(headless 로직) · `platform/`(채널) · `debug/`로 갈려 있다.
**그 모양을 나머지에 퍼뜨린다.**

```
lib/
  core/            앱 전역 설정·서비스 로케이터
    map/           지도 규칙·스타일 (위젯 아닌 것들이 여기로)
  domain/          순수 계산 (다익스트라·경로 안내·좌표) — 지금도 이대로 좋다
  models/          직렬화 값 타입
  repositories/    바깥 세계(HTTP)
  features/
    indoor_navigation/  contract · application · platform · debug  ← 본보기
  screens/
    outdoor_map/   화면 + 그 화면 전용 조각
    map_shell/     〃
  widgets/         **여러 화면이 실제로 함께 쓰는 위젯만**
```

## 순서

앞이 끝나야 뒤가 깨끗하다.

| # | 할 일 | 크기 | 상태 |
|---|---|---|---|
| 1 | 테스트 루트 통합 | 83파일 | **완료** (584e83a) |
| 2 | `widgets/`의 위젯 아닌 17개를 성격별로 | 2,794줄 | **완료** (1428a68) |
| 3 | 화면 전용 위젯 25개를 그 화면 밑으로 | 8,000줄 | **완료** (1428a68) |
| 4 | 여러 대상을 시험하던 테스트 분해 | 2파일 | **완료** (430829a) |
| 5 | `floor_plan_view._onStyleLoaded` 분해 | 371 → 52줄 | **완료** (a3c1909) |
| 6 | 앱에서 닿지 않는 화면 삭제 | 5,135줄 | **완료** (512188d, aaa17e3) |
| 7 | `map_shell_screen` 분해 | 2,953줄 | 중 |
| 8 | 직접 테스트 없는 큰 모듈에 테스트 | — | 없음 |

### 1~4를 마친 결과

| 디렉터리 | 전 | 후 |
|---|---|---|
| `lib/widgets` | 13,610줄 / 49개 | **4,232줄 / 11개** |
| `lib/core/map` | — | 2,340줄 / 12개 |
| `lib/screens/map_shell/widgets` | — | 5,789줄 / 12개 (+ `place_detail/` 5개) |
| `lib/screens/outdoor_map/widgets` | — | 974줄 / 9개 |
| 테스트 루트 | `test/` + `tests/unit_test/` | `test/` 하나 |

**`lib/widgets/`에 남은 11개는 전부 두 화면 이상이 실제로 쓴다.** 그 기준을
README 맨 위에 적어 두었다 — 기준이 없으면 다시 쌓인다.

5부터는 야외 지도와 같은 방식(테스트 먼저 → 옮기고
→ 원본과 대조 → 실기기 확인)을 쓴다.

## 이 개편이 건드리는 다른 곳

파일을 옮기면 **같이 고쳐야 하는 것**이 넷이다. 빠뜨리면 문서가 먼저 썩는다.

| 대상 | 무엇을 |
|---|---|
| `client/test/` | `lib/` 구조를 미러하므로 **같은 자리로 함께 옮긴다** |
| `client/lib/widgets/README.md` | 위젯 목록을 문서화하고 있다. 옮긴 파일은 여기서 지운다 |
| `docs/client/*.md` | 파일 경로를 본문에 적어 둔 문서가 여럿이다(`grep -rn 'lib/widgets/' docs/`) |
| `.github/workflows/ci.yml` | 지금은 `test/`·`integration_test/`만 가리켜 경로 고정이 없다 — 이 개편으로는 바뀌지 않는다 |

**백엔드는 영향이 없다.** API 계약(JSON)이 바뀌지 않고, 경로 계산은 그대로 클라이언트
온디바이스다. 클라이언트 디렉터리 이름은 백엔드가 알지 못한다.
