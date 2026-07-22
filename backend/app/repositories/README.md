# `app/repositories` — DB 조회 + 응답 dict 조립

Session으로 DB를 읽어 **기존 API 응답과 같은 모양의 순수 dict**를 만든다.
`select()` 조회와 ORM→dict 변환이 여기 모인다. HTTP 상태 코드는 모른다(변환은 라우터가).

> Spring 대응: Repository + 일부 Mapper. 조회부터 응답 dict 조립까지 이 계층에서 끝낸다(별도 service 계층은 두지 않는다 — 서버는 조회·직렬화만 하고, 경로 계산은 클라이언트가 온디바이스로 수행).

---

## 구성 파일

| 파일 | 역할 | 핵심 함수 |
|---|---|---|
| `building_queries.py` | 건물/층/매장/지도/그래프 조회 + dict 조립 | `list_buildings`, `get_building`, `search_stores`, `get_floor_map`, `get_floor_graph` |
| `geo_transform.py` | 건물 `local_m → wgs84` 변환을 요청 시점에 피팅 | `fit_building_geo_transform` |
| `tile_queries.py` | 층 지도를 MVT 바이트로 렌더링 | `render_floor_tile` |
| `__init__.py` | 패키지 표식 | — |

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
