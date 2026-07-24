# [인수인계] 층 간(다층) 경로 탐색 연동 — 건물 전체 그래프 + 수직 이동 정책

클라이언트 개발자에게 전달하는 요청서. 백엔드의 수직 전이 라우팅 변경
([vertical-transfer-routing.md](vertical-transfer-routing.md))을 앱 경로 탐색에 연동한다.

## 배경

백엔드가 수직 전이(엘리베이터·에스컬레이터) 간선을 방향·층수 비용까지 반영해 새로 서빙한다.
그런데 현재 클라이언트 경로 탐색은 **단일 층 그래프 안에서만** 동작한다
(`http_building_repository.getShortestRoute`가 `buildingId/floor` 캐시로 그 층 그래프만 Dijkstra).
전이 간선은 `floor_id=null`이라 층별 `navigation_graph`에 실리지 않으므로, 지금 구조로는
**층을 넘는 경로가 아예 안 나온다.** 이번 작업은 새 **건물 전체 그래프**를 받아 층 간
경로까지 온디바이스 Dijkstra로 계산·표시하는 연동이다.

## 새 API 계약

`GET /buildings/{building_id}/graph?vertical=auto|elevator|escalator`

- `vertical` (기본 `auto`): 수직 이동 수단 정책.
  - `auto` — 엘리베이터·에스컬레이터 모두(1~2층은 에스컬레이터, 3층+는 엘리베이터가 자연히 최단)
  - `elevator` — 엘리베이터만(접근성/유아차)
  - `escalator` — 에스컬레이터만
  - 잘못된 값은 422.
- 응답 형태:

```json
{
  "building": { "id": "thehyundai-seoul", "name": "더현대 서울" },
  "vertical": "auto",
  "nodes": [
    { "id": "FL-...:ND-...", "type": "elevator", "name": "EV1",
      "x_m": 98.4, "y_m": 117.1, "lat": 37.52, "lng": 126.92,
      "floor_id": "FL-..." }
  ],
  "edges": [
    { "id": "FL-...:E-..", "from": "FL-...:ND-a", "to": "FL-...:ND-b",
      "length_m": 12.3, "bidirectional": true,
      "geometry_local_m": [], "transfer_mode": null },
    { "id": "xfer:es:...__...", "from": "FL-A:ND-x", "to": "FL-B:ND-y",
      "length_m": 20.0, "bidirectional": false,
      "geometry_local_m": [], "transfer_mode": "escalator" },
    { "id": "xfer:el:...__...", "from": "FL-A:ND-x", "to": "FL-C:ND-z",
      "length_m": 40.0, "bidirectional": true,
      "geometry_local_m": [], "transfer_mode": "elevator" }
  ]
}
```

- 층별 그래프와의 차이: **전 층 노드가 한 그래프에 섞임**(노드마다 `floor_id`로 구분),
  층 내부 간선 + **수직 전이 간선** 포함, 간선에 `transfer_mode`
  (`null`=평면 보행, `"elevator"`/`"escalator"`=수직 이동).
- 규모(실데이터 `thehyundai-seoul`): 노드 1931, 간선 2366, 전이 간선 auto 179 / elevator 147 / escalator 32.

## 핵심 주의점

- **에스컬레이터 간선은 단방향**(`bidirectional:false`) — `from→to`만 통행 가능. Dijkstra의
  인접 리스트 구성이 이미 `bidirectional`을 존중하므로(`dijkstra.dart`), 그래프만 통째로
  넣으면 방향은 자동으로 지켜진다. **역방향 간선을 임의로 추가하지 말 것**(불가능 경로가 되살아난다).
- **전이 간선은 `geometry_local_m`이 빈 배열** → 두 노드를 직선으로 잇는다. 두 노드는 같은
  `local_m` 프레임이라 좌표는 유효하지만 **서로 다른 층**이다. 폴리라인을 층별로 그릴 때 전이
  간선 지점에서 끊고, `transfer_mode`로 "엘리베이터/에스컬레이터 이용" 안내를 넣는다.
- `length_m`은 이미 층수 비용이 반영된 값 — 클라이언트에서 재가중하지 말 것.

## 작업 항목(파일별)

- `repositories/http_building_repository.dart`: 건물 전체 그래프를 받는 fetch 추가
  (캐시 키 `buildingId` + `vertical`). `getShortestRoute`가 단일 층 그래프 대신 이 그래프로
  경로를 내도록 변경(층 간 start/end 지원).
- `models/floor_graph.dart`(또는 신규 `building_graph.dart`): 노드 `floor_id`, 간선
  `transfer_mode` 파싱 추가.
- `domain/floor_router.dart`: 경로 폴리라인을 층별로 분할하고 전이 지점을 표기(렌더는 층 단위이므로).
- `domain/dijkstra.dart`: **알고리즘 변경 불필요**(이미 방향·가중치 존중). 회귀 확인만.
- 수직 이동 정책(`auto`/`elevator`/`escalator`)을 노출할 UI(설정/토글)와 요청 파라미터 연결.
  접근성 옵션이면 `elevator`.

## 완성 기준

- [ ] `GET /buildings/{id}/graph?vertical=auto`를 받아 파싱한다(노드 `floor_id`, 간선 `transfer_mode` 포함).
- [ ] 서로 다른 층의 출발·도착 노드로 경로를 요청하면 층 간 경로가 반환된다(단일 층으로만 제한되지 않음).
- [ ] 에스컬레이터 단방향이 지켜진다 — 상행 전용 간선을 하행으로 타는 경로가 생성되지 않는다.
- [ ] 1~2층 이동은 에스컬레이터, 3층+ 이동은 엘리베이터 경로가 선택된다(가까운 기기가 있으면 근접 우선은 정상 동작).
- [ ] `vertical=elevator` 요청 시 경로가 에스컬레이터를 쓰지 않는다(엘리베이터만). `vertical=escalator`도 대칭 동작.
- [ ] 경로 폴리라인이 층별로 올바르게 렌더되고, 전이 지점에서 `transfer_mode`에 따라 "엘리베이터/에스컬레이터 이용" 안내가 표시된다.
- [ ] 잘못된 `vertical` 값(예: `stairs`)은 422로 처리되어 앱이 크래시하지 않는다.
- [ ] 기존 단일 층 경로(같은 층 목적지)도 회귀 없이 동작한다.

## 검증 방법

- 로컬 백엔드 기동 후 `GET /buildings/thehyundai-seoul/graph?vertical=auto`로 응답 확인
  (Swagger: `http://127.0.0.1:8001/docs`).
- 서로 다른 층의 두 매장 `entrance_node_id`로 경로 요청 → 전이 간선을 지나는지, 수단이 층수에 맞는지 확인.
- `vertical`을 바꿔가며 같은 출발/도착의 경로 수단이 바뀌는지 확인.

## 참고

- 설계·비용 모델·검증 기준: [vertical-transfer-routing.md](vertical-transfer-routing.md)
- 백엔드 테스트(기대 동작 예시): `backend/tests/integration/test_building_graph.py`,
  `backend/tests/unit/test_vertical_transfers.py`
