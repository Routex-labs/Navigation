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
| 갓 위젯 | `floor_plan_view`(3,229줄) | 야외 지도와 같은 방식으로 해체 |

**위젯 클래스가 하나도 없는 파일이 20개 / 2,794줄**이다. `widgets/`에 있다는 이유로
"UI 코드"로 읽히지만 실제로는 순수 함수라 위젯 없이 시험된다. 자리를 옮기면 그 사실이
이름에서 드러난다.

## 문제 2 — 한 함수가 여러 일을 한다

길이만 보면 긴 위젯 트리가 상위를 다 먹는다. 그래서 **책임의 종류**를 셌다 —
바깥 왕복(`await`), 화면 상태 변경(`setState`), 지도 쓰기, 사용자에게 말 걸기.
서로 다른 종류를 여럿 하고 있으면 쪼갤 후보다.

| 함수 | 줄 | await | setState | 지도쓰기 | 말 걸기 | 섞인 것 |
|---|---|---|---|---|---|---|
| `_onStyleLoaded` (floor_plan_view) | 371 | 51 | 0 | 31 | 0 | 이미지 등록 + 소스 등록 + 레이어 등록 + 초기 데이터 |
| `_buildShell` (map_shell) | 372 | 0 | 4 | 0 | 0 | 레이아웃 + 상태 전이 |
| `_requestTransitRoute` (map_shell) | 152 | 6 | 1 | 0 | 5 | 조회 + 파싱 + 상태 + 안내 문구 |
| `_buildBody` (outdoor_map) | 432 | 0 | 0 | 0 | 0 | 오버레이 14종 조립 |
| `_startRoute` (map_shell) | 178 | 7 | 1 | 0 | 0 | 후보 확정 + 계산 + 표시 |
| `_search` (search_panel) | 163 | 4 | 4 | 0 | 0 | 경량 검색 + 의미 검색 + 상태 |
| `onAltitude` (escalator detector) | 331 | 0 | 0 | 0 | 0 | 판정 단계 6개가 한 함수 |

파일별로는 `floor_plan_view`(334점) · `map_shell_screen`(285) · `outdoor_map_screen_route`(186)
· `search_panel`(167) 순이다.

**에스컬레이터 판정(`onAltitude`)은 손대지 않는다** — 알고리즘 재작성이 예정돼 있다.

## 문제 3 — 테스트

### 해결됨: 루트가 둘이던 것

`tests/unit_test/`에 83개가 평면으로 쌓여 있고 `test/`가 따로 있었다. CI가 한때
`tests/`만 돌려 `test/` 아래 337개가 **한 번도 실행되지 않은** 적이 있다.
`test/` 하나로 합치고 `lib/` 구조를 미러하게 했다(584e83a).

앞으로 규칙은 하나다 — **`lib/a/b/c.dart`의 테스트는 `test/a/b/c_test.dart`.**
`lib/`에서 파일을 옮기면 테스트도 같은 자리로 옮긴다.

### 남은 것 1: 한 파일이 여러 대상을 시험한다

`test/widgets/widgets_test.dart`가 본보기다 — `LocationMarker`·`UncertaintyCircle`·
`StatusBadge`·`EtaCard` 각각 하나씩 + `SearchPanel` 20개가 한 파일에 있다.
대상별로 가른다.

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
| `widgets/floor_facility_style.dart` | 390 |
| `screens/map_shell/directions_candidates.dart` | 280 |

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

| # | 할 일 | 크기 | 위험 |
|---|---|---|---|
| 1 | 테스트 루트 통합 | 83파일 | 없음(완료) |
| 2 | `widgets/`의 **위젯 아닌 20개**를 `core/map/`으로 | 2,794줄 | 낮음 — 순수 이동 |
| 3 | 화면 전용 위젯을 그 화면 밑으로 | ~3,500줄 | 낮음 |
| 4 | `widgets_test.dart` 같은 잡동사니 테스트 분해 | — | 없음 |
| 5 | `floor_plan_view._onStyleLoaded` 분해 | 371줄 | **중** — 실기기 확인 필요 |
| 6 | `map_shell_screen` 분해(part → 진짜 분리) | 2,953줄 | 중 |
| 7 | 직접 테스트 없는 큰 모듈에 테스트 | — | 없음 |

2~4는 기계적이라 한 번에 간다. 5부터는 야외 지도와 같은 방식(테스트 먼저 → 옮기고
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
