# `lib/map` — 지도에 무엇을 어떻게 그릴지의 값과 계산

색·글자 크기·아이콘·레이어 표현식을 만든다. **위젯이 아니다** — MapLibre에 넘길
값을 만들 뿐이고, 실제로 지도에 쓰는 것은 `screens/`가 한다.

한때 이 파일들은 `core/`(앱 설정) 안에 있었다. 그 폴더의 README는 스스로 "설정과
전역 배선"이라 선언하고 구성 파일로 둘만 적어 두었는데 실제로는 18개가 들어와
있었고, 결국 라벨 계산이 화면을 import하는 화살표까지 생겼다. 그래서 뗐다.

## 구성 파일

| 무엇 | 파일 |
|---|---|
| 도면 폴리곤 색 | [`palette.dart`](palette.dart) |
| 라벨 글자색·헤일로·고정 크기 | [`label_style.dart`](label_style.dart) |
| 경로선 색·굵기 | [`route_style.dart`](route_style.dart) |
| 글꼴 스택 | [`fonts.dart`](fonts.dart) |
| 대분류 색·글리프 | [`category_icon.dart`](category_icon.dart) |
| 카테고리 강조 fill·필터·라벨 | [`category_map_fill.dart`](category_map_fill.dart) · [`category_map_filter.dart`](category_map_filter.dart) |
| 라벨 아이콘 배지 | [`category_map_icon.dart`](category_map_icon.dart) |
| POI·편의시설 스타일 | [`floor_facility_style.dart`](floor_facility_style.dart) |
| 매장명 라벨 크기 맞춤 | [`store_label_fit.dart`](store_label_fit.dart) |
| 한 폴리곤에 여럿일 때 라벨 칸 나누기 | [`store_label_anchor.dart`](store_label_anchor.dart) |
| 도착지 핀 비트맵 | [`destination_pin.dart`](destination_pin.dart) |
| 현재 위치 마커 비트맵·치수 | [`location_marker_icon.dart`](location_marker_icon.dart) |
| 아이콘 PNG 캐시 | [`icon_cache.dart`](icon_cache.dart) |
| GeoJSON 조립 | [`geojson.dart`](geojson.dart) |
| 카메라 가둠 | [`floor_camera_bounds.dart`](floor_camera_bounds.dart) |
| zoom ↔ 미터 산수 | [`zoom_math.dart`](zoom_math.dart) |
| 층 전환 타이밍 정책 | [`floor_switch_progress.dart`](floor_switch_progress.dart) |
| "지도에서 선택" 지점 이름 | [`picked_point.dart`](picked_point.dart) |

파일 이름에 `map_` 접두사를 붙이지 않는다 — 폴더가 이미 말한다.

## 경계

- **정책이 아니라 값과 산수다.** "어느 배율에서 실내로 넘어갈지" 같은 판단은
  `screens/outdoor_map/indoor_entry_zoom.dart`에 있고, 여기 있는 `zoom_math.dart`는
  "이 폭을 담으려면 zoom이 얼마인가"만 답한다.
- **domain·models·theme만 본다.** 화면도 features도 import하지 않는다. 그 방향은
  [계층 검사](../../test/lib_layer_direction_test.dart)가 지킨다.
- 색·라벨·아이콘을 **왜 그 값으로 두었는지**는
  [지도 스타일 규칙](../../../docs/client/map-style-rules.md)이 단일 출처다. 여기 주석에는
  계약과 함정만 둔다.

## 먼저 알아야 할 함정

`setLayerProperties`는 patch가 아니라 **전체 교체**다 — 설정하지 않은 속성이 null로
전송돼 스펙 기본값으로 되돌아가고, `fill-color`의 기본값이 검정이라 도면이 통째로
검게 덮인다. 웹에서는 경로가 달라 증상이 안 보인다. 그래서 최초 등록과 갱신이 **같은
함수**를 쓴다(`screens/outdoor_map/indoor_overlay_layers.dart`).

---

> **다음 읽기:** [`lib/widgets` — 재사용 UI와 지도 렌더링](../widgets/README.md)
