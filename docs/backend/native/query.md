# 자연어 질의 엔드포인트 (`/query`) — 요구사항 정의

`app/routers/query.py`의 스텁 두 개(`POST /query/destination`, `POST /query/info`)를
**실제 동작하는 경량 검색**으로 구현하기 위한 요구사항 문서. 구현 전에 완료 조건·응답 계약·
실패 조건·검증 기준을 먼저 확정한다.

## 1. 해결할 문제

- 기존 문제: 두 엔드포인트가 `{"status":"stub","query":…,"result":null}`만 반환한다. 클라이언트가 자연어("MLB 어디야?", "화장실 몇 층이야?")로 물어도 아무 결과가 없다.
- 완료 조건(Definition of Done):
  - `POST /query/destination`이 질의 텍스트로 **가장 잘 맞는 매장 1건**과 그 **입구 노드**를 반환해, 클라이언트가 바로 온디바이스 경로 계산에 넣을 수 있다.
  - `POST /query/info`가 질의 텍스트로 매장/POI의 **위치 정보(층·카테고리 등)**를 반환한다.
  - 매칭 실패·건물 없음·입구 노드 없음 등 실패 조건이 명시된 상태 코드/응답으로 처리된다.

## 2. 범위

- **이번 범위 — 경량 매칭.** 임베딩·RAG 없이 매장/POI의 **이름·카테고리·동의어**를 텍스트로 매칭한다. 의존성 추가 없음(기존 SQLAlchemy 조회만).
- **범위 밖 — RAG.** `sentence-transformers` + FAISS 의미 검색은 후속. 이 문서의 응답 계약을 유지한 채 매칭 내부만 교체할 수 있게 설계한다.
- **범위 밖 — 경로 계산.** 최단 경로는 서버가 계산하지 않는다. `destination`은 도착 노드(`entrance_node_id`)까지만 주고, Dijkstra는 클라이언트가 수행한다.
- **범위 밖 — RNN 등 밑바닥 시퀀스 학습.** 학습 데이터가 없고 이 문제는 시퀀스 모델링이 아니라 소규모 어휘 검색이다. 경량 매칭으로 부족하면 RNN이 아니라 ② 형태소 정규화(Kiwi 등) → ③ 사전학습 임베딩(RAG) 순으로 올라간다.
- **1차 대상 층 — 지하 2층(B2).** B2에서 실작업을 켜놓고 검증하므로, 구현·수용 테스트를 **B2 매장 데이터 기준으로 먼저** 맞춘다(`resources/studio/thehyundai-seoul-dabeeo/stores_b2.json`). 나머지 층은 같은 로직으로 자연히 커버된다.

## 3. 엔드포인트 동작

### `POST /query/destination`

- 요청: `{ "text": str, "building_id": str, "current_floor_id": str | null }`
  - `current_floor_id`는 선택 사항이다. 값이 있으면 해당 층에서만 매칭해 현재 층의 화장실·엘리베이터·에스컬레이터를 바로 찾는다. 생략하면 기존처럼 건물 전체에서 검색한다.
- 처리: `text`를 정규화 → 건물 내 매장을 매칭 → 최상위 1건 선택 → 입구 노드·층 정보와 함께 반환.
- 응답(성공, 200):
  ```json
  {
    "status": "ok",
    "query": "MLB",
    "match": {
      "store_id": "…",
      "name": "MLB",
      "category": "패션",
      "subcategory": "캐주얼·스트리트",
      "floor_id": "…",
      "floor_name": "B2",
      "entrance_node_id": "…",
      "centroid_local_m": { "x": 0.0, "y": 0.0 },
      "centroid_wgs84": { "lat": 0.0, "lng": 0.0 }
    }
  }
  ```
  - `entrance_node_id`·`floor_name`은 클라이언트 경로 계산·화면 전환에 필요하다.
  - `centroid_wgs84`는 지도 표시용 실좌표(건물에 wgs84 앵커 없으면 null).
  - 필드는 기존 `_to_store_dict` 출력에서 필요한 것만 추린다(재사용).

### `POST /query/info`

- 요청: `{ "text": str, "building_id": str, "current_floor_id": str | null }`
  - `current_floor_id`를 주면 `floors`도 현재 층 하나만 반환한다. 생략하면 대상이 존재하는 모든 층을 반환한다.
- 처리: **매장 단일 풀만** 검색한다(POI 제외). 데이터상 화장실·엘리베이터·에스컬레이터가 모두 매장으로 존재하므로 매장만으로 대상이 커버되고, POI(elevator/escalator 마커)는 추가 정보가 없다. 매칭 규칙은 `destination`과 동일(4절 공유).
- 응답(성공, 200): 설명 정보 중심 — `name`, `category`, `subcategory`, `floor_name`, 좌표. 경로용 `entrance_node_id`는 선택(강조하지 않음).
- **여러 층에 같은 대상이 있으면 층 목록을 준다.** "화장실 몇 층이야?"의 답은 단건 좌표가 아니라 존재하는 층들이다. 대표 1건 + `floors: [floor_name, …]`(있는 층 목록)을 함께 반환한다.
  ```json
  {
    "status": "ok",
    "query": "화장실",
    "match": { "name": "화장실", "category": "…", "floor_name": "B2", "centroid_local_m": { "x": 0.0, "y": 0.0 } },
    "floors": ["B2", "B1", "1F", "2F"]
  }
  ```

> POI를 query에서 쓰지 않기로 하면서 "매장·POI 우선순위" 결정은 불필요해졌다. 시설 검색을 POI 기준으로 정교화하는 것은 후속 과제로 남긴다.

## 4. 경량 매칭 규칙

우선순위가 높은 것부터 적용하고, 맞는 게 없으면 다음으로 내려간다.

1. **정확 일치** — 정규화된 `text`가 매장 `name`과 동일(예: "MLB").
2. **카테고리/서브카테고리 일치** — `text`가 `category`/`subcategory`와 동일(예: "편의시설"). 단 B2는 리테일 매장 대부분이 `category="매장"`이라 카테고리 매칭이 약하다 — 이름/동의어 매칭이 주력.
3. **동의어 매핑** — 사전으로 `text`를 표준어로 변환(예: "엠엘비"→"MLB", "화장실"/"토일렛"→"화장실"). **사전은 `resources/`의 JSON 파일로 둔다**(코드 상수 아님). `store_category_by_name.json`(494개)과 같은 선례를 따라, 개발자 아닌 데이터 담당도 코드 수정·재배포 없이 항목을 추가하고 재시드/재시작만으로 반영한다.
4. **부분 일치** — 기존 `search_stores`의 `name LIKE %text%`.

- 정규화: 앞뒤 공백 제거, 소문자화, 조사/의문형 꼬리("어디야","몇 층") 제거는 최소한으로.
- 여러 건이 걸리면 **우선순위 → 그다음 동일 우선순위 내에서는 결정적 정렬**(예: `floor_name`, `store_id` 순)으로 1건을 고른다. 무작위 금지(테스트 재현성).

## 5. 실패 조건 (정상 동작보다 먼저 정의)

| 상황 | 처리 |
|---|---|
| `building_id`가 없는 건물 | `404` (기존 `search_stores`가 `None` 반환하는 계약과 동일하게 라우터가 번역) |
| 매칭 결과 0건 | `200` + `{"status":"no_match","query":…,"match":null}` (에러 아님 — "못 찾음"은 정상 응답) |
| 매칭됐으나 `entrance_node_id`가 `null` | `destination`은 `match`를 주되 `entrance_node_id: null`을 그대로 노출하고 `status:"ok_no_route"`로 구분. 클라이언트가 경로 불가를 인지하게 한다. |
| `text`가 빈 문자열/공백 | `422`(요청 검증) 또는 `no_match` 중 하나로 **일관되게**. 결정: 빈 문자열은 `422`. |
| 여러 건 동점 | 4절의 결정적 정렬로 1건 확정(비결정성 금지). |

## 6. 재사용 지점 (기존 코드)

- `app/repositories/building_queries.py`
  - `search_stores(session, building_id, query)` — 이름 부분 일치. 매칭 4단계의 마지막 단계로 재사용/확장.
  - `_to_store_dict(store, transform)` — 응답 매장 필드 조립. `destination` 응답은 이 출력의 부분집합.
  - `fit_building_geo_transform` — 좌표 wgs84 변환(필요 시).
- `app/models/place.py` — `Store`(`name`,`category`,`subcategory`,`entrance_node_id`,`centroid_*`), `Poi`(`type`,`name`,`linked_node_id`).
- `floor_name`은 `Store.floor_id`로 `Floor`를 조인해 얻는다. **보강은 query 계층에서 국소적으로 한다** — 공유 함수 `_to_store_dict`에 필드를 추가하면 `search_stores`·`get_floor_map` 등 기존 소비자의 응답 스키마(`response_model`)까지 바뀌어 기존 API·테스트에 파급된다. query 응답 조립 시 `Floor.name`만 따로 조회해 붙인다.

## 7. 검증 기준 (수용 기준)

구현이 아래를 모두 만족하면 완료로 본다. 테스트는 기존 `backend/tests`의 Given/When/Then·fixture 관례를 따른다. **(전 항목 완료 — 백엔드 66개 테스트 통과, B2 실데이터로 라이브 확인)**

- [x] 매장명 질의("MLB")가 그 매장 1건 + `entrance_node_id`를 반환한다. — 통합 테스트 + 라이브(MLB@B2)
- [x] 카테고리 질의("편의시설")가 해당 카테고리 매장 1건을 반환한다. — 단위 `test_카테고리로_매칭한다`
- [x] 동의어 질의("엠엘비"→"MLB")가 대응 매장을 반환한다. — 단위 + 동의어 커버리지 테스트
- [x] info 질의("화장실")가 대표 1건 + 있는 층 목록(`floors`)을 반환한다. — 통합 + 라이브(11개 층 목록)
- [x] 매칭 없는 질의가 `200` + `status:"no_match"`(예외 아님)를 반환한다. — 통합 테스트
- [x] 없는 `building_id`가 `404`를 반환한다. — 통합 테스트
- [x] 동점 입력이 **항상 같은 결과**를 반환한다(결정적). — 단위 `test_동점은_level_id_순으로_결정적이다`
- [x] `entrance_node_id`가 없는 매장이 매칭될 때 `ok_no_route`로 구분된다. — 단위 `test_입구노드_없으면_ok_no_route`
- [x] 응답 스키마가 Pydantic 모델(`response_model`)로 고정된다. — `dto/query.py` + 라우터 `response_model=`
- [x] `backend/tests` 단위/통합 테스트 통과. — 66개 통과

> 참고: 백엔드 완료. **클라이언트 연동(목업→실 HTTP, 새 계약 파싱, 지도 표시)** 은 별도 클라이언트 작업이다.

## 8. 확정된 결정

- **동의어 사전 위치** → `resources/`의 JSON 파일. (`store_category_by_name.json` 선례. 데이터 담당이 코드 없이 항목 추가.)
- **info의 매장·POI 우선순위** → info는 **매장 단일 풀만** 검색(POI 미사용). 결정 자체가 불필요해짐. 시설 POI 정교화는 후속.
- **`floor_name` 보강 위치** → **query 계층에서 국소 조회**. 공유 함수 `_to_store_dict`는 건드리지 않아 기존 API 계약 불변.
- **1차 대상 층** → 지하 2층(B2) 데이터로 먼저 구현·검증.

## 9. 향후 확장 (지금 구현 안 함)

지금은 매장·편의시설이 한 테이블(`stores`)에 섞여 있고 필드가 같아 태그로 충분하다. 아래는 갈라질 때를 대비한 **이음새만** 남기고, 실제 구현은 필요 시점으로 미룬다.

- **`kind` 구분자 도입** — 리테일 vs 편의시설을 `category` 문자열("매장"/"편의시설")에 의존하지 말고 전용 값(예: `retail`/`amenity`)으로 구분. query가 "화장실"을 이름 매칭이 아니라 종류로 정확히 거를 수 있게 된다. 이 문서의 매칭 규칙(4절)은 그대로 두고, 도입 시 필터만 얹는다.
- **타입별 필드 확장은 단일 테이블 유지(STI)** — 매장(브랜드·영업시간)과 편의시설(성별 구분·운영 여부)이 서로 다른 필드를 갖게 되면, 테이블을 쪼개지 말고 nullable 컬럼 또는 `attributes` JSON으로 한 테이블 안에서 분기한다. 둘 다 경로 탐색을 `entrance_node_id`로 공유하는 한 물리 분리 이득이 없다.
- **elevator/escalator 이중 표현 정리** — 현재 엘리베이터·에스컬레이터가 `Store`(이름)와 `Poi`(노드 승격) 양쪽에 존재한다. 단일 출처(예: 검색=Store, 지도 마커=Poi)를 정해 드리프트를 막는다.
- **시설 검색을 POI 기준으로 정교화** — info가 POI를 활용하는 것은 후속(현재는 매장 단일 풀).
- **의미 검색(RAG)** — 동의어 사전으로 못 잡는 표현이 문제되면 사전학습 임베딩으로. 응답 계약(3절)은 유지하고 매칭 내부만 교체.

> 실제 테이블 분리(Joined Table Inheritance)는 타입별 필드가 많아지고 쿼리가 완전히 갈라질 때만 검토한다. 지금 예상 필드(2~3개)로는 과하다.
