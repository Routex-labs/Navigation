# 더현대서울 실내 내비게이션 데이터셋 PR 개요

이 문서는 현재 PR에서 올리는 더현대서울 실내 내비게이션 데이터셋의 목적, 포함 범위, 제외 범위,
활용 방법을 설명한다.

## 목적

이 PR은 더현대서울 실내 내비게이션 데모에서 사용할 지도 데이터셋과 생성 파이프라인을 추가한다.
목표는 CAD 수준의 정밀 도면이 아니라, PDR + Particle Filter와 기본 경로 탐색이 사용할 수 있는
topology 기반 indoor map을 만드는 것이다.

## 포함되는 것

- VWorld SHP에서 더현대서울 건물 외곽 polygon을 추출하는 스크립트
- 현대백화점 모바일 층 안내도 공개 리소스를 수집하는 스크립트
- 수집된 층 안내도와 지도 JSON을 후처리해 navigation graph를 생성하는 스크립트
- 협업자가 바로 확인할 수 있는 후처리 결과 JSON
- 브라우저에서 바로 열 수 있는 `preview.html`
- 데이터셋 파일별 의미와 활용 방법을 설명하는 `README.md`

## 커밋되는 산출물

```text
thehyundai_indoor_navigation_dataset/
|-- README.md
|-- PR_OVERVIEW.md
|-- navigation_map.json
|-- preview.html
`-- navigation_map_parts/
    |-- building.json
    |-- coordinate_system.json
    |-- debug.json
    |-- edges.json
    |-- floor_regions.json
    |-- image_analysis.json
    |-- manual_review_candidates.json
    |-- nodes.json
    |-- notes.json
    |-- ocr_results.json
    |-- pois.json
    |-- preview.json
    `-- stores.json
```

## 커밋하지 않는 것

- `floor_assets/json/map-c68dcdcf8ff9.json`
- `floor_assets/` 아래 원본 이미지, JSON, SVG, JS, CSS 리소스
- `debug/` 아래 PNG 디버그 이미지
- VWorld SHP 원본 파일

위 파일들은 원천 입력 또는 중간 산출물이고, 크기가 크거나 재생성 가능하다. PR에는 리뷰와 앱 연동에
필요한 후처리 결과만 포함한다.

## 앱에서 쓰는 파일

매장 검색만 필요하면 `navigation_map_parts/stores.json`을 읽는다.

경로 탐색은 다음 두 파일을 읽는다.

```text
navigation_map_parts/nodes.json
navigation_map_parts/edges.json
```

엘리베이터, 에스컬레이터, 출입구 같은 시설 안내까지 필요하면 다음 파일을 추가로 읽는다.

```text
navigation_map_parts/pois.json
```

전체 파일 위치는 `navigation_map.json`의 `files` 필드를 기준으로 찾는다.

## 좌표계

- `source`: Dabeeo 원본 지도 좌표계
- `local_meters`: 건물 외곽 크기에 맞춘 실내 로컬 meter 좌표계
- `wgs84`: 가능한 경우 외부 지도 연동용 위경도 추정값

PDR, Particle Filter, A*/Dijkstra 경로 탐색에는 `local_meters`를 우선 사용한다.

## 신뢰도와 한계

자동 추출 결과이므로 각 객체에는 `confidence`가 포함된다. 낮은 confidence 객체는
`navigation_map_parts/manual_review_candidates.json`에서 확인한다.

이 데이터셋은 데모와 알고리즘 검증용이다. 실제 서비스 품질로 사용하려면 현장 검수, 매장 경계 보정,
POI 위치 확인, 층간 이동 정보 보강이 필요하다.

## 연결 이슈

- M2-004 · 더현대서울 실내 내비게이션 데이터셋 구축: #18
