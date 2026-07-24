# `app/repositories` — DB 조회 + 응답 dict 조립

Session으로 DB를 읽어 **기존 API 응답과 같은 모양의 순수 dict**를 만든다.
`select()` 조회와 ORM→dict 변환이 여기 모인다. HTTP 상태 코드는 모른다(변환은 라우터가).

> Spring 대응: Repository + 일부 Mapper. 조회부터 응답 dict 조립까지 이 계층에서 끝낸다(별도 service 계층은 두지 않는다 — 서버는 조회·직렬화만 하고, 경로 계산은 클라이언트가 온디바이스로 수행).

---

## 구성 파일

| 파일 | 역할 | 핵심 함수 |
|---|---|---|
| `building_queries.py` | 건물/층/매장/지도/그래프 조회 + dict 조립 | `list_buildings`, `get_building`, `search_stores`, `get_floor_map`, `get_floor_graph`, `get_building_graph` |
| `query_search.py` | 자연어 질의 경량 매칭(이름·카테고리·동의어) | `match_destination`, `match_info`, `match_ai_destination` |
| `query_morph.py` | 질의 형태소 정규화(Kiwi). 조사·어미 제거 | `normalize` |
| `query_semantic.py` | 임베딩 의미 검색(FAISS). 경량 미스·모호한 부분 일치 보완 | `semantic_search`, `reset_indexes`, `warm_model_in_background` |
| `geo_transform.py` | 건물 `local_m → wgs84` 변환을 요청 시점에 피팅 | `fit_building_geo_transform` |
| `tile_queries.py` | 층 지도를 MVT 바이트로 렌더링 | `render_floor_tile` |
| `__init__.py` | 패키지 표식 | — |

---

## 모듈 연관관계

### 건물·지도 조회 경로

건물 JSON과 MVT 타일은 서로 다른 출력이지만 같은 층 조회와 좌표 변환을 공유한다.

```mermaid
flowchart LR
    ROUTER["routers/buildings.py"]
    BUILDING["building_queries.py<br/>JSON 지도 · 그래프"]
    TILE["tile_queries.py<br/>MVT bytes"]
    TRANSFORM["geo_transform.py<br/>local_m → WGS84"]
    MODEL["models · SQLite"]
    GEO["geo/<br/>변환 · 타일 수학"]

    ROUTER --> BUILDING
    ROUTER --> TILE
    TILE -->|"층 찾기"| BUILDING
    BUILDING --> MODEL
    TILE --> MODEL
    BUILDING --> TRANSFORM
    TILE --> TRANSFORM
    BUILDING --> GEO
    TILE --> GEO
```

### 자연어 검색 경로

경량 검색이 기본이며, 결과가 없거나 모호한 경우에만 의미 검색을 호출한다.

```mermaid
flowchart LR
    ROUTER["routers/query.py"]
    SEARCH["query_search.py<br/>경량 매칭 · 응답 조립"]
    MORPH["query_morph.py<br/>Kiwi 정규화"]
    SEMANTIC["query_semantic.py<br/>FAISS 의미 검색"]
    TRANSFORM["geo_transform.py<br/>결과 좌표 변환"]
    MODEL["Store · Floor"]

    ROUTER --> SEARCH
    SEARCH --> MORPH
    SEARCH -. "경량 미스 · 모호한 tier 2" .-> SEMANTIC
    SEMANTIC -. "매장 재조회" .-> SEARCH
    SEARCH --> MODEL
    SEARCH --> TRANSFORM
```

두 개의 공유 지점이 이 계층의 핵심이다.

- **`geo_transform`을 건물 JSON·타일·질의 결과가 공유한다.** 세 출력이 같은 좌표를
  가리키려면 반드시 이 함수 하나를 통해야 한다. 여기가 어긋나면 "지도에선 맞는데
  타일에선 어긋나는" 증상이 난다.
- **`query_semantic`·`query_morph`가 `query_search`를 되부른다.** 순환처럼 보이지만 각각 `_load_stores`(매장 로딩)·`_synonyms`(동의어 사전)만 빌려 쓰는 단방향 재사용이다. `query_morph` 쪽은 함수 안에서 지연 import해 모듈 로드 시점의 순환을 피한다.

---

## `building_queries.py` 내부

### 건물·매장 조회

```mermaid
flowchart LR
    LIST["list_buildings()"]
    GET["get_building()"]
    SUMMARY["_to_building_summary()"]
    DEFAULT["_default_floor()"]

    SEARCH["search_stores()"]
    TRANSFORM["fit_building_geo_transform()"]
    STORE["_to_store_dict()"]

    LIST --> SUMMARY
    GET --> SUMMARY --> DEFAULT
    SEARCH --> TRANSFORM
    SEARCH --> STORE
    TRANSFORM --> STORE
```

### 층 지도 응답 조립

```mermaid
flowchart LR
    MAP["get_floor_map()"]
    FIND["_find_floor()"]
    TRANSFORM["fit_building_geo_transform()"]
    FOOTPRINT["_floor_footprint()<br/>_footprint_wgs84()"]
    GRAPH["_to_floor_graph_dict()"]
    STORE["_to_store_dict()"]
    POI["_to_poi_dict()"]
    RESPONSE["FloorMap dict"]

    MAP --> FIND
    MAP --> TRANSFORM
    FIND --> FOOTPRINT --> RESPONSE
    FIND --> GRAPH --> RESPONSE
    FIND --> STORE --> RESPONSE
    FIND --> POI --> RESPONSE
    TRANSFORM --> FOOTPRINT
    TRANSFORM --> STORE
    TRANSFORM --> POI
```

### 층별·건물 전체 그래프

```mermaid
flowchart LR
    FLOOR["get_floor_graph()"]
    BUILDING["get_building_graph()"]
    FIND["_find_floor()"]
    FLOOR_DICT["_to_floor_graph_dict()"]
    NODE["_to_node_dict()<br/>_to_graph_node_dict()"]
    EDGE["_to_edge_dict()"]
    POLICY["_vertical_allows()"]

    FLOOR --> FIND --> FLOOR_DICT
    FLOOR_DICT --> NODE
    FLOOR_DICT --> EDGE

    BUILDING --> NODE
    BUILDING --> POLICY --> EDGE
```

- `_to_floor_graph_dict()`를 **층 지도와 그래프 API가 공유한다.** 클라이언트가 층 지도 응답 한 번으로 그래프까지 캐시할 수 있는 이유다.
- `_floor_footprint()`는 층 외곽선이 없을 때만 건물 것으로 폴백한다 — 지하층에 1F 윤곽이 그려지던 문제의 대응.

---

## `query_search.py` 내부

### 공개 질의 함수

```mermaid
flowchart LR
    DEST["match_destination()"]
    INFO["match_info()"]
    LOAD["_load_stores()"]
    RANK["_rank()"]
    MATCH["_to_match()"]
    STATUS["_status()"]
    FLOORS["_floor_names_for_match()"]
    TRANSFORM["fit_building_geo_transform()"]
    DEST_RESPONSE["DestinationResponse dict"]
    INFO_RESPONSE["InfoResponse dict"]

    DEST --> LOAD
    INFO --> LOAD
    LOAD --> RANK
    RANK --> MATCH
    RANK --> FLOORS
    DEST --> TRANSFORM
    INFO --> TRANSFORM
    TRANSFORM --> MATCH

    DEST --> STATUS --> DEST_RESPONSE
    MATCH --> DEST_RESPONSE

    FLOORS --> INFO_RESPONSE
    MATCH --> INFO_RESPONSE
```

### AI 하이브리드 분기

```mermaid
flowchart TD
    AI["match_ai_destination()"]
    LOAD["_load_stores()"]
    LIGHT["_rank_with_candidate()"]
    CONF{"경량 결과가<br/>충분히 확실한가?"}
    SEMANTIC["query_semantic<br/>semantic_search()"]
    MATCH["_to_match()"]
    NONE["no_match"]

    AI --> LOAD --> LIGHT --> CONF
    CONF -->|"예"| MATCH
    CONF -->|"아니오"| SEMANTIC
    SEMANTIC -->|"검색 성공"| MATCH
    SEMANTIC -->|"실패 · 모델 없음"| NONE
```

### 후보 정규화와 순위 계산

```mermaid
flowchart LR
    TEXT["원문 query"]
    CANDIDATE["_query_candidates()"]
    VARIANT["_norm() · 끝 구두점 후보"]
    TAIL["_strip_tail()"]
    MORPH["query_morph.normalize()"]
    NORMALIZED["정규화 후보 목록"]
    SYN["_synonyms()"]
    TIER["_tier()"]
    RANK["_rank_with_candidate()"]

    TEXT --> CANDIDATE
    CANDIDATE --> VARIANT --> TAIL --> MORPH --> NORMALIZED
    SYN --> TIER
    NORMALIZED --> TIER --> RANK
```

- **`_load_stores()`가 이 계층의 허브다.** 세 공개 함수와 의미 검색이 전부 이걸 통해 매장을 읽으므로, 여기 걸린 층 필터가 모든 경로에 동시에 적용된다.
- **AI 하이브리드 그림의 분기는 조건부**다. 정확 이름·카테고리 또는 단일 매장명 부분
  일치는 경량 경로에서 끝난다.
  최상위 `(tier, 구두점 후보 순서)`에 서로 다른 매장명이 여럿이면 ID순 후보를 임의 확정하지 않고
  의미 검색으로 넘긴다. 일반 검색용 `_rank()`는 같은 내부 순위를 쓰되 후보 순서 필드만 감춘다.
- **`_query_candidates()`는 원문을 보존하면서 끝 구두점을 단계적으로 제거한다.**
  각 후보는 `_strip_tail()`(의문형 꼬리) → `query_morph.normalize()`(조사·어미) 순으로
  정규화한다. `"A.P.C."`는 원문 정확 일치를 유지하고 `"화장실이 어디야?"`도 잡는다.
  Kiwi가 없으면 꼬리 제거 결과를 쓴다.

---

## `query_semantic.py` 내부

```mermaid
flowchart TD
    semSearch["semantic_search()"] --> getModel["_get_model()"] & getIdx["_get_index()"] & encode["_encode()"]
    getIdx --> buildIdx["_build_index()"]
    buildIdx --> getModel & docText["_document_text()"] & encode
    buildIdx -.-> loadS["query_search<br/>_load_stores()"]
    semSearch -.-> loadS
    resetI["reset_indexes()"] -. "캐시 비움" .-> getIdx

    classDef pub fill:#2a9d8f,color:#fff,stroke:none
    classDef priv fill:#e9ecef,color:#212529,stroke:#adb5bd
    classDef ext fill:#e9c46a,color:#212529,stroke:none
    class semSearch,resetI pub
    class getIdx,buildIdx,getModel,encode,docText priv
    class loadS ext
```

- **`_get_model()`과 `_get_index()`는 둘 다 지연 로드 싱글턴**이다. 락 안에서 한 번 더 확인해 동시 요청이 모델·인덱스를 중복 생성하지 않게 한다.
- **모델 로드는 로컬 캐시 우선(`_load_model`)이다.** `local_files_only=True`로 먼저 시도해 HF Hub 왕복(경고·지연)을 없애고, 캐시가 없을 때만 Hub로 폴백한다. 배포 이미지는 빌드 때 `scripts.warm_embedding_model`로 캐시를 채운다.
- **`warm_model_in_background()`는 기동 시 워밍용이다.** `NAV_WARM_EMBEDDING=1`이면 `main.create_app()`이 이 데몬 스레드를 띄워 `_get_model()`을 미리 돌린다. `_model_lock`이 직렬화하므로 워밍 중 첫 질의가 들어와도 중복 로드 없이 같은 인스턴스를 쓴다.
- **인덱스는 `store_id`만 캐시한다.** ORM 객체는 매 요청 현재 세션으로 새로 읽는다(`semantic_search → _load_stores`) — detached 객체와 stale 층 정보를 피하기 위해서다.
- 모델 로드가 실패하면 `_get_model()`이 `None`을 돌려주고 AI 경로만 조용히 비활성된다. 경량 매칭은 계속 동작한다. 백그라운드 워밍이 실패해도 같은 방식으로 degrade한다.

---

## `tile_queries.py` · `geo_transform.py` 내부

### MVT 타일 렌더

```mermaid
flowchart LR
    RENDER["render_floor_tile()"]
    FIND["_find_floor()"]
    QUERY["Building · Store · Poi 조회"]
    BOUNDS["geo.tiling<br/>tile_bounds()"]
    TRANSFORM["fit_building_geo_transform()"]
    LAYERS["build_floor_tile_layers()"]
    ENCODE["mapbox_vector_tile.encode()"]
    BYTES["MVT bytes"]

    RENDER --> FIND
    RENDER --> QUERY
    RENDER --> BOUNDS
    RENDER --> TRANSFORM
    FIND --> LAYERS
    QUERY --> LAYERS
    BOUNDS --> LAYERS
    TRANSFORM --> LAYERS --> ENCODE --> BYTES
```

### 좌표 변환 피팅

```mermaid
flowchart TD
    FIT["fit_building_geo_transform()"]
    NODES["건물 전 층 Node<br/>x_m · y_m · lat · lng"]
    COUNT{"실측 대응점이<br/>3개 이상인가?"}
    REAL["실측 PointPair"]
    SYNTH["_synthetic_geo_pairs()<br/>서울시청 기준 가상 3점"]
    AFFINE["geo.georeference<br/>fit_wgs84_transform()"]

    FIT --> NODES --> COUNT
    COUNT -->|"예"| REAL --> AFFINE
    COUNT -->|"아니오"| SYNTH --> AFFINE
```

- 수학(`geo/`)과 조회(`repositories/`)를 나눈 경계가 여기서 보인다. 타일 **바이트 인코딩**만 외부 포맷 라이브러리에 의존하므로 `geo`가 아니라 이쪽에 있다.
- 좌표 변환 그림의 `아니오` 경로는 실측 앵커가 없는 합성 데이터용이다. 위치는 가짜지만
  형태·크기는 정확한 지도가 나온다.

---

## 반환 규칙 (라우터와의 계약)

| 반환 | 뜻 | 라우터 처리 |
|---|---|---|
| dict / list | 정상 결과 | 200 |
| `None` | 없는 Building/Floor | 404 |
| 빈 `[]` | 검색 결과 없음(대상은 존재) | 200 + 빈 목록 |

- 모든 조회 함수는 **첫 인자가 `Session`**이고, 상태 코드를 던지지 않는다.
- ORM 객체를 그대로 반환하지 않고 `_to_store_dict` 등으로 **명시적으로 dict를 조립**한다(내부 `from_node_id`→`from` 키 변경, `centroid_wgs84` 계산 등). 최종 검증·직렬화는 라우터의 `response_model`(=`dto/`)이 한다.

## `geo_transform.py` — 변환 피팅

```python
def fit_building_geo_transform(session, building_id) -> GeoTransform
```

- 건물의 모든 층 Node 중 **실측 wgs84가 채워진 것**을 대응점으로 뽑아 `geo.georeference.fit_wgs84_transform`으로 피팅한다.
- 대응점이 3개 미만이면(합성 데이터 등) 서울시청 앵커에 1m=1m로 배치하는 **합성 대응점**으로 대체한다 — 위치는 가짜지만 형태/크기는 정확한 지도를 보여주기 위함.
- **DB 컬럼으로 저장하지 않고 매 요청 즉석 피팅한다.** 타일(`tile_queries`)과 JSON 지도(`building_queries`)가 이 함수를 공유해야 두 경로가 같은 좌표를 가리킨다.

## `tile_queries.py` — MVT 렌더

- `geo.tiling.build_floor_tile_layers`로 GeoJSON 레이어를 만든 뒤 **`mapbox_vector_tile.encode`로 바이트 인코딩**한다(외부 포맷 라이브러리 의존이라 geo가 아닌 여기서).

---

## 의존성 방향

```
repositories/*  ──►  models (select), geo (변환·타일 수학), sqlalchemy
tile_queries    ──►  building_queries._find_floor, geo_transform, mapbox_vector_tile

routers/*   ──►  repositories (단순 조회)
```

- repositories는 `models`와 `geo`에 의존하지만 `dto`·`routers`에는 의존하지 않는다(계약은 라우터가 dto로 강제).

---

## 자주 하는 작업

| 하고 싶은 것 | 방법 |
|---|---|
| 새 조회 API 추가 | 조회 함수(`Session` 첫 인자) 작성 → dto 추가 → 라우터에서 연결 |
| 응답 dict 필드 바꾸기 | `_to_*_dict` 헬퍼 수정 + 대응 `dto/` 수정 |
| 좌표가 지도/타일에서 다르게 보임 | 둘 다 `fit_building_geo_transform`을 쓰는지 확인 |

---

> **다음 읽기:** [`app/routers` — HTTP 엔드포인트](../routers/README.md)
