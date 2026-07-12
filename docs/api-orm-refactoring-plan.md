# FastAPI + SQLAlchemy 리팩터링 진행표

## 목적

현재의 `sqlite3` 직접 SQL/DDL 구조를 SQLAlchemy ORM 중심 구조로 전환한다.
Pydantic은 HTTP 요청·응답 검증에만 사용하고, ORM 엔티티와 역할을 분리한다.

이 문서는 구현 순서와 각 단계의 결정 사항을 기록한다. **각 단계의 질문에 합의한 뒤 다음 단계로 진행한다.**

## 현재 구조 요약

- DB: SQLite + `sqlite3`
- 스키마 생성: `api/scripts/load_dataset.py`의 `DROP TABLE` / `CREATE TABLE`
- 데이터 적재: JSON 지도 데이터 → SQLite
- 도메인: 불변 `dataclass`
- HTTP 검증: 일부 응답에만 Pydantic `BaseModel`
- DB 접근: `SqliteBuildingRepository`의 직접 SQL과 row 수동 매핑

## 목표 구조

```text
api/app/
├── main.py
├── core/
│   ├── config.py          # 환경변수 기반 설정
│   └── database.py        # SQLAlchemy Engine, Session, get_db
├── models/                # SQLAlchemy ORM 엔티티
├── schemas/               # Pydantic 요청/응답 DTO
├── routers/               # HTTP 경로와 상태 코드 변환
├── queries/               # 단순 조회와 ORM load 전략
├── services/              # 경로 탐색 등 비즈니스 규칙
└── scripts/
    └── seed_navigation.py # 초기 지도 데이터 적재
```

## 원칙

1. `Pydantic BaseModel`은 테이블 모델이 아니다. 요청·응답 계약에만 쓴다.
2. ORM 엔티티는 `models/`에 두고 SQLAlchemy `DeclarativeBase`를 상속한다.
3. 단순 조회는 `queries/`의 Session 기반 함수로 처리한다.
4. 여러 엔티티를 조합하거나 경로 탐색 규칙이 있을 때만 Service를 만든다.
5. 이번 범위에서는 Repository를 만들지 않는다. 향후 복잡한 쿼리 재사용이 실제로 생길 때만
   별도 도입을 검토한다.
6. `Session`은 요청마다 생성·종료하며 캐시하지 않는다.
7. 설정과 Engine은 프로세스 단위로 재사용한다.
8. 현재 개발 단계에서는 스키마와 시드 데이터를 매번 초기화한다. 안정화·운영 배포가 필요해질 때 Alembic migration으로 전환한다.

## 구현 전 공통 체크리스트

이 절차는 설계 문서가 아니라 실제 파일을 변경할 때 따르는 체크리스트다. 각 번호를
완료·검증하기 전에는 다음 번호로 넘어가지 않는다.

### 공통 안전 규칙

1. 파일을 수정하기 직전에 현재 파일 내용을 다시 읽는다. 이 문서의 코드 초안보다 실제
   구현이 우선이다.
2. URL, HTTP 상태 코드, 응답 JSON 키는 바꾸지 않는다. 특히 `from`, `to`, `path_points`,
   `centroid_local_m` 등의 기존 Flutter 계약을 보존한다.
3. 한 단계에서 새 구조와 기존 구조를 동시에 활성화하지 않는다. 새 Query/Service로
   옮긴 API만 새 `get_db()`를 사용한다.
4. 삭제는 대체 코드의 테스트가 통과하고, `rg`로 기존 모듈 import가 없음을 확인한 후에만 한다.
5. 개발 DB 초기화는 명시적인 CLI에서만 한다. FastAPI 서버 startup 이벤트에는
   `drop_all()` 또는 `create_all()`을 넣지 않는다.

### 기준선 확인

대상: `api/requirements.txt`, `api/app/FastAPIConfig.py`, `api/app/main.py`,
`api/app/router/`, `api/app/service/buildingService.py`, `api/app/repository/`,
`api/scripts/load_dataset.py`, `api/tests/`

작업:

- 현재 테스트 전체를 실행해 통과 기준선을 기록한다.
- 현재 API 통합 테스트에서 URL·상태 코드·응답 JSON 키를 확인한다.
- `git status --short`로 사용자 작업과 이번 리팩터링 파일을 구분한다.

완료 조건:

- 리팩터링 전 테스트 결과가 기록되어 있다.
- 호환해야 할 API 목록이 7단계의 API별 책임 확정표와 일치한다.

### 의존성 추가

대상: `api/requirements.txt`

작업:

- `sqlalchemy>=2.0` 추가
- `pydantic-settings>=2.0` 추가
- 이 단계에서는 기존 `sqlite3` 코드, Router, 테스트를 바꾸지 않는다.

검증:

```text
python -c "import sqlalchemy, pydantic_settings; print(sqlalchemy.__version__)"
```

완료 조건:

- 새 패키지를 import할 수 있다.
- 기존 테스트가 여전히 통과한다.

### Core 기반 추가

새 파일:

```text
api/app/core/__init__.py
api/app/core/config.py
api/app/core/database.py
```

작업:

- `config.py`: `DATABASE_URL`의 기본값을 현재 DB 파일인
  `sqlite:///.../api/data/navigation.db`로 둔다.
- `database.py`: `engine`, `SessionLocal`, `get_db()`를 정의한다.
- `get_db()`는 요청 단위 Session을 만들고, 예외 시 rollback, 종료 시 close한다.
- 이 시점에는 기존 `FastAPIConfig.get_db()`를 교체하지 않는다. 이름이 같아도 서로 다른
  구조가 병렬로 존재한다는 점을 명확히 한다.

검증:

- 임시 Python 실행에서 Engine과 Session을 생성·종료할 수 있다.
- 기존 서버와 기존 테스트가 변함없이 동작한다.

완료 조건:

- 새 Core 모듈은 존재하지만 아직 Router가 의존하지 않는다.

### ORM 모델 추가

새 파일:

```text
api/app/models/__init__.py
api/app/models/base.py
api/app/models/building.py
api/app/models/navigation.py
api/app/models/place.py
```

작업:

- 4단계의 전체 ORM 모델 초안을 실제 파일로 옮긴다.
- 현재 DDL의 8개 테이블, PK, FK, nullable, unique, index를 모두 반영한다.
- `models/__init__.py`가 모든 모델을 import하게 해 `Base.metadata` 등록을 보장한다.
- 아직 기존 dataclass(`app/domain/building.py`)와 Repository는 삭제하지 않는다.

검증:

- 새 임시 SQLite 파일에 `Base.metadata.create_all()`을 실행한다.
- 생성된 테이블 이름과 주요 index/FK가 기존 DDL과 일치하는지 확인한다.
- 실제 `api/data/navigation.db`는 이 단계에서 건드리지 않는다.

완료 조건:

- ORM 모델 import 및 빈 DB 테이블 생성이 성공한다.

### 개발 DB 초기화와 시드 전환

새 파일:

```text
api/scripts/reset_database.py
api/scripts/seed_navigation.py
api/scripts/reset_and_seed.py
```

작업:

- 5단계의 코드 초안을 실제 파일로 옮긴다.
- 기존 `load_dataset.py`의 JSON 파싱·보정 로직을 재사용 또는 이동한다.
- `DROP_DDL`, `APPEND_DDL`, `sqlite3.connect()` 및 raw INSERT 문을 새 시드 흐름에서 제거한다.
- `python -m scripts.reset_and_seed`가 `drop_all() → create_all() → seed`를 실행하도록 한다.
- 기존 `load_dataset.py` 삭제는 새 명령과 테스트가 통과한 후에만 한다.

검증:

- 초기화 후 buildings, floors, nodes, edges, stores, pois, floor_vector_maps,
  map_features 건수가 현재 테스트 기준값과 동일하다.
- SQLite FK 위반 없이 한 번에 commit된다.

완료 조건:

- 새 개발 DB를 빈 상태에서 재생성하고 지도 데이터를 적재할 수 있다.

### 단순 조회 Query 함수 구현

새 파일:

```text
api/app/queries/__init__.py
api/app/queries/building_queries.py
```

구현 함수와 이전 함수의 대응:

| 새 함수 | 대체 대상 | 핵심 ORM 조회 |
|---|---|---|
| `list_buildings(session)` | `BuildingService.get_all_buildings` | `Building` + `selectinload(Building.floors)` |
| `get_building(session, building_id)` | `get_building` | `Building` 단건 + floors |
| `search_stores(session, building_id, query)` | `search_stores` | `Store`와 `Floor` 조건 조회 |
| `get_floor_map(session, building_id, floor_name)` | `get_floor_map` | Floor, Building, VectorMap/Features, Store, Poi |
| `get_floor_graph(session, building_id, floor_name)` | `get_floor_graph` | Floor의 Node·Edge 목록 |

작업:

- Query 함수는 `Session`을 첫 인자로 받고 `HTTPException`을 import하지 않는다.
- `None`은 존재하지 않는 Building/Floor, 빈 list는 검색 결과 없음이라는 기존 의미를 유지한다.
- 다중 컬렉션은 `joinedload()`로 한꺼번에 묶지 않는다. `selectinload()` 또는 명시적
  `select()`로 조회한다.
- 반환 JSON 모양은 현재 Service의 `_to_*_dict` 결과와 정확히 같게 만든다.

검증:

- 함수 단위 테스트에서 기존 Service 테스트의 기대 JSON을 그대로 재사용한다.
- `GET /buildings`의 N+1이 `selectinload(Building.floors)`로 제거되는지 SQL 로그로 확인한다.

완료 조건:

- 단순 조회 결과가 기존 API 응답과 동등하다.

### NavigationService 구현

새 파일:

```text
api/app/services/__init__.py
api/app/services/navigation_service.py
```

#### 최단 경로 조회 흐름과 ORM 객체 그래프

```text
GET /buildings/{building_id}/floors/{floor_name}/route
    |
    v
routers.buildings.get_shortest_route
    |
    | Depends(get_db)
    v
Session
    |
    | 1. building_id + floor_name으로 Floor 조회
    v
Floor
    |---------------------------> Building
    |                              (현재 경로 계산에는 존재 확인 외 사용하지 않음)
    |
    | 2. floor_id로 Node 전체 조회
    +---------------------------> [Node, Node, Node, ...]
    |
    | 3. floor_id로 Edge 전체 조회
    +---------------------------> [Edge, Edge, Edge, ...]
                                      |           |
                                      |           +--> to_node_id --> Node.id
                                      +--> from_node_id --> Node.id
    |
    v
NavigationService
    |
    | 4. Node + Edge를 순수 dijkstra 함수에 전달
    v
find_shortest_path(nodes, edges, start_node_id, end_node_id)
    |
    +--> ShortestPath(node_ids, edge_ids, total_distance_m)
    |
    | 5. edge_ids 순서대로 Edge.geometry를 연결
    |    역방향 이동이면 geometry 좌표 순서를 뒤집음
    v
RouteResponse
```

경로 계산에서는 `Edge.from_node`, `Edge.to_node` ORM 관계를 매번 따라가지 않는다.
한 Floor의 Node·Edge 전체를 각각 한 번 조회한 뒤, `id → Node`와 `id → Edge` 딕셔너리를
만들어 메모리에서 탐색한다. 그래야 탐색 중 N+1 쿼리가 생기지 않는다.

작업:

- `get_shortest_path()`와 `_build_path_points()`만 기존 `BuildingService`에서 옮긴다.
- Service 생성자 또는 함수 인자로 `Session`을 받고, Floor·Node·Edge 조회에는 ORM Query를 쓴다.
- `app/domain/dijkstra.py`의 순수 다익스트라 함수는 그대로 유지한다.
- 잘못된 시작/끝 Node는 `ValueError`, Floor 없음은 `None`, 경로 없음은
  `{"path_found": false, ...}`라는 기존 계약을 유지한다.

검증:

- `tests/unit/test_dijkstra.py`가 그대로 통과한다.
- route API의 400/404/정상 경로 응답이 기존 통합 테스트와 동일하다.

완료 조건:

- 경로 계산 규칙은 `NavigationService` 한 곳에만 있다.

### Router를 새 DI 구조로 전환

대상: 기존 `api/app/router/buildingRouter.py`, `api/app/FastAPIConfig.py`
→ 전환 후 `api/app/routers/buildings.py`, `api/app/main.py`

#### Router 기준 데이터 흐름

```text
단순 조회 API

GET /buildings/{building_id}/floors/{floor_name}
    |
    v
routers.buildings.get_floor_map
    |
    | Depends(get_db)
    v
Session
    |
    v
building_queries.get_floor_map(session, building_id, floor_name)
    |
    +--> Floor ----------> Building
    |
    +--> Floor ----------> FloorVectorMap ----------> [MapFeature, ...]
    |
    +--> Floor ----------> [Store, Store, ...]
    |
    +--> Floor ----------> [Poi, Poi, ...]
    |
    v
FloorMapResponse 형식의 dict
    |
    v
Router가 None만 404로 변환 후 반환
```

```text
계산이 있는 조회 API

GET /buildings/{building_id}/floors/{floor_name}/route
    |
    v
routers.buildings.get_shortest_route
    |
    | Depends(get_db)
    v
Session
    |
    v
NavigationService(session).get_shortest_path(...)
    |
    +--> Floor → [Node, ...] / [Edge, ...]
    |
    +--> dijkstra → path geometry 조립
    |
    v
RouteResponse 형식의 dict
    |
    v
Router가 ValueError는 400, 없는 Floor/경로는 404로 변환 후 반환
```

작업:

- Router의 `Depends(get_building_service)`를 `Depends(core.database.get_db)`로 교체한다.
- 단순 조회 API는 `building_queries` 함수를 호출한다.
- route API만 `NavigationService(session)`을 생성해 호출한다.
- Router에는 URL/쿼리 파라미터, Depends, response_model, 400/404 변환만 남긴다.
- 기존 API URL과 JSON 키는 변경하지 않는다.

검증:

- 모든 integration API 테스트 통과
- OpenAPI/Swagger에서 기존 endpoint와 response_model 확인

완료 조건:

- `BuildingService`와 `SqliteBuildingRepository` 없이 buildings Router가 동작한다.

### Pydantic 응답 모델 보완

대상: `api/app/schemas/`, `api/app/routers/buildings.py`, `api/app/main.py`

작업:

- `HealthResponse`, `BuildingSummaryResponse`, `BuildingDetailResponse` 등 현재 dict로 반환되는 GET 응답 모델을 추가한다.
- 기존 `FloorMapResponse`, `FloorGraphResponse`, `RouteResponse`는 JSON 키를 바꾸지 않고 유지한다.
- 쓰기 API가 없으므로 `Create`/`Update` DTO는 만들지 않는다.
- ORM 필드명과 API JSON 구조가 다르면 `from_attributes=True`만으로 해결하려 하지 말고,
  Query 함수에서 기존 응답 구조로 명시적으로 조립한다.

검증:

- response_model 검증 후에도 Flutter가 기대하는 JSON 키가 동일하다.

완료 조건:

- `/health`를 포함한 모든 GET endpoint에 응답 모델이 있다.

### 기존 구조 제거

삭제 후보:

```text
api/app/repository/BuildingRepository.py
api/app/repository/sqliteBuildingRepository.py
api/app/service/buildingService.py
api/app/domain/building.py
api/scripts/load_dataset.py
api/app/FastAPIConfig.py의 기존 sqlite3 DI 코드
```

삭제 전 확인:

```text
rg "BuildingService|SqliteBuildingRepository|BuildingRepository|sqlite3" api/app api/tests
```

작업:

- 실제 import가 0개인 파일만 삭제한다.
- `FastAPIConfig.py`는 제거하고 앱 조립 책임은 `main.py`로 옮긴다.
- `app/domain/dijkstra.py`는 유지한다.

완료 조건:

- raw sqlite3 Repository와 중복 Service 구현이 없다.
- 실행·테스트·시드가 ORM 구조만 사용한다.

### 최종 검증

1. 빈 개발 DB 초기화 및 seed 성공
2. unit + integration 테스트 전체 통과
3. `/health`, buildings, store search, floor map, graph, route API 수동 확인
4. `git diff`로 Flutter 계약 변경이 없는지 확인
5. 불필요한 DDL 문자열·sqlite3 import·기존 Repository import가 없는지 확인

---

## 1. 전환 범위 결정

### 할 일

- SQLAlchemy 2.0, pydantic-settings 의존성을 추가한다.
- 기존 SQLite를 유지한다. PostgreSQL 전환은 이번 범위에 포함하지 않는다.
- 기존 API URL 및 응답 JSON 호환 여부를 결정한다.

### 확정된 결정

- [x] DB는 SQLite를 유지한다.
- [x] Alembic은 도입하지 않는다. 개발 DB는 `drop_all() → create_all() → seed`로 초기화한다.
- [x] PostgreSQL 전환은 이번 리팩터링 범위에서 제외한다.
- [x] 기존 API URL과 응답 JSON 형식은 유지한다. Flutter 클라이언트 수정은 이번 범위에서 제외한다.

### 남은 질문

- 없음

### 완료 기준

- 전환 대상 DB와 API 호환 정책이 정해져 있다.
- 추가할 라이브러리와 버전 정책이 정해져 있다.

---

## 2. Core 설정 및 DB Session 도입

### 할 일

- `core/config.py`에 `Settings`를 정의한다.
- `core/database.py`에 `engine`, `SessionLocal`, `get_db()`를 둔다.
- `DATABASE_URL`을 환경변수로 주입할 수 있게 한다.

### 결정 사항

- `get_db()`가 요청 종료 시 자동 `commit()`할지, 쓰기 Service가 명시적으로 `commit()`할지 결정한다.

### 확정된 결정

현재는 읽기 API가 대부분이므로 `get_db()`는 `rollback()`과 `close()`만 보장한다.
쓰기 Service가 모든 검증·변경을 성공한 뒤 명시적으로 `session.commit()`한다.

```python
# core/database.py
def get_db():
    session = SessionLocal()
    try:
        yield session
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


# services/store.py — 쓰기 유스케이스의 최종 성공 지점
def create_store(session: Session, command: StoreCreate) -> Store:
    try:
        store = Store(...)
        session.add(store)
        session.commit()
        session.refresh(store)
        return store
    except Exception:
        session.rollback()
        raise
```

- 단순 조회는 `commit()`하지 않는다.
- 하나의 유스케이스에서 여러 테이블을 변경하면 마지막에 한 번만 `commit()`한다.
- 쓰기 Service는 예외 시 직접 `rollback()`하고 예외를 다시 전달한다.
- `get_db()`의 `rollback()`은 Service 밖에서 발생한 예외를 위한 최종 안전망이다.

### 완료 기준

- 요청마다 독립 `Session`이 열리고 항상 닫힌다.
- 테스트에서 `get_db()`를 테스트 DB Session으로 교체할 수 있다.

---

## 3. 엔티티와 관계 확정

### 엔티티 후보

| 엔티티 | 핵심 관계 | 비고 |
|---|---|---|
| `Building` | 1:N `Floor` | 건물 |
| `Floor` | N:1 `Building`, 1:N 지도 요소 | 층 |
| `Node` | N:1 `Floor` | 길찾기 정점 |
| `Edge` | N:1 `Floor`, N:1 `Node`(출발/도착 각각) | Node를 두 번 참조 |
| `Store` | N:1 `Floor`, 선택적으로 N:1 `Node` | 입구 노드 |
| `Poi` | N:1 `Floor`, 선택적으로 N:1 `Node` | 연결 노드 |
| `FloorVectorMap` | 1:1 `Floor` | SVG 메타데이터 |
| `MapFeature` | N:1 `FloorVectorMap` | 지도 도형 |

### 관계 그림

```text
Building 1 ── * Floor
Floor    1 ── * Node / Edge / Store / Poi
Floor    1 ── 0..1 FloorVectorMap ── * MapFeature

Edge   * ── 1 Node (from_node)
Edge   * ── 1 Node (to_node)
Store  0..1 ── 1 Node (entrance_node)
Poi    0..1 ── 1 Node (linked_node)
```

### ERD 초안

```mermaid
erDiagram
    BUILDINGS ||--o{ FLOORS : contains
    FLOORS ||--o{ NODES : has
    FLOORS ||--o{ EDGES : has
    FLOORS ||--o{ STORES : has
    FLOORS ||--o{ POIS : has
    FLOORS ||--o| FLOOR_VECTOR_MAPS : has
    FLOOR_VECTOR_MAPS ||--o{ MAP_FEATURES : has

    NODES ||--o{ EDGES : from_node
    NODES ||--o{ EDGES : to_node
    NODES o|--o{ STORES : entrance_node
    NODES o|--o{ POIS : linked_node

    BUILDINGS {
        string id PK
        string name
        float area_m2
        float perimeter_m
        json footprint_local_m
    }

    FLOORS {
        string id PK
        string building_id FK
        string name
        int level
    }

    NODES {
        string id PK
        string floor_id FK
        string type
        string name
        float x_m
        float y_m
        float lat
        float lng
    }

    EDGES {
        string id PK
        string floor_id FK
        string from_node_id FK
        string to_node_id FK
        float length_m
        boolean bidirectional
        json geometry
    }

    STORES {
        string id PK
        string floor_id FK
        string name
        string entrance_node_id FK
        json polygon
    }

    POIS {
        string id PK
        string floor_id FK
        string linked_node_id FK
        string type
        string name
    }

    FLOOR_VECTOR_MAPS {
        string floor_id PK_FK
        json coordinate_system
        json source
    }

    MAP_FEATURES {
        string id PK
        string floor_id FK
        string kind
        string geometry_type
        json coordinates
    }
```

### 확정된 결정

- `FloorVectorMap`은 Floor과 `1:0..1` 관계다. 지도 데이터가 없는 층을 허용한다.
- Store의 `entrance_node_id`와 Poi의 `linked_node_id`는 각각 선택적인 단일 Node FK로 유지한다.
  여러 입구 노드가 필요해지는 경우에만 별도 연결 테이블을 도입한다.
- `geometry`, `polygon`, `coordinates` 등 지도 좌표 배열은 SQLite JSON 컬럼으로 유지한다.
- Node의 `lat/lng`는 기존 graph API 응답 호환을 위해 nullable 필드로 유지한다.

### 관계 방향 및 FK 설계 기준

| 관계 | FK | ORM 방향 | 근거 |
|---|---|---|---|
| `Building - Floor` | `floors.building_id` | 양방향 | 건물 목록에서 층 목록을 사용한다. |
| `Floor - Node` | `nodes.floor_id` | 단방향 또는 양방향 | 그래프 조회는 Floor 기준이다. |
| `Floor - Edge` | `edges.floor_id` | 단방향 또는 양방향 | 그래프 조회는 Floor 기준이다. |
| `Edge - Node` | `from_node_id`, `to_node_id` | `Edge → Node` 단방향 | 간선은 출발/도착 Node를 각각 참조한다. Node의 역방향 컬렉션은 현재 불필요하다. |
| `Floor - Store` | `stores.floor_id` | 양방향 | 층 지도에서 Store 목록을 반환한다. |
| `Store - Node` | `entrance_node_id`, nullable | `Store → Node` 단방향 | 현재 API는 입구 Node 객체가 아니라 ID만 반환한다. |
| `Floor - Poi` | `pois.floor_id` | 양방향 | 층 지도에서 POI 목록을 반환한다. |
| `Poi - Node` | `linked_node_id`, nullable | `Poi → Node` 단방향 | 현재 API는 연결 Node 객체가 아니라 ID만 반환한다. |
| `Floor - FloorVectorMap` | `floor_vector_maps.floor_id` | 양방향 1:0..1 | 도면 데이터가 없는 층을 허용한다. |
| `FloorVectorMap - MapFeature` | `map_features.floor_id` | 양방향 | 도면과 Feature 목록을 함께 사용한다. |

`Edge`는 `from_node_id`, `to_node_id` 두 FK를 반드시 가진다. 다만 현재 다익스트라는
한 층의 Node·Edge 전체를 읽어 계산하므로, `Node.outgoing_edges`와
`Node.incoming_edges` 역방향 컬렉션은 만들지 않는다.

### Fetch join 및 배치 로딩 기준

| API/로직 | 현재 조회 흐름 | ORM 전환 후 권장 |
|---|---|---|
| `GET /buildings` | 건물마다 층을 별도 조회하므로 건물이 늘면 N+1 | `selectinload(Building.floors)` |
| `GET /buildings/{id}/floors/{floor}` | Floor, Building, VectorMap, Feature, Store, Poi를 각각 조회 | 여러 컬렉션에는 `selectinload()` 또는 명시적 쿼리 |
| `GET .../graph`, `GET .../route` | Node 전체와 Edge 전체를 각각 조회 | 현재처럼 Floor 단위 명시적 조회 유지 |

- `joinedload()`는 `Floor → Building`, `Floor → FloorVectorMap`처럼 다대일·일대일 관계에만 제한적으로 사용한다.
- `Floor → Stores`, `Nodes`, `Edges`, `Pois`, `MapFeatures`를 모두 `joinedload()`하면
  컬렉션 간 곱집합으로 행 수가 폭증할 수 있으므로 사용하지 않는다.
- SQLAlchemy에서는 `selectinload()`가 Hibernate의 `@BatchSize` 활용과 가장 유사하다.
  전역 batch size를 먼저 지정하지 말고, 실제 N+1이 생기는 조회에 선택적으로 적용한다.

### 완료 기준

- FK, nullable 여부, unique 제약 조건이 엔티티별로 정해져 있다.
- 양방향 ORM 관계가 정말 필요한 곳만 정해져 있다.

---

## 4. ORM 모델 구현

### 할 일

- `models/base.py`에 공통 `Base(DeclarativeBase)`를 만든다.
- 엔티티별 ORM 모델과 FK·인덱스를 구현한다.
- 기존 DDL의 제약 조건과 인덱스가 모델 선언에 반영되는지 확인한다.

### 전체 ORM 모델 초안

아래는 현재 `load_dataset.py`의 8개 테이블을 그대로 옮긴 초안이다. 구현을 시작할 때
이 코드를 `models/base.py`, `models/building.py`, `models/navigation.py`, `models/place.py`로
분리한다.

```python
# models/base.py
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass
```

```python
# models/building.py
from __future__ import annotations

from typing import TYPE_CHECKING

from sqlalchemy import Float, ForeignKey, Integer, JSON, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base

if TYPE_CHECKING:
    from app.models.navigation import Edge, Node
    from app.models.place import FloorVectorMap, Poi, Store


class Building(Base):
    __tablename__ = "buildings"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    area_m2: Mapped[float | None] = mapped_column(Float)
    perimeter_m: Mapped[float | None] = mapped_column(Float)
    footprint_local_m: Mapped[list[dict] | None] = mapped_column(JSON)

    floors: Mapped[list["Floor"]] = relationship(back_populates="building")


class Floor(Base):
    __tablename__ = "floors"
    __table_args__ = (
        UniqueConstraint("building_id", "name", name="uq_floors_building_name"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True)
    building_id: Mapped[str] = mapped_column(
        String,
        ForeignKey("buildings.id"),
        nullable=False,
    )
    name: Mapped[str] = mapped_column(String, nullable=False)
    level: Mapped[int] = mapped_column(Integer, nullable=False)

    building: Mapped["Building"] = relationship(back_populates="floors")
    nodes: Mapped[list["Node"]] = relationship(back_populates="floor")
    edges: Mapped[list["Edge"]] = relationship(back_populates="floor")
    stores: Mapped[list["Store"]] = relationship(back_populates="floor")
    pois: Mapped[list["Poi"]] = relationship(back_populates="floor")
    vector_map: Mapped["FloorVectorMap | None"] = relationship(
        back_populates="floor",
        uselist=False,
    )
```

```python
# models/navigation.py
from __future__ import annotations

from typing import TYPE_CHECKING

from sqlalchemy import Boolean, Float, ForeignKey, Index, JSON, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base

if TYPE_CHECKING:
    from app.models.building import Floor


class Node(Base):
    __tablename__ = "nodes"
    __table_args__ = (
        Index("idx_nodes_floor", "floor_id"),
        Index("idx_nodes_type", "type"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True)
    floor_id: Mapped[str] = mapped_column(ForeignKey("floors.id"), nullable=False)
    type: Mapped[str] = mapped_column(String, nullable=False)
    name: Mapped[str | None] = mapped_column(String)
    x_m: Mapped[float] = mapped_column(Float, nullable=False)
    y_m: Mapped[float] = mapped_column(Float, nullable=False)
    lat: Mapped[float | None] = mapped_column(Float)
    lng: Mapped[float | None] = mapped_column(Float)
    source_x: Mapped[float | None] = mapped_column(Float)
    source_y: Mapped[float | None] = mapped_column(Float)

    floor: Mapped["Floor"] = relationship(back_populates="nodes")


class Edge(Base):
    __tablename__ = "edges"
    __table_args__ = (
        Index("idx_edges_floor", "floor_id"),
        Index("idx_edges_from", "from_node_id"),
        Index("idx_edges_to", "to_node_id"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True)
    floor_id: Mapped[str] = mapped_column(ForeignKey("floors.id"), nullable=False)
    from_node_id: Mapped[str] = mapped_column(ForeignKey("nodes.id"), nullable=False)
    to_node_id: Mapped[str] = mapped_column(ForeignKey("nodes.id"), nullable=False)
    length_m: Mapped[float] = mapped_column(Float, nullable=False)
    bidirectional: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    geometry: Mapped[list[dict] | None] = mapped_column(JSON)

    floor: Mapped["Floor"] = relationship(back_populates="edges")
    from_node: Mapped[Node] = relationship(foreign_keys=[from_node_id])
    to_node: Mapped[Node] = relationship(foreign_keys=[to_node_id])
```

```python
# models/place.py
from __future__ import annotations

from typing import TYPE_CHECKING

from sqlalchemy import Float, ForeignKey, Index, Integer, JSON, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base

if TYPE_CHECKING:
    from app.models.building import Floor
    from app.models.navigation import Node


class Store(Base):
    __tablename__ = "stores"
    __table_args__ = (
        Index("idx_stores_floor", "floor_id"),
        Index("idx_stores_name", "name"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True)
    floor_id: Mapped[str] = mapped_column(ForeignKey("floors.id"), nullable=False)
    name: Mapped[str] = mapped_column(String, nullable=False)
    centroid_x_m: Mapped[float] = mapped_column(Float, nullable=False)
    centroid_y_m: Mapped[float] = mapped_column(Float, nullable=False)
    entrance_x_m: Mapped[float | None] = mapped_column(Float)
    entrance_y_m: Mapped[float | None] = mapped_column(Float)
    entrance_node_id: Mapped[str | None] = mapped_column(ForeignKey("nodes.id"))
    polygon: Mapped[list[dict] | None] = mapped_column(JSON)

    floor: Mapped["Floor"] = relationship(back_populates="stores")
    entrance_node: Mapped["Node | None"] = relationship(
        foreign_keys=[entrance_node_id],
    )


class Poi(Base):
    __tablename__ = "pois"
    __table_args__ = (
        Index("idx_pois_floor", "floor_id"),
        Index("idx_pois_type", "type"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True)
    floor_id: Mapped[str] = mapped_column(ForeignKey("floors.id"), nullable=False)
    type: Mapped[str] = mapped_column(String, nullable=False)
    name: Mapped[str | None] = mapped_column(String)
    x_m: Mapped[float] = mapped_column(Float, nullable=False)
    y_m: Mapped[float] = mapped_column(Float, nullable=False)
    linked_node_id: Mapped[str | None] = mapped_column(ForeignKey("nodes.id"))

    floor: Mapped["Floor"] = relationship(back_populates="pois")
    linked_node: Mapped["Node | None"] = relationship(
        foreign_keys=[linked_node_id],
    )


class FloorVectorMap(Base):
    __tablename__ = "floor_vector_maps"

    floor_id: Mapped[str] = mapped_column(
        ForeignKey("floors.id"),
        primary_key=True,
    )
    coordinate_system: Mapped[dict] = mapped_column(JSON, nullable=False)
    source: Mapped[dict] = mapped_column(JSON, nullable=False)

    floor: Mapped["Floor"] = relationship(back_populates="vector_map")
    features: Mapped[list["MapFeature"]] = relationship(back_populates="vector_map")


class MapFeature(Base):
    __tablename__ = "map_features"
    __table_args__ = (
        Index("idx_map_features_floor", "floor_id"),
        Index("idx_map_features_kind", "kind"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True)
    floor_id: Mapped[str] = mapped_column(
        ForeignKey("floor_vector_maps.floor_id"),
        primary_key=True,
    )
    kind: Mapped[str] = mapped_column(String, nullable=False)
    name: Mapped[str | None] = mapped_column(String)
    category: Mapped[str | None] = mapped_column(String)
    geometry_type: Mapped[str] = mapped_column(String, nullable=False)
    coordinates: Mapped[list | dict] = mapped_column(JSON, nullable=False)
    centroid_x: Mapped[float | None] = mapped_column(Float)
    centroid_y: Mapped[float | None] = mapped_column(Float)

    vector_map: Mapped["FloorVectorMap"] = relationship(back_populates="features")
```

모든 모델 파일을 import한 뒤에만 `Base.metadata.create_all(engine)`을 호출한다.

### 주의

- `Edge`의 from/to 관계는 `foreign_keys`를 명시한다.
- JSON 형태의 지도 좌표는 ORM 관계로 분해하지 않고 JSON/TEXT 컬럼으로 유지할 수 있다.
- 모델의 양방향 `relationship`을 Pydantic 응답으로 그대로 반환하지 않는다.

### 완료 기준

- `Base.metadata.create_all()`로 빈 개발 DB의 테이블 생성이 가능하다.
- 기존 스키마와 필요한 제약·인덱스가 동일하다.

---

## 5. 개발 DB 초기화 및 초기 데이터 적재 분리

### 할 일

- 기존 DDL 문자열을 제거하고 ORM 모델의 `Base.metadata.drop_all()`과
  `Base.metadata.create_all()`로 교체한다.
- JSON → DB 적재 로직은 `seed_navigation.py`로 분리해 유지한다.
- 개발 초기화 명령은 `drop_all() → create_all() → seed` 순서로 실행한다.

### 결정 사항

- 현재 결정: 스키마가 자주 바뀌므로 개발용 DB는 매번 삭제 후 재생성한다.
- Alembic은 DB 구조가 안정되고 기존 데이터를 보존해야 하는 시점에 도입한다.

### 작성할 코드 초안

`models/__init__.py`는 모든 모델을 import하여 `Base.metadata`에 등록한다.

```python
# app/models/__init__.py
from app.models.building import Building, Floor
from app.models.navigation import Edge, Node
from app.models.place import FloorVectorMap, MapFeature, Poi, Store

__all__ = [
    "Building", "Floor", "Node", "Edge", "Store", "Poi",
    "FloorVectorMap", "MapFeature",
]
```

개발 DB 초기화는 별도 함수로 둔다. 앱 서버 시작 시 자동 실행하지 않고, 명시적인
CLI 명령에서만 호출한다. 서버 재시작마다 데이터가 삭제되는 일을 막기 위해서다.

```python
# scripts/reset_database.py
from app.core.database import engine
import app.models  # 모든 모델을 Base.metadata에 등록
from app.models.base import Base


def reset_database() -> None:
    """개발 SQLite DB의 모든 테이블을 삭제하고 ORM 정의대로 다시 생성한다."""
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
```

시드 스크립트는 DDL을 갖지 않고 JSON을 ORM 객체로 변환해 한 트랜잭션으로 저장한다.

```python
# scripts/seed_navigation.py
from __future__ import annotations

import json
from math import hypot
from pathlib import Path

from app.core.database import SessionLocal
from app.models import (
    Building,
    Edge,
    Floor,
    FloorVectorMap,
    MapFeature,
    Node,
    Poi,
    Store,
)

API_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_JSON = API_ROOT / "app" / "data" / "navigation_1f.json"
DEFAULT_VECTOR_DIR = API_ROOT / "app" / "data" / "vector_maps"


def find_vector_dataset(
    vector_path: Path,
    *,
    building_id: str,
    floor_id: str,
) -> dict:
    """디렉터리 안에서 현재 건물/층에 맞는 벡터 JSON 하나를 찾는다."""
    candidates = (
        [vector_path]
        if vector_path.is_file()
        else sorted(vector_path.rglob("*.json"))
    )
    matches: list[dict] = []
    for path in candidates:
        with path.open(encoding="utf-8") as file:
            data = json.load(file)
        if data.get("building_id") == building_id and data.get("floor_id") == floor_id:
            matches.append(data)

    if len(matches) != 1:
        raise ValueError(f"{building_id}/{floor_id} 벡터 JSON은 정확히 하나여야 합니다.")
    return matches[0]


def edge_geometry_and_length(
    edge: dict,
    node_points: dict[str, dict[str, float]],
) -> tuple[list[dict], float]:
    """geometry 또는 length가 누락된 입력을 노드 좌표로 보완한다."""
    geometry = edge.get("geometry_local_m") or [
        dict(node_points[edge["from"]]),
        dict(node_points[edge["to"]]),
    ]
    length_m = edge.get("length_m")
    if length_m is None:
        length_m = sum(
            hypot(current["x"] - previous["x"], current["y"] - previous["y"])
            for previous, current in zip(geometry, geometry[1:])
        )
    return geometry, length_m


def seed_navigation(
    json_path: Path = DEFAULT_JSON,
    vector_path: Path | None = DEFAULT_VECTOR_DIR,
) -> None:
    """JSON 지도 데이터 한 건물/층을 비어 있는 개발 DB에 적재한다."""
    with json_path.open(encoding="utf-8") as file:
        data = json.load(file)

    building_data = data["building"]
    floor_data = building_data["floor"]
    building_id = building_data["id"]
    floor_id = floor_data["id"]
    node_points = {
        node["id"]: node["position"]["local_m"]
        for node in data["nodes"]
    }

    session = SessionLocal()
    try:
        session.add(
            Building(
                id=building_id,
                name=building_data["name"],
                area_m2=building_data.get("area_m2"),
                perimeter_m=building_data.get("perimeter_m"),
                footprint_local_m=building_data.get("footprint_local_m"),
            )
        )
        session.add(
            Floor(
                id=floor_id,
                building_id=building_id,
                name=floor_data["name"],
                level=floor_data["level"],
            )
        )

        session.add_all(
            Node(
                id=node["id"],
                floor_id=floor_id,
                type=node["type"],
                name=node.get("name"),
                x_m=node["position"]["local_m"]["x"],
                y_m=node["position"]["local_m"]["y"],
                lat=(node["position"].get("wgs84") or {}).get("lat"),
                lng=(node["position"].get("wgs84") or {}).get("lng"),
                source_x=(node["position"].get("source") or {}).get("x"),
                source_y=(node["position"].get("source") or {}).get("y"),
            )
            for node in data["nodes"]
        )

        edges: list[Edge] = []
        for edge in data["edges"]:
            geometry, length_m = edge_geometry_and_length(edge, node_points)
            edges.append(
                Edge(
                    id=edge["id"],
                    floor_id=floor_id,
                    from_node_id=edge["from"],
                    to_node_id=edge["to"],
                    length_m=length_m,
                    bidirectional=edge.get("bidirectional", True),
                    geometry=geometry,
                )
            )
        session.add_all(edges)

        session.add_all(
            Store(
                id=store["id"],
                floor_id=floor_id,
                name=store["name"],
                centroid_x_m=store["centroid"]["local_m"]["x"],
                centroid_y_m=store["centroid"]["local_m"]["y"],
                entrance_x_m=(store.get("entrance_local_m") or {}).get("x"),
                entrance_y_m=(store.get("entrance_local_m") or {}).get("y"),
                entrance_node_id=store.get("entrance_node_id"),
                polygon=store.get("polygon_local_m"),
            )
            for store in data["stores"]
        )
        session.add_all(
            Poi(
                id=poi["id"],
                floor_id=floor_id,
                type=poi["type"],
                name=poi.get("name"),
                x_m=poi["position"]["local_m"]["x"],
                y_m=poi["position"]["local_m"]["y"],
                linked_node_id=poi.get("linked_node_id"),
            )
            for poi in data["pois"]
        )

        if vector_path is not None:
            vector_data = find_vector_dataset(
                vector_path,
                building_id=building_id,
                floor_id=floor_id,
            )
            session.add(
                FloorVectorMap(
                    floor_id=floor_id,
                    coordinate_system=vector_data["coordinate_system"],
                    source=vector_data["source"],
                )
            )
            session.add_all(
                MapFeature(
                    id=feature["id"],
                    floor_id=floor_id,
                    kind=feature["kind"],
                    name=feature.get("name"),
                    category=feature.get("category"),
                    geometry_type=feature["geometry"]["type"],
                    coordinates=feature["geometry"]["coordinates"],
                    centroid_x=(feature.get("centroid") or {}).get("x"),
                    centroid_y=(feature.get("centroid") or {}).get("y"),
                )
                for feature in vector_data["features"]
            )

        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
```

두 작업을 하나의 개발용 명령으로 연결한다.

```python
# scripts/reset_and_seed.py
from scripts.reset_database import reset_database
from scripts.seed_navigation import seed_navigation


if __name__ == "__main__":
    reset_database()
    seed_navigation()
    print("개발 DB 초기화 및 지도 데이터 적재 완료")
```

### 완료 기준

- 개발 DB는 ORM 모델 정의를 기준으로 삭제·재생성된다.
- 지도 데이터는 스키마 생성 뒤 seed 스크립트로 적재된다.
- SQL DDL 문자열을 직접 유지하지 않는다.

---

## 6. Pydantic 응답 모델 정리

### 목적

이 단계는 ORM 모델을 API 밖으로 노출하지 않고, Flutter가 소비하는 JSON 응답 계약을
Pydantic `response_model`로 고정하는 작업이다. 현재 쓰기 API가 없으므로 Create/Update
DTO는 만들지 않고 GET API의 응답 모델만 다룬다.

### 응답 흐름과 책임

```text
SQLAlchemy ORM 객체
    |
    | 단순 조회: building_queries
    | 경로 계산: NavigationService
    v
기존 API JSON 형태의 dict 조립
    | 예: centroid_x_m / centroid_y_m → {"x": ..., "y": ...}
    |     from_node_id / to_node_id → from / to
    v
Router의 response_model 검증 및 직렬화
    v
Flutter가 사용하는 기존 JSON 응답
```

`routers/`에는 URL, 파라미터, `Depends(get_db)`, `response_model`, 400/404 변환만 둔다.
ORM 조회와 응답 dict 조립은 `queries/` 또는 `services/`에 둔다. Pydantic 모델은 ORM
엔티티나 Service의 반환 타입이 아니라 외부 HTTP 응답 계약이다.

### 응답 모델 적용 대상

| API | 응답 모델 | 응답 dict 조립 위치 |
|---|---|---|
| `GET /health` | `HealthResponse` | `main.py` |
| `GET /buildings` | `list[BuildingSummaryResponse]` | `building_queries.list_buildings` |
| `GET /buildings/{building_id}` | `BuildingDetailResponse` | `building_queries.get_building` |
| `GET /buildings/{building_id}/stores` | `list[StoreResponse]` | `building_queries.search_stores` |
| `GET /buildings/{building_id}/floors/{floor_name}` | `FloorMapResponse` | `building_queries.get_floor_map` |
| `GET /buildings/{building_id}/floors/{floor_name}/graph` | `FloorGraphResponse` | `building_queries.get_floor_graph` |
| `GET /buildings/{building_id}/floors/{floor_name}/route` | `RouteResponse` | `NavigationService.get_shortest_path` |

`POST /query/destination`, `POST /query/info`은 현재 stub이므로 이번 단계에서 응답 모델을
추가하지 않는다.

### 확정된 규칙

- 건물 목록과 상세 API에도 명시적 응답 모델을 추가한다.
- 기존 URL, HTTP 상태 코드, JSON 키를 유지한다.
- 특히 graph 응답의 `from`, `to`, 지도/매장 응답의 `centroid_local_m`, 경로 응답의
  `path_points` 구조를 바꾸지 않는다.
- ORM 필드명과 JSON 키가 다르면 Query/Service가 명시적으로 dict를 조립한다.
  예를 들어 내부 `from_node_id`, `to_node_id`는 외부에서 `from`, `to`로 유지한다.
- Pydantic alias는 API 계약 검증을 위한 보조 수단이며, ORM 관계 객체를 그대로 직렬화하지
  않는다.

### 할 일

- `HealthResponse`, `BuildingSummaryResponse`, `BuildingDetailResponse`를 추가한다.
- 기존 `FloorMapResponse`, `FloorGraphResponse`, `RouteResponse`는 JSON 키를 변경하지 않고
  유지한다.
- `/health`와 모든 buildings GET endpoint에 해당 `response_model`을 선언한다.
- 응답 모델 검증을 통과하는지와 Swagger에 기존 응답 구조가 표시되는지 확인한다.

### 완료 기준

- Router가 ORM 엔티티를 직접 반환하지 않는다.
- 모든 GET API의 응답 계약이 Pydantic 모델로 선언돼 있다.
- Flutter가 소비하는 기존 JSON 키와 중첩 구조가 유지된다.

---

## 7. 조회 코드와 Service 재배치

### ORM 객체를 얻는 조회 흐름

```text
단순 조회

Router → Session → building_queries
                    |
                    +--> Building → [Floor, ...]
                    +--> Floor → [Store, Poi, Node, Edge, ...]
                    +--> Floor → FloorVectorMap → [MapFeature, ...]
                    |
                    v
                 응답 dict → Pydantic response_model

경로 조회

Router → Session → NavigationService
                    |
                    +--> Floor 조회
                    +--> floor_id로 Node 전체 조회
                    +--> floor_id로 Edge 전체 조회
                    |
                    v
                 dijkstra → RouteResponse
```

경로 탐색 중에는 `Edge.from_node`, `Edge.to_node` 관계를 반복해서 따라가지 않는다.
Node·Edge 전체를 한 번씩 읽고 `id → 객체` 딕셔너리로 만든 뒤 메모리에서 탐색한다.

### 먼저 확정할 목표 구조

Router는 URL 파라미터·Dependency·HTTP 상태 코드만 처리한다. 단순 조회 SQL은
`queries/`에, 계산·규칙은 `services/`에 둔다. 이로써 모든 조회에 형식적인 Service를
만들지 않으면서도 Router가 DB 조회와 응답 조립으로 비대해지는 일을 막는다.

```text
Router
  ├── 단순 조회 → queries/building_queries.py
  └── 최단 경로 → services/navigation_service.py
```

### API별 책임 확정표

| 현재 API | API가 하는 일 | 목표 코드 위치 | Service 필요 여부 | Router에 남길 일 |
|---|---|---|---|---|
| `GET /health` | 서버 생존 확인 | `main.py` | 불필요 | `{"status": "ok"}` 반환 |
| `GET /buildings` | 건물 요약 목록과 층 이름 조회 | `queries/building_queries.py:list_buildings` | 불필요 | Query 호출 및 응답 반환 |
| `GET /buildings/{building_id}` | 건물 상세 조회 | `queries/building_queries.py:get_building` | 불필요 | `None`이면 404 변환 |
| `GET /buildings/{building_id}/stores?q=` | 건물 존재 확인 후 매장 이름 검색 | `queries/building_queries.py:search_stores` | 불필요 | `None`이면 404 변환 |
| `GET /buildings/{building_id}/floors/{floor_name}` | Floor, Building, VectorMap, Store, Poi를 조회해 지도 응답 조립 | `queries/building_queries.py:get_floor_map` | 불필요 | `None`이면 404 변환 |
| `GET /buildings/{building_id}/floors/{floor_name}/graph` | Floor의 Node·Edge 목록 조회 | `queries/building_queries.py:get_floor_graph` | 불필요 | `None`이면 404 변환 |
| `GET /buildings/{building_id}/floors/{floor_name}/route` | Node·Edge 조회, 다익스트라, 경로 geometry 방향 보정 | `services/navigation_service.py:get_shortest_path` | 필요 | `ValueError`는 400, 없는 층/경로는 404 변환 |
| `POST /query/destination` | 목적지 자연어 질의 | 현재 Router stub 유지 | 현재 불필요 | 요청 검증 및 stub 응답 |
| `POST /query/info` | 장소 정보 자연어 질의 | 현재 Router stub 유지 | 현재 불필요 | 요청 검증 및 stub 응답 |

### Service를 두는 기준

`NavigationService`는 아래 이유로 유지한다.

- DB에서 가져온 Node·Edge를 다익스트라 함수에 전달한다.
- 경로가 존재하지 않는 경우와 잘못된 입력을 구분한다.
- 간선을 역방향으로 지날 때 geometry 좌표 순서를 뒤집고, 여러 geometry를 하나의 path로 합친다.

반대로 건물·층·매장 조회는 DB를 읽어 정해진 응답 구조로 만드는 작업이므로 Service가 아니라
`queries/`에 둔다. `queries/`는 SQLAlchemy `Session`과 `select()`, `selectinload()`를 사용하지만
HTTPException·FastAPI 타입은 import하지 않는다.

### 최종 DI 흐름

```text
단순 조회
Router → Depends(get_db) → Session → building_queries 함수

최단 경로
Router → Depends(get_db) → Session → NavigationService(Session) → dijkstra
```

각 Router는 `Session` 또는 `NavigationService` 중 하나만 주입받는다. Router가 ORM 모델 관계를
직접 순회하거나 다익스트라를 호출하지 않는다.

### 현재 `BuildingService` 재배치 결정

| 현재 함수 | 목표 위치 | 이유 |
|---|---|---|
| `get_all_buildings` | `building_queries.py` | 단순 목록 조회 |
| `get_building` | `building_queries.py` | 단순 단건 조회 |
| `search_stores` | `building_queries.py` | 조건 조회 |
| `get_floor_map` | `building_queries.py` | Floor 관련 읽기 데이터를 한 응답으로 조합 |
| `get_floor_graph` | `building_queries.py` | Node·Edge 단순 조회 |
| `get_shortest_path` | `navigation_service.py` | 다익스트라 실행·경로 geometry 방향 보정 규칙이 있음 |
| `_build_path_points` | `navigation_service.py` | 최단 경로 결과의 도메인 규칙 |

`queryRouter`의 RAG 기능은 현재 stub이므로 당장 Service를 만들지 않는다. 실제 LLM/검색
연동을 시작할 때 `QueryService` 또는 외부 어댑터를 별도로 둔다.

### 분류 기준

| 작업 성격 | 위치 |
|---|---|
| ID 단건 조회, 단순 목록 조회 | Router 또는 작은 query 함수 |
| 재사용되는 join/필터/페이징 쿼리 | Repository |
| 최단 경로 계산, 여러 엔티티 조합, 검증 규칙 | Service |
| HTTP 상태 코드, 입력 파싱 | Router |

### 현재 코드에 적용

- `get_shortest_path`, 그래프 조립: `NavigationService` 유지
- 건물/층/매장 단순 조회: `queries/`의 Session 기반 조회로 단순화
- `SqliteBuildingRepository`의 수동 row → dataclass 매핑: ORM 도입 후 제거

### 완료 기준

- 엔티티마다 형식적인 Service/Repository가 생기지 않는다.
- `NavigationService`는 HTTP/FastAPI 타입을 모른다.

---

## 8. Router 및 DI 전환

### 확정된 결정

- 기존 `api/app/router/`는 `api/app/routers/`로 이름을 변경한다.
  - `buildingRouter.py` → `buildings.py`
  - `queryRouter.py` → `query.py`
  - 파일명은 역할을 나타내는 snake_case로 통일한다. 이 변경은 Python import 경로만
    바꾸며 외부 API URL에는 영향을 주지 않는다.
- `FastAPIConfig.py`는 최종적으로 제거한다.
  - `core/config.py`: 환경설정과 `DATABASE_URL`
  - `core/database.py`: engine, SessionLocal, `get_db`
  - `main.py`: FastAPI 앱 생성, CORS, Router 등록, `/health`
- buildings Router는 `Depends(core.database.get_db)`로 `Session`을 주입받는다.
  - 단순 조회는 `building_queries`를 호출한다.
  - route API만 `NavigationService(session)`를 생성해 호출한다.
- query Router는 현재 stub 구현을 유지하고, 새 `routers/query.py`에서 등록한다.
- 테스트의 `dependency_overrides` 대상은 기존 `FastAPIConfig.get_db`가 아니라
  `core.database.get_db`로 변경한다.

### 전환 후 흐름

```text
GET /buildings...                 POST /query/...
        |                                  |
        v                                  v
routers/buildings.py                routers/query.py
        |
        | Depends(get_db)
        v
Session ──→ building_queries         (route만 NavigationService)
```

### 할 일

- `routers/buildings.py`의 모든 endpoint를 Session 기반 DI로 전환한다.
- `routers/query.py`를 등록하고 기존 query stub API를 유지한다.
- `main.py`에서 CORS, Router 등록, `/health`를 조립하고 `FastAPIConfig.py`를 제거한다.
- 테스트의 `dependency_overrides`와 import를 새 `get_db` 경로로 전환한다.

### 완료 기준

- 기존 API 경로와 상태 코드가 의도대로 유지된다.
- Router에는 HTTP 책임만 남고, sqlite3 Repository/기존 BuildingService DI가 없다.
- `main.py`, `core/config.py`, `core/database.py`의 책임이 겹치지 않는다.

---

## 9. 테스트 전환

### 테스트 원칙

- `get_db()`가 연결을 열고 닫는지처럼 FastAPI/SQLAlchemy의 기본 동작 자체는 테스트하지
  않는다.
- ORM 객체의 `isinstance()`만 확인하지 않는다. 객체가 존재하더라도 잘못된 건물·층을
  조회하거나 Flutter 응답 구조가 깨질 수 있으므로, 사용자가 소비하는 핵심 결과를 확인한다.
- 구현 세부사항을 과도하게 확인하지 않는다. raw SQL, SQLite JSON 문자열, 모든 컬럼의
  반복 비교 대신 각 규칙에 정상 사례 하나와 실패 사례 하나를 둔다.
- 현재는 쓰기 API가 없으므로 세션 범위에서 한 번 `reset → seed`한 임시 SQLite DB를
  Query/API 테스트가 공유한다. 요청별 transaction rollback 또는 테스트별 독립 DB는 쓰기
  API가 생길 때 도입한다.

### 유지·교체할 테스트

| 범위 | 유지 또는 새로 작성할 검증 | 제거 또는 교체할 기존 검증 |
|---|---|---|
| 순수 알고리즘 | `test_dijkstra.py`의 최단 거리·단방향·동일 노드·음수 간선 검사 유지 | 없음 |
| 시드 | `reset → seed` 뒤 ORM Session으로 Building/Floor/Node/Edge/VectorMap이 조회되고 핵심 관계가 유효한지 확인 | `sqlite3.Connection`과 raw SQL/JSON 문자열을 직접 확인하는 `test_etl.py` |
| Query | 실제 시드 DB에서 건물·매장·지도·그래프 조회 결과의 식별자와 핵심 JSON 구조 확인 | Fake Repository 기반 단순 조회 `BuildingService` 테스트 |
| NavigationService | 정상 경로, 역방향 geometry, geometry 누락 보완, 경로 없음 확인 | 기존 `BuildingService`에 묶인 경로 테스트를 새 Service로 이전 |
| API 계약 | endpoint별 정상 응답, 대표 JSON 키, 400/404 상태 코드 확인 | Query/Service와 같은 데이터를 API에서 전부 반복 비교 |

### 시드 ORM 조회 테스트 기준

시드 테스트는 “SQLite에 SQL 문자열이 정확히 저장됐는가”가 아니라 “시드한 지도 데이터를
ORM과 API가 사용할 수 있는가”를 검증한다.

```python
node_ids = {node.id for node in nodes}

assert nodes and all(node.floor_id == floor.id for node in nodes)

assert edges and all(
    edge.floor_id == floor.id
    and edge.from_node_id in node_ids
    and edge.to_node_id in node_ids
    for edge in edges
)

assert any(len(edge.geometry) >= 2 for edge in edges)

assert vector_map is not None
assert vector_map.features
```

- `assert edges`는 빈 목록을 막는다. 빈 목록에서는 `all(...)`이 `True`가 되므로 생략하지
  않는다.
- `all(...)`은 모든 간선이 해당 층의 실제 노드를 참조하는지 확인한다.
- `any(...)`은 geometry가 있는 간선이 하나 이상 있는지 확인한다.
- vector map 존재와 feature 존재는 서로 다른 실패 원인을 보여 주므로 두 assert로 분리한다.

### 오류 테스트 최소 사례

정상 사례와 오류 사례는 하나의 테스트에 섞지 않고 별도로 작성한다.

- 없는 건물 또는 층 요청 → `404`
- 존재하지 않는 시작/끝 노드 → `400`
- 서로 연결되지 않은 노드 간 route 요청 → `404 Route not found`
- 중복된 건물·층 vector JSON 등 잘못된 시드 입력 → `ValueError` 및 트랜잭션 rollback

### 할 일

- 임시 SQLite DB를 `reset → seed`하는 Session 범위 fixture를 만든다.
- FastAPI `dependency_overrides`로 `core.database.get_db`를 테스트 Session으로 교체한다.
- `test_etl.py`의 raw SQL 검증을 ORM Session 기반 시드 검증으로 교체한다.
- `test_building_service.py`를 제거하고, 단순 조회는 Query 테스트로, 경로 규칙은
  `NavigationService` 테스트로 이전한다.
- API 계약과 위의 오류 최소 사례를 유지·보강한다.

### 완료 기준

- 전체 테스트가 raw sqlite3 Repository와 기존 BuildingService에 의존하지 않는다.
- 시드 데이터가 ORM 조회와 API 계약에 필요한 관계·응답 구조를 제공함이 검증된다.
- 정상 흐름과 핵심 오류 경계가 각각 최소 한 사례로 검증된다.

---

## 권장 진행 순서

1. **기준선 확인:** `git status --short`, 전체 테스트, 기존 API 계약을 기록한다.
2. **2단계:** SQLAlchemy 의존성을 추가하고 `core/config.py`, `core/database.py`를 만든다.
3. **3·4단계:** 확정한 관계를 바탕으로 ORM 모델을 구현하고, 빈 임시 DB에서
   `Base.metadata.create_all()`을 검증한다.
4. **5단계:** `reset → seed` CLI를 구현해 ORM 모델만으로 개발 DB를 재생성·적재한다.
5. **6단계:** 모든 GET API의 Pydantic 응답 모델을 구현한다.
6. **7단계:** `building_queries`와 `NavigationService`로 기존 조회·경로 규칙을 옮긴다.
7. **8단계:** `routers/`와 `main.py`로 HTTP/DI를 전환하고 `FastAPIConfig.py`를 제거한다.
8. **9단계:** 임시 시드 DB 기반 테스트로 전환하고, API 계약·오류 경계·전체 테스트를
   검증한다.
9. **기존 구조 제거:** 모든 검증 후 raw sqlite3 Repository, 기존 BuildingService, domain
   dataclass, 기존 시드 코드를 제거하고 import가 남지 않았는지 확인한다.

각 단계는 해당 단계의 검증을 통과한 뒤에만 다음 단계로 진행한다. 특히 시드가 성공하기 전에는
Query/API 테스트 전환을 시작하지 않으며, 응답 모델이 준비되기 전에는 Router 전환을 시작하지
않는다.

## 커밋 단위 작업 체크리스트

아래 체크박스 하나를 하나의 짧은 커밋으로 처리한다. 각 커밋은 해당 단계의 테스트 또는 검증을
통과한 뒤에만 만든다. 커밋 메시지는 제안한 한 줄을 사용한다.

- [x] 문서 확정 — `문서: ORM 전환 계획 정리`
- [x] SQLAlchemy와 pydantic-settings 의존성 추가 — `의존성: ORM 패키지 추가`
- [x] Settings, engine, SessionLocal, `get_db` 추가 — `코어: DB 세션 추가`
- [x] 8개 ORM 모델과 빈 DB `create_all()` 검증 — `모델: 지도 ORM 추가`
- [x] ORM 기반 reset·seed CLI 구현 — `시드: 지도 데이터 ORM 적재`
- [x] GET API 응답 모델 추가 — `스키마: GET 응답 모델 추가`
- [x] 건물·매장·지도·그래프 Query 함수 이전 — `조회: 건물 ORM 쿼리 추가`
- [x] 최단 경로 `NavigationService` 이전 — `서비스: 경로 탐색 이전`
- [x] `routers/`, `main.py`, Session DI로 HTTP 계층 전환 — `라우터: ORM DI 전환`
- [x] 임시 시드 DB fixture와 Query/Service/API 테스트 전환 — `테스트: ORM 검증 전환`
- [x] 기존 sqlite3 Repository·BuildingService·시드·설정 코드 제거 — `정리: sqlite3 구조 제거`

커밋 경계는 합리적이다. 다만 기존 앱이 계속 실행·테스트될 수 있도록 새 `schemas/`,
`queries/`, `services/`, `routers/`는 전환 커밋 전까지 추가만 하고 기존 모듈을 먼저 삭제하지
않는다. 기존 `schema/`, `router/`, `FastAPIConfig.py`와 sqlite3 구조의 제거는 마지막 정리
커밋에서만 수행한다.

## 현재 진행 상태

- [x] 현재 구조 파악
- [x] 목표 구조 초안 작성
- [x] 1단계 결정
- [x] 3단계 설계: 엔티티 관계와 JSON/nullable 정책 확정
- [x] 6단계 설계: GET 응답 모델과 API 계약 확정
- [x] 7단계 설계: API별 책임과 Service 경계 확정
- [x] 8단계 설계: Router/DI와 앱 조립 구조 확정
- [x] 9단계 설계: 테스트 범위와 오류 사례 확정
- [x] 기준선 테스트 기록
- [x] 2단계 구현: Core 설정과 Session DI
- [x] 4단계 구현: ORM 모델과 빈 DB 생성 검증
- [x] 5단계 구현: reset·seed CLI
- [x] 6단계 구현: GET 응답 모델
- [x] 7단계 구현: Query/NavigationService로 코드 이동
- [x] 8단계 구현: Router/DI 전환과 `main.py` 정리
- [x] 9단계 구현: 테스트 전환과 최종 검증
- [x] 기존 sqlite3 구조 제거
