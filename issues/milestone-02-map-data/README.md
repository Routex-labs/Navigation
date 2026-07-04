# Milestone 2 · 실내 지도 데이터와 기본 경로 (Map Data & Routing)

**권장 진행 주차: 2주차**

M1에서 앱과 서버가 서로 통신하는 골격을 만들었다면, M2는 그 통로에
실제 데모에 쓸 **건물 데이터, 평면도 렌더링, 기본 경로 계산**을 얹는 마일스톤이다.

이 단계의 목표는 센서 없이도 "건물 선택 → 층 평면도 표시 → 목적지까지 경로 표시"가 되는
정적 데모를 만드는 것이다. PDR, Particle Filter, 자동 전환은 M3~M4에서 다룬다.

## 목표 (Definition of Done)

- 데모 건물 1개와 1~2개 층의 GeoJSON 데이터가 정해진 스키마로 관리된다.
- Flutter 앱이 FastAPI에서 받은 평면도, POI, 층 정보를 화면에 표시한다.
- 목적지 POI를 선택하면 경로 그래프 위의 기본 최단 경로가 지도에 그려진다.
- 데이터 스키마와 실행 방법이 문서화되어 팀원이 같은 샘플로 테스트할 수 있다.

## 이슈 목록

| ID | 주차 내 위치 | 컴포넌트 | 상태 | GitHub | 제목 |
|---|---|---|---|---|---|
| M2-001 | 2주차 초반 | data / api | Draft | - | [평면도 GeoJSON 스키마와 샘플 데이터 확정](M2-001-floorplan-geojson-schema.md) |
| M2-002 | 2주차 중반 | client / map | Draft | - | [Flutter 실내 평면도 렌더링](M2-002-indoor-map-rendering.md) |
| M2-003 | 2주차 후반 | routing / client | Draft | - | [경로 그래프와 기본 최단 경로 표시](M2-003-route-graph-shortest-path.md) |
| M2-004 | 2주차 후반 | data / routing / demo | Created | #18 | [더현대서울 실내 내비게이션 데이터셋 구축](M2-004-thehyundai-indoor-navigation-dataset.md) |

## 진행 순서

```text
M2-001 (데이터 스키마)
   ├─> M2-002 (평면도 렌더링)
   └─> M2-003 (경로 그래프/최단 경로)
        └─> M2-004 (더현대서울 데모 데이터셋)
```

M2-002와 M2-003은 M2-001의 데이터 구조가 정해진 뒤 병렬로 진행할 수 있다.

## 범위 밖

- 실제 센서 기반 현재 위치 추적
- PDR, heading filter, Particle Filter
- 자연어 목적지 파싱이나 RAG
- 다건물 검색 UI

## 주차 운영 메모

2주차 안에 완벽한 지도 편집기를 만들려고 하면 범위가 커진다.
데모용 건물 1개를 직접 만든 GeoJSON으로 고정하고, 이후 확장 가능하도록 스키마와 렌더링 경계를
분리하는 데 집중한다.
