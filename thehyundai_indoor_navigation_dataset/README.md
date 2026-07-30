# 더현대서울 Indoor Navigation Dataset

이 폴더는 더현대서울 실내 내비게이션 데모를 위해 생성한 로컬 데이터셋이다.
VWorld 건물 외곽, 현대백화점 모바일 층 안내도 공개 리소스, 후처리된 topology 기반
navigation graph를 함께 보관한다.

CAD 도면처럼 정밀한 실측 데이터가 아니라, PDR + Particle Filter 데모에서 경로 탐색과
위치 보정을 실험할 수 있는 수준의 topology map이다.

## 핵심 파일

- `navigation_map.json`: 전체 데이터를 직접 담지 않는 split manifest. 앱은 이 파일에서 `files` 경로를 읽어 필요한 JSON만 로드한다.
- `navigation_map_parts/nodes.json`: 길찾기 그래프의 node 목록. 각 node에는 `id`, `type`, `position.local_meters`, `position.source`, `confidence`가 들어간다.
- `navigation_map_parts/edges.json`: node 간 이동 가능한 edge 목록. A* 또는 Dijkstra에서 바로 사용할 수 있도록 `from`, `to`, `length_m`, `bidirectional`, `confidence`를 포함한다.
- `navigation_map_parts/stores.json`: 매장 데이터. `id`, `name`, `centroid`, `entrance`, `polygon` 또는 `bbox`, `confidence`, OCR 매칭 정보가 들어간다.
- `navigation_map_parts/pois.json`: 엘리베이터, 에스컬레이터, 계단, 출입구, 화장실 등 POI 후보.
- `navigation_map_parts/ocr_results.json`: EasyOCR로 읽은 텍스트 원본과 bounding box, confidence.
- `navigation_map_parts/manual_review_candidates.json`: confidence가 낮거나 자동 추출 품질 검수가 필요한 객체.
- `navigation_map_parts/building.json`: 건물 외곽 요약. 이름, 층, source CRS, 투영/WGS84 bbox, 면적·둘레, 외곽 폴리곤을 담는다.
- `navigation_map_parts/floor_regions.json`: 층 내부 구획(section) 폴리곤. 매장 영역의 배경이 되는 구역 정보다.
- `preview.html`: 브라우저에서 지도, 그래프, 매장, OCR, POI overlay를 확인하는 미리보기.

## 좌표계

- `position.source`: Dabeeo 지도 JSON 원본 좌표계.
- `position.local_meters`: 건물 외곽 크기에 맞춰 변환한 실내 로컬 meter 좌표계. 길찾기와 PDR 데모에서는 이 값을 우선 사용한다.
- `position.wgs84`: 가능한 경우 WGS84 위경도 추정값. 실내 데모의 주 좌표계로 쓰기보다는 외부 지도 연동용 보조값으로 본다.
- `navigation_map_parts/coordinate_system.json`: 좌표 변환 기준, scale, source bounds, 건물 bbox 정보를 담는다.
- `navigation_map_parts/image_analysis.json`: 실제 스크린샷 위에 overlay를 맞추기 위한 OpenCV affine 정합 결과를 담는다.

## 앱에서 읽는 방법

매장 검색만 필요하면 다음 파일만 읽으면 된다.

```text
navigation_map_parts/stores.json
```

경로 탐색은 다음 두 파일을 사용한다.

```text
navigation_map_parts/nodes.json
navigation_map_parts/edges.json
```

POI 안내까지 포함하려면 다음 파일을 추가로 읽는다.

```text
navigation_map_parts/pois.json
```

시각화나 디버깅 UI는 `navigation_map.json` manifest를 먼저 읽고, `files`에 적힌 상대 경로를 따라
필요한 part 파일을 lazy load하는 방식이 가장 단순하다.

## 커밋되지 않는 원천/중간 산출물

이 폴더에는 리뷰와 앱 연동에 필요한 **후처리 결과만** 커밋한다. 아래 원천 입력과 중간
산출물은 크기가 크거나 재생성 가능하므로 커밋하지 않는다(제외 범위는 `PR_OVERVIEW.md` 참고).

- VWorld GIS건물통합정보 SHP 원본과 여기서 추출한 더현대서울 건물 외곽(geojson·요약 JSON).
- `floor_assets/` — 현대백화점 모바일 층 안내도 페이지에서 브라우저가 공개적으로 받은 지도
  JSON·이미지·SVG 리소스. 어떤 원천에서 생성됐는지는 `navigation_map.json`의
  `generated_from`이 경로로 기록한다.
- `debug/` 아래 PNG 디버그 overlay(복도·벽·매장·OCR·그래프·정합). 경로 목록은
  `navigation_map_parts/debug.json`에 남지만 PNG 자체는 커밋하지 않는다.
- 위 원천에서 결과 JSON을 만들어 내는 생성 스크립트. 이 폴더는 파이프라인 코드가 아니라
  그 산출물만 보관한다.

`navigation_map_parts/preview.json`은 `preview.html`이 배경 이미지(커밋되지 않는
`floor_assets/...`) 위에 overlay를 맞추기 위한 이미지 크기·bbox 정보를 담는다.

## 주의

- 이 데이터셋은 데모용 자동 추출 결과다. 실제 서비스나 안전-critical 길안내에는 수동 검수와 현장 검증이 필요하다.
- confidence가 낮은 객체는 `navigation_map_parts/manual_review_candidates.json`에서 먼저 확인한다.
- 현대백화점 공개 페이지에서 브라우저가 정상적으로 받은 리소스만 저장한다. 로그인 우회나 비공개 API 접근 결과는 포함하지 않는다.
