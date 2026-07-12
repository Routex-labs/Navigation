# FastAPI 요청 관통 흐름 — uvicorn부터 SQLAlchemy Session까지

> `GET /buildings/{building_id}/floors/{floor_name}/route` 요청 하나가 소켓에 도착해서
> JSON 응답으로 나갈 때까지의 전체 경로와, 각 구간에서 알아야 하는 지식 정리.
> Spring 대응 개념을 `≒`로 병기한다.
> 기준 코드: `api/app/main.py`, `app/core/database.py`, `app/routers/buildings.py`,
> `app/queries/building_queries.py`, `app/services/navigation_service.py`,
> `app/domain/dijkstra.py`.

## 0. 한 줄 대응표

| FastAPI 세계 | Spring 세계 |
|---|---|
| uvicorn | Tomcat (WAS) |
| ASGI 프로토콜 | Servlet 스펙 |
| `scope` dict / `Request` | `HttpServletRequest` |
| FastAPI `app` 객체 | DispatcherServlet + ApplicationContext |
| CORSMiddleware (미들웨어 스택) | Filter Chain |
| APIRouter / 경로 매칭 | HandlerMapping |
| `Depends(get_db)` | `@Autowired` (단, 기본 스코프가 요청) |
| SQLAlchemy `Session` | JPA `EntityManager` / Hibernate Session |
| `models/` (DeclarativeBase) | JPA `@Entity` |
| `selectinload()` | fetch join / `@BatchSize` |
| Pydantic 바인딩/검증 | `@PathVariable`/`@RequestParam`/`@RequestBody` + Bean Validation |
| `schemas/` (response_model) | DTO + Jackson 직렬화 스키마 |
| router 함수 | `@RestController` |
| `HTTPException` + 기본 핸들러 | `@ExceptionHandler` |
| `jsonable_encoder` + `JSONResponse` | Jackson `HttpMessageConverter` + `ResponseEntity` |
| lifespan | `@PostConstruct` / `@PreDestroy` |
| pydantic-settings (`NAV_` 환경변수) | `application.yml` |

## 1. 데이터 객체 관계 — ORM 엔티티

스키마의 원천은 DDL 문자열이 아니라 `app/models/`의 SQLAlchemy 모델 선언이다.
`Base.metadata.create_all()`이 이 선언에서 테이블을 생성한다.

```mermaid
erDiagram
    BUILDINGS ||--o{ FLOORS : contains
    FLOORS ||--o{ NODES : contains
    FLOORS ||--o{ EDGES : contains
    FLOORS ||--o{ STORES : contains
    FLOORS ||--o{ POIS : contains
    FLOORS ||--o| FLOOR_VECTOR_MAPS : has
    FLOOR_VECTOR_MAPS ||--o{ MAP_FEATURES : has

    NODES ||--o{ EDGES : from_node
    NODES ||--o{ EDGES : to_node
    NODES o|--o{ STORES : entrance_node
    NODES o|--o{ POIS : linked_node
```

| 파일 | 엔티티 | 관계 |
|---|---|---|
| `models/building.py` | `Building`, `Floor` | `Building 1:N Floor` 양방향 (`back_populates`) |
| `models/navigation.py` | `Node`, `Edge` | `Edge → Node` 단방향 2개 (`foreign_keys` 명시) |
| `models/place.py` | `Store`, `Poi`, `FloorVectorMap`, `MapFeature` | Floor 기준 컬렉션 + 선택적 Node FK |

관계 설계 규칙:

- `Node.outgoing_edges` 같은 역방향 컬렉션은 만들지 않는다. 경로 탐색은 한 층의
  Node·Edge 전체를 한 번에 읽어 메모리에서 수행하므로 역방향 관계가 필요 없다.
- `geometry`, `polygon`, `coordinates` 같은 지도 좌표 배열은 관계로 분해하지 않고
  SQLite **JSON 컬럼**으로 유지한다. 별도 테이블로 분리하면 불필요한 JOIN만 늘어난다.
- 좌표는 `x_m`, `y_m` 평면 컬럼이다. 예전 구조의 `LocalPoint` 값 객체는 ORM 전환과
  함께 제거됐고, `{"x": ..., "y": ...}` 중첩 JSON으로의 변환은 `queries/`가 응답 dict를
  조립할 때 명시적으로 수행한다.

```text
테이블 스키마 표현   → models/ (DeclarativeBase 선언)
데이터 조회          → queries/ (Session + select)
경로 계산 규칙       → services/navigation_service.py
순수 알고리즘        → domain/dijkstra.py
화면 그래프 그리기   → Flutter
```

## 2. 전체 관통 흐름 (요청 → 응답 왕복)

```text
 [Client (Flutter / Swagger UI)]
        │
        │  ① GET /buildings/{b}/floors/1F/route?start_node_id=A&end_node_id=B
        ▼
┌────────────────────────────────────────────────────────────────────┐
│  uvicorn  ── ASGI 서버                                  ≒ Tomcat   │
│                                                                    │
│   HTTP 파싱 ──► scope dict 생성                                    │
│                 {method, path, headers, query_string, ...}         │
│                                                                    │
│   단일 스레드 asyncio 이벤트 루프에서 모든 요청 처리               │
└──────────────────────────────┬─────────────────────────────────────┘
                               │  ② await app(scope, receive, send)
                               ▼
┌────────────────────────────────────────────────────────────────────┐
│  FastAPI app  (main.create_app())            ≒ DispatcherServlet   │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  CORSMiddleware                           ≒ Servlet Filter  │  │
│  │   OPTIONS preflight → 즉시 응답 / 응답에 CORS 헤더 부착      │  │
│  │                                                              │  │
│  │  ┌────────────────────────────────────────────────────────┐  │  │
│  │  │  Router (Starlette)               ≒ HandlerMapping    │  │  │
│  │  │   등록 순서대로 첫 매칭 · 없음 404 · 메서드 다름 405   │  │  │
│  │  │                                                        │  │  │
│  │  │  ┌──────────────────────────────────────────────────┐  │  │  │
│  │  │  │  Depends(core.database.get_db)   ≒ Spring DI    │  │  │  │
│  │  │  │   session = SessionLocal()                       │  │  │  │
│  │  │  │   yield session      ← 여기서 핸들러 실행        │  │  │  │
│  │  │  │   except → rollback / finally → close            │  │  │  │
│  │  │  │   (응답 전송 후 실행되는 요청 스코프 자원 정리)   │  │  │  │
│  │  │  └───────────────────────┬──────────────────────────┘  │  │  │
│  │  │                          ▼                             │  │  │
│  │  │  ┌──────────────────────────────────────────────────┐  │  │  │
│  │  │  │  Pydantic 바인딩/검증                            │  │  │  │
│  │  │  │   building_id, floor_name ◄── URL 경로           │  │  │  │
│  │  │  │   start_node_id, q ◄── 쿼리스트링                │  │  │  │
│  │  │  │   (형 변환 실패 시 핸들러 실행 전에 422 차단)     │  │  │  │
│  │  │  └───────────────────────┬──────────────────────────┘  │  │  │
│  │  │                          ▼                             │  │  │
│  │  │      ★ sync/async 분기 (FastAPI 최대 함정) ★          │  │  │
│  │  │       def      → anyio 스레드풀에서 실행 (블로킹 OK)  │  │  │
│  │  │       async def → 이벤트 루프에서 직접 실행           │  │  │
│  │  │                   (동기 SQLAlchemy 호출 시 서버 정지)  │  │  │
│  │  └──────────────────────────┬─────────────────────────────┘  │  │
│  └─────────────────────────────┼────────────────────────────────┘  │
└────────────────────────────────┼───────────────────────────────────┘
                                 │  ③ 여기부터 프레임워크 없음.
                                 │     그냥 Python 함수 호출.
                                 ▼
      ┌───────────────────────────────────────────────┐
      │  routers/buildings.py 핸들러     ≒ Controller │
      │   HTTP ↔ 결과 번역만.                          │
      │   None → HTTPException(404)                   │
      │   ValueError → HTTPException(400)             │
      └──────────┬───────────────────────┬────────────┘
                 │ 단순 조회             │ 최단 경로만
                 ▼                       ▼
  ┌─────────────────────────┐  ┌──────────────────────────────┐
  │ queries/                │  │ services/                    │
  │ building_queries.py     │  │ navigation_service.py        │
  │  select() 조회 +        │  │  Floor 조회 → 층의 Node·Edge │
  │  selectinload(floors)   │  │  전체를 각각 1회 조회        │
  │  기존 JSON 모양 dict    │  │  → dijkstra (메모리 탐색)    │
  │  조립 (from/to,         │  │  → geometry 방향 보정으로    │
  │  centroid_local_m)      │  │    path_points 조립          │
  └────────────┬────────────┘  └──────────────┬───────────────┘
               └──────────────┬───────────────┘
                              ▼
      ┌───────────────────────────────────────────────┐
      │  SQLAlchemy Session / Engine                  │
      │   core/database.py                            │
      │   Session은 요청마다 생성·종료                 │
      │   Engine은 프로세스 전역 재사용                │
      └──────────────────────┬────────────────────────┘
                             ▼
                   ┌───────────────────┐
                   │  SQLite (파일 IO) │
                   │  navigation.db    │
                   └───────────────────┘
```

## 3. 되돌아가는 길 (응답 방향)

```text
  queries/services ──dict──► router 반환
                               │
                               ▼
        ┌─────────────────────────────────────────────┐
        │  response_model 검증 (schemas/)             │
        │   선언된 스키마로 검증 + 미선언 필드 필터링  │
        │   ≒ DTO 직렬화 스키마                       │
        └──────────────────┬──────────────────────────┘
                           ▼
        ┌─────────────────────────────────────────────┐
        │  jsonable_encoder → JSONResponse            │
        │   ≒ Jackson ObjectMapper + ResponseEntity   │
        └──────────────────┬──────────────────────────┘
                           ▼
        ┌─────────────────────────────────────────────┐
        │  CORSMiddleware (역방향 통과)                │
        │   Access-Control-Allow-Origin 부착          │
        └──────────────────┬──────────────────────────┘
                           ▼
        ┌─────────────────────────────────────────────┐
        │  uvicorn — HTTP 상태줄/헤더/바디 바이트 조립 │
        └──────────────────┬──────────────────────────┘
                           │  TCP
                           ▼
                    [Client (Flutter)]

  응답 전송이 끝난 뒤 → get_db의 finally 실행 (session.close())
```

에러가 나는 경우의 경로:

```text
  검증 실패(타입 불일치 등)   ──► 핸들러 실행 전 차단        ──► 422 JSON
  None (없는 건물/층/경로)    ──► router가 HTTPException(404) ──► {"detail": "..."}
  ValueError (잘못된 노드 ID) ──► router가 HTTPException(400) ──► {"detail": "..."}
  처리 안 된 예외             ──► get_db rollback 후 500      ──► 스택트레이스는 서버 로그
```

## 4. 최단 경로 요청의 상세 흐름

`GET .../route`만 Service를 거친다. 핵심은 **DB는 두 번만 읽고, 탐색은 전부
메모리에서**다. 탐색 중 `Edge.from_node` 같은 ORM 관계를 따라가면 간선마다
lazy load 쿼리(N+1)가 발생하므로, Node·Edge 전체를 dict로 인덱싱한 뒤 탐색한다.

```text
NavigationService(session).get_shortest_path(...)
    │ 1. Floor 조회 (building_id + floor_name) ── 없으면 None → 404
    │ 2. select(Node).where(floor_id=...)  ← 쿼리 1번
    │ 3. select(Edge).where(floor_id=...)  ← 쿼리 1번
    ▼
domain/dijkstra.py — find_shortest_path(nodes, edges, start, end)
    │  인접 리스트 dict 구성 (bidirectional이면 역방향도 등록)
    │  heapq 우선순위 큐 탐색
    │  잘못된 노드 ID → ValueError / 경로 없음 → None
    ▼
ShortestPath(node_ids, edge_ids, total_distance_m)
    ▼
_build_path_points — 간선 geometry를 하나의 선으로 연결
    │  geometry 없는 간선 → 양 끝 노드 좌표로 보완
    │  역방향 통과 간선 → 좌표 순서 reverse()
    │  인접 간선의 공통 접점 좌표는 한 번만 포함
    ▼
RouteResponse (path_points, total_distance_m, ...)
```

계층별 책임:

| 계층 | 담당 | 담당하지 않는 것 |
|---|---|---|
| `queries/` | Session 기반 단순 조회, 응답 dict 조립 | HTTP 타입 import, 경로 계산 |
| `services/` | Floor·Node·Edge 조회 조합, 다익스트라 호출, geometry 방향 보정 | HTTP 상태 코드 |
| `routers/` | 파라미터 검증, Query/Service 호출, HTTP 응답·오류 변환 | 경로 계산, ORM 조회 |
| `domain/dijkstra.py` | 순수 최단 경로 알고리즘 | DB, HTTP, ORM 관계 |
| Flutter | 경로 상태 저장, Polyline·마커 렌더링 | 서버 조회 |

`dijkstra.py`는 FastAPI도 Session도 모른다. ORM 객체의 `id`, `from_node_id`,
`to_node_id`, `length_m`, `bidirectional` 속성만 duck-typing으로 사용하므로
단위 테스트에서 DB 없이 검증할 수 있다.

### DB 관점과 Python 메모리 관점의 탐색 차이

| 관점 | 실제로 하는 일 |
|---|---|
| SQLite | `WHERE floor_id = ?`로 필요한 Node·Edge 행만 선별 |
| SQLAlchemy | row를 `Node`, `Edge` ORM 객체로 매핑 |
| Service | 조회 결과 `list[Node]`, `list[Edge]`를 알고리즘에 전달 |
| dijkstra | `Edge` 목록으로 인접 리스트를 만들어 메모리 탐색 |

DB는 데이터 선별과 저장을 담당하고, 최단 경로 계산은 Python 프로세스 내부
메모리에서 수행한다.

## 5. 단계별 상세 지식

### 0단계. 서버 기동 (요청이 오기 전)

`uvicorn app.main:app --reload` 실행 시:

1. uvicorn이 `app.main` 모듈을 **import** → `create_app()` 실행
   (FastAPI 생성, `add_middleware`, `include_router`, `/health` 등록).
   Spring의 ApplicationContext 초기화에 해당하지만 **컴포넌트 스캔이 없다** —
   전부 명시적으로 조립한다.
2. `app.core.database` import 시점에 `Settings` 로드(환경변수 `NAV_DATABASE_URL`)와
   **Engine 생성**이 한 번 일어난다. Engine·SessionLocal은 프로세스 전역이다.
3. 소켓(기본 8000)을 열고 **asyncio 이벤트 루프** 시작.
4. startup 이벤트에서 DB를 초기화하지 않는다. `drop_all/create_all/seed`는
   `python -m scripts.reset_and_seed` CLI에서만 실행한다.

### 1단계. uvicorn — TCP → scope

HTTP 바이트를 파싱해 `scope`(dict)를 만든다. method, path, 헤더, 쿼리스트링이
들어있는 `HttpServletRequest`의 원재료다.

### 2단계. 미들웨어 (CORSMiddleware)

- `add_middleware`로 등록한 것들이 앱을 양파처럼 감싼다. 요청은 바깥→안,
  응답은 안→바깥.
- CORSMiddleware는 브라우저의 **preflight OPTIONS**를 라우터 도달 전에 가로채
  즉시 응답하고, 실제 응답에는 `Access-Control-Allow-Origin`을 붙인다.
- CORS는 **브라우저 보안 모델**이다. Flutter 모바일 앱/curl에는 관여하지 않는다.

### 3단계. 라우팅

- `APIRouter(prefix="/buildings")` + `@router.get("/{building_id}")`는 include 시점에
  정규식으로 컴파일된다.
- **등록 순서대로 첫 매칭 승리.** 고정 경로는 파라미터 경로보다 먼저 등록한다.
- 경로 없음 → 404, 경로는 맞고 메서드 다름 → 405. 둘 다 라우터 단계에서 종료.

### 4단계. Depends (DI)

Spring DI와 결정적으로 다른 점 3가지:

1. **기본 스코프가 싱글톤이 아니라 요청.** 매 요청 `get_db()`가 다시 불려
   새 Session을 만든다. Engine처럼 프로세스 전역이어야 하는 것은 모듈 전역에 둔다.
2. **같은 요청 안에서는 동일 dependency가 캐시**된다 (`use_cache=True` 기본).
3. **`yield` dependency**로 자원 정리를 한다. 현재 `core/database.py`의 `get_db`:

```python
def get_db() -> Iterator[Session]:
    session = SessionLocal()
    try:
        yield session       # ← 여기서 핸들러 실행
    except Exception:
        session.rollback()  # ← 핸들러 밖 예외의 최종 안전망
        raise
    finally:
        session.close()     # ← 응답 전송 후 실행
```

읽기 API뿐이므로 `get_db()`는 자동 commit하지 않는다. 쓰기 유스케이스가 생기면
해당 Service가 명시적으로 `session.commit()`한다.

### 5단계. 파라미터 바인딩 + 검증 (Pydantic)

타입 힌트만 보고 값의 출처를 결정한다:

| 시그니처 | 출처 | Spring |
|---|---|---|
| 경로 템플릿에 있는 이름 (`building_id: str`) | URL 경로 | `@PathVariable` |
| 경로에 없는 단순 타입 (`q: str = ""`) | 쿼리스트링 | `@RequestParam` |
| Pydantic 모델 타입 | 요청 바디 JSON | `@RequestBody` |
| `Depends(...)` | DI | `@Autowired` |

검증 실패는 핸들러 실행 전에 **422**로 차단된다. ORM 엔티티(`models/`)와
HTTP 계약(`schemas/`)을 분리하는 이유는 Entity/DTO 분리 이유와 같다.

### 6단계. ★ sync vs async (가장 중요)

- **`def` 핸들러** → anyio **스레드풀**(기본 40)에서 실행. 블로킹 IO 안전.
- **`async def` 핸들러** → **이벤트 루프에서 직접** 실행. 내부에서 동기 SQLAlchemy,
  `requests`, `time.sleep()` 같은 블로킹 호출을 하면 **서버 전체가 정지**한다.

규칙: **동기 SQLAlchemy를 쓰는 동안 모든 핸들러는 `def`로 선언한다.**
`async def`는 `httpx`, async SQLAlchemy처럼 await 가능한 스택으로 바꿀 때만 쓴다.

### 7단계. router → queries / services

프레임워크 마법이 없는 순수 Python 구간. 계층별 계약:

- **router**: HTTP만 안다. `None` → 404, `ValueError` → 400 번역. 비즈니스 로직 금지.
- **queries**: Session 기반 단순 조회와 응답 dict 조립. `HTTPException` import 금지.
  `None` = 없는 건물/층, 빈 list = 검색 결과 없음이 규약.
- **services**: 계산 규칙이 있는 로직만 (`NavigationService`). HTTP를 모른다.
- 형식적인 Repository 계층은 두지 않는다. 복잡한 쿼리 재사용이 실제로 생길 때만
  도입을 검토한다.

로딩 전략:

- `GET /buildings`는 `selectinload(Building.floors)`로 층 목록 N+1을 제거한다.
- 여러 컬렉션을 `joinedload()`로 한꺼번에 묶으면 곱집합으로 행이 폭증하므로
  컬렉션에는 `selectinload()` 또는 명시적 `select()`만 쓴다.
- 경로 탐색은 관계 순회 대신 Floor 단위 명시적 조회 2번으로 처리한다.

SQLAlchemy + 스레드 지식:

1. `def` 핸들러는 스레드풀에서 돌므로 요청마다 스레드가 다를 수 있다.
   Session은 스레드 간 공유하면 안 되므로 **요청당 생성·종료**한다 (yield dependency).
   SQLite 연결 옵션에 `check_same_thread=False`를 주는 이유도 스레드풀 실행 때문이다.
2. Engine의 커넥션 풀은 프로세스 전역으로 재사용된다.

### 8단계. 직렬화

- 반환 dict → `response_model` 스키마로 **검증 + 미선언 필드 필터링**
  (내부 필드 유출 방지 안전장치. `/health`를 포함한 모든 GET에 선언되어 있다)
  → `jsonable_encoder` → `JSONResponse`.
- ORM 필드명과 API JSON 키가 다르면 (`from_node_id` → `from`) Pydantic 자동 매핑에
  의존하지 않고 `queries/`가 명시적으로 dict를 조립한다. Flutter 계약이 우선이다.

### 9단계. 반환

`JSONResponse`가 미들웨어를 역순 통과(CORS 헤더 부착) → ASGI `send` → uvicorn이
HTTP 바이트로 조립해 소켓에 쓴다. yield dependency의 `finally`(session.close)는
응답 전송 후 실행된다.

## 6. 꼭 기억할 것 7개

1. **uvicorn=Tomcat, FastAPI=Spring MVC, ASGI=Servlet 스펙, Session=EntityManager,
   Pydantic=DTO+Validation, Depends=DI** — 역할 대응만 잡으면 구조는 같다.
2. 단일 스레드 이벤트 루프가 기본. **동기 SQLAlchemy를 쓰는 핸들러는 반드시 `def`**
   (`async def` + 동기 DB = 서버 정지).
3. Depends는 **요청 스코프가 기본**. Session은 요청마다, Engine은 프로세스마다.
4. 자원 정리는 **yield dependency** (`rollback`/`close`). 서버 startup에서 DB 초기화 금지.
5. 컬렉션 로딩은 **selectinload**, 경로 탐색은 **Floor 단위 명시 조회 + 메모리 탐색**
   — ORM 관계를 루프 안에서 따라가면 N+1이다.
6. 라우트는 **등록 순서 매칭** → 고정 경로를 파라미터 경로보다 먼저.
7. 스키마의 원천은 `models/`, HTTP 계약의 원천은 `schemas/`, 변환은 `queries/`가
   명시적으로 수행한다 — Flutter가 소비하는 JSON 키가 항상 우선이다.
