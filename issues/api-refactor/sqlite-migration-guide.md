# SQLite 전환 구현 가이드 (따라하기)

> 더미(인메모리 + sample_building.json) API를 실데이터(navigation_1f.json) + SQLite
> 기반으로 전환한 전체 과정 기록. 이 문서 순서대로 따라 하면 동일한 결과를 재현할 수 있다.
> 설계 근거는 `docs/api-design.md`, 데이터 가공 근거는 `docs/dataset-analysis.md`,
> FastAPI 동작 원리는 `docs/fastapi-request-flow.md` 참고.

## 0. 완성 후 모습

```text
api/
|-- app/
|   |-- main.py                        # 진입점: app = create_app() 한 줄
|   |-- FastAPIConfig.py               # 설정 + DI 체인 + 앱 팩토리
|   |-- domain/building.py             # 불변 dataclass 6종 (Building/Floor/Node/Edge/Store/Poi)
|   |-- repository/
|   |   |-- BuildingRepository.py      # Protocol 인터페이스 (9개 메서드 계약)
|   |   `-- sqliteBuildingRepository.py# SQLite 구현체
|   |-- service/buildingService.py     # 비즈니스 로직 (HTTP 모름, 없으면 None)
|   |-- router/
|   |   |-- buildingRouter.py          # /buildings/* 엔드포인트
|   |   `-- queryRouter.py             # /query/* RAG 스텁
|   `-- data/navigation_1f.json        # 가공된 실데이터 (scripts/process_1f_dataset.py 산출)
|-- scripts/load_dataset.py            # ETL: JSON -> SQLite (멱등)
|-- data/navigation.db                 # 생성물 (.gitignore 대상)
`-- tests/
    |-- conftest.py                    # 실데이터를 임시 DB에 적재하는 픽스처
    |-- unit/test_building_service.py
    `-- integration/test_api.py
```

요청 흐름 (상세한 각 구간 설명은 `docs/fastapi-request-flow.md`):

```text
uvicorn → FastAPI app → buildingRouter → BuildingService
        → BuildingRepository(Protocol) ← SqliteBuildingRepository → navigation.db
```

## 1. 사전 준비

```bash
cd api
py -3.12 -m venv .venv          # 반드시 3.12 (아래 함정 #4 참고)
.venv\Scripts\activate
pip install -r requirements.txt
```

전제: `app/data/navigation_1f.json`이 존재해야 한다. 없으면 저장소 루트에서
`python scripts/process_1f_dataset.py` 로 먼저 생성한다(데이터 가공 단계).

## 2. Step 1 — ETL: JSON → SQLite (`scripts/load_dataset.py`)

### 스키마 요점

`docs/api-design.md`의 6개 테이블(buildings, floors, nodes, edges, stores, pois)을
그대로 사용하되, 두 가지 원칙을 지킨다.

- **가변 길이 기하(footprint/polygon/geometry)는 JSON 문자열 TEXT 컬럼**에 넣는다.
  노드 234개 규모에서 공간 인덱스는 불필요하고, 읽을 때 `json.loads` 한 번이면 된다.
- **`source_x/source_y`(도면 원본 좌표)를 nodes에 보존**한다. 좌표 재보정 시
  DB만으로 재계산할 수 있게 하기 위함이다(dataset-analysis.md의 결정).

### 멱등 설계

스크립트 처음에 `DROP TABLE IF EXISTS ...` 후 재생성한다. 언제든 다시 실행해도
같은 결과가 나오므로 "DB가 꼬였나?" 싶으면 그냥 재실행하면 된다.

### 핵심 코드 형태

```python
def load_navigation_db(json_path=DEFAULT_JSON, db_path=DEFAULT_DB) -> dict[str, int]:
    data = json.load(open(json_path, encoding="utf-8"))
    conn = sqlite3.connect(db_path)
    try:
        conn.executescript(DDL)              # DROP + CREATE
        conn.execute("INSERT INTO buildings ...")
        conn.executemany("INSERT INTO nodes ...", [...])   # 대량은 executemany
        conn.commit()
        return {table: count, ...}           # 적재 건수 반환 (테스트에서 활용)
    finally:
        conn.close()
```

함수로 분리해 둔 이유: **테스트 conftest가 이 함수를 import해서 임시 DB를 만든다.**
CLI 실행(`__main__`)은 argparse로 경로만 받아 이 함수를 호출한다.

### 실행과 확인

```bash
python scripts/load_dataset.py
```

기대 출력:

```text
적재 완료: ...\api\data\navigation.db
  buildings: 1
  floors: 1
  nodes: 234
  edges: 282
  stores: 61
  pois: 47
```

직접 확인하고 싶으면:

```bash
python -c "import sqlite3; c=sqlite3.connect('data/navigation.db'); \
print(c.execute('SELECT name FROM stores LIMIT 3').fetchall())"
```

## 3. Step 2 — Domain (`app/domain/building.py`)

`@dataclass(frozen=True)` 불변 객체 6종. 규칙:

- **FastAPI/sqlite3 어디에도 의존하지 않는다** (import 목록에 dataclasses뿐).
- 로직 없음 — 데이터만. JPA Entity가 아니라 값 객체에 가깝다.
- 좌표는 전부 building-local meter(`x_m`, `y_m`). WGS84(`lat`,`lng`)는 보조값.

```python
@dataclass(frozen=True)
class Node:
    id: str
    floor_id: str
    type: str      # corridor | junction | store_entrance | escalator | elevator | dead_end
    name: str | None
    x_m: float
    y_m: float
    lat: float | None
    lng: float | None
```

기존 더미 `Building`(floors/floor_data + getter/setter)은 통째로 대체된다.

## 4. Step 3 — Repository

### 인터페이스 (`app/repository/BuildingRepository.py`)

`typing.Protocol`로 계약만 선언한다 (Spring interface 대응). 9개 메서드:

```text
find_all_buildings()                      find_nodes_by_floor(floor_id)
find_building_by_id(building_id)          find_edges_by_floor(floor_id)
find_floors_by_building(building_id)      find_stores_by_floor(floor_id)
find_floor_by_name(building_id, name)     find_pois_by_floor(floor_id)
search_stores(building_id, query)
```

규약: **"없음"은 예외가 아니라 None(단건)/빈 리스트(목록)** 로 표현한다.

### SQLite 구현 (`app/repository/sqliteBuildingRepository.py`)

```python
class SqliteBuildingRepository:
    def __init__(self, conn: sqlite3.Connection):   # 커넥션은 주입받는다
        self._conn = conn

    def find_building_by_id(self, building_id):
        row = self._conn.execute("SELECT ... WHERE id = ?", (building_id,)).fetchone()
        return self._to_building(row) if row else None
```

포인트 3가지:

1. **커넥션을 만들지 않고 주입받는다.** 수명 관리는 FastAPIConfig의 `get_db`
   (yield dependency) 책임. repository는 SQL 실행과 row→domain 매핑만 한다.
2. SQL 파라미터는 반드시 `?` 바인딩. f-string으로 SQL을 조립하면 인젝션 구멍이 된다.
   (검색어도 `LIKE ?` + `f"%{query}%"` 값 바인딩으로 처리)
3. JSON TEXT 컬럼은 여기서 `json.loads`로 복원해 domain 객체에 담는다.

`conn.row_factory = sqlite3.Row` 덕분에 `row["name"]`처럼 컬럼명으로 접근한다
(설정은 get_db에서 한다).

## 5. Step 4 — Service (`app/service/buildingService.py`)

- 생성자에서 `BuildingRepository`(Protocol 타입)를 받는다. SQLite인지 인메모리인지 모른다.
- `HTTPException`을 import하지 않는다 — HTTP는 router의 책임.
- domain 객체 → API 응답 dict 가공을 담당한다. 목록 응답에는 footprint 같은
  무거운 필드를 빼고, 상세 응답에만 넣는다.

```python
def get_floor_graph(self, building_id, floor_name):
    floor = self.building_repository.find_floor_by_name(building_id, floor_name)
    if floor is None:
        return None            # router가 404로 번역
    return {"floor": ..., "nodes": [...], "edges": [...]}
```

## 6. Step 5 — Router (`app/router/buildingRouter.py`)

```python
router = APIRouter(prefix="/buildings", tags=["buildings"])

@router.get("/{building_id}/floors/{floor_name}/graph")
def get_floor_graph(building_id: str, floor_name: str,
                    service: BuildingService = Depends(get_building_service)):
    result = service.get_floor_graph(building_id, floor_name)
    if result is None:
        raise HTTPException(status_code=404, detail="Floor not found")
    return result
```

포인트:

- **모든 핸들러는 `def`(동기)로 선언.** sqlite3는 블로킹 IO이므로 `async def`로
  바꾸면 이벤트 루프가 막혀 서버 전체가 멈춘다. (fastapi-request-flow.md 6단계)
- 층 파라미터는 문자열 이름(`1F`)이다. 기존 더미는 int였는데, 실데이터의 층
  식별자가 "1F" 같은 이름이라 문자열로 바꿨다.
- 라우트는 등록 순서대로 매칭되므로, 나중에 `/buildings/search` 같은 고정 경로를
  추가한다면 `/{building_id}`보다 **위에** 선언해야 한다.

`queryRouter.py`는 기존 `routers/query.py`(RAG 스텁)를 새 디렉토리 규약에 맞춰
옮긴 것으로 로직 변화 없음.

## 7. Step 6 — FastAPIConfig + main

`app/FastAPIConfig.py`가 설정/DI/팩토리를 한 곳에서 담당한다 (Spring의
application.yml + @Configuration 대응).

### DI 체인

```python
def get_db():                            # ← yield dependency
    conn = sqlite3.connect(get_db_path())
    conn.row_factory = sqlite3.Row
    try:
        yield conn                       # 핸들러 실행
    finally:
        conn.close()                     # 응답 전송 후 자동 정리

def get_building_repository(conn = Depends(get_db)) -> BuildingRepository:
    return SqliteBuildingRepository(conn)

def get_building_service(repository = Depends(get_building_repository)) -> BuildingService:
    return BuildingService(repository)
```

- **요청마다 커넥션을 새로 연다.** `def` 핸들러는 스레드풀에서 실행되므로 커넥션을
  전역 공유하면 `check_same_thread` 에러가 난다. SQLite는 파일이라 연결 비용이
  무시할 수준이므로 요청당 연결이 정석.
- 기존 더미의 `@lru_cache` 싱글톤 repository는 제거됐다 — 커넥션이 요청 스코프가
  되면서 repository도 요청 스코프가 됐기 때문.
- DB 경로는 `NAV_DB_PATH` 환경변수로 교체 가능 (기본 `api/data/navigation.db`).

### 순환 import 함정

buildingRouter가 `from app.FastAPIConfig import get_building_service`를 하므로,
FastAPIConfig가 모듈 레벨에서 router를 import하면 **순환 import**가 터진다.
해법: 라우터 import를 `create_app()` 함수 안으로 내린다.

```python
def create_app() -> FastAPI:
    from app.router import buildingRouter, queryRouter   # 함수 안 import
    app = FastAPI(title="Navigation API", version="0.2.0")
    ...
```

### main.py

```python
from app.FastAPIConfig import create_app
app = create_app()
```

앱 팩토리 패턴을 쓰면 테스트가 독립된 app 인스턴스를 만들 수 있다.

## 8. Step 7 — 테스트

### conftest.py 전략

**목/더미 대신 실데이터를 임시 SQLite에 적재해서 테스트한다.** ETL 함수를
그대로 쓰므로 "적재 → repository → service → HTTP" 전체 경로가 검증된다.

```python
@pytest.fixture(scope="session")            # 세션당 1회만 적재 (빠름)
def navigation_db_path(tmp_path_factory):
    db_path = tmp_path_factory.mktemp("db") / "navigation.db"
    load_navigation_db(json_path=DEFAULT_JSON, db_path=db_path)
    return db_path

@pytest.fixture
def api_client(navigation_db_path):
    app = create_app()
    def override_get_db():                  # get_db만 임시 DB로 교체
        conn = sqlite3.connect(navigation_db_path)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
        finally:
            conn.close()
    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as client:
        yield client
    app.dependency_overrides.clear()
```

`dependency_overrides`는 DI 체인의 **가장 아래(get_db)** 만 갈아끼운다.
repository/service는 실제 코드가 그대로 돈다.

### 검증 기준값

가공 결과(docs/dataset-analysis.md)의 수치를 그대로 단언한다:
노드 234, 엣지 282, 매장 61, POI 47, 면적 16,182.4 m², 층 이름 "1F",
매장 검색("베네타") 결과 존재, 엣지의 from/to가 모두 실존 노드.

### 실행

```bash
python -m pytest tests/unit tests/integration -q
```

기대 출력: `20 passed`

## 9. Step 8 — 서버 실행과 확인

```bash
python scripts/load_dataset.py      # DB 없으면 먼저
uvicorn app.main:app --reload
```

확인 (브라우저에서 http://localhost:8000/docs 또는 curl):

```bash
curl http://localhost:8000/health
# {"status":"ok"}

curl http://localhost:8000/buildings
# [{"id":"thehyundai-seoul","name":"[배포]현대백화점-더현대서울점(파크원)","floors":["1F"]}]

curl "http://localhost:8000/buildings/thehyundai-seoul/stores?q=베네타"
# [{"id":"store_000","name":"보테가 베네타",...}]

curl http://localhost:8000/buildings/thehyundai-seoul/floors/1F/graph
# {"floor":{...},"nodes":[234개],"edges":[282개]}
```

## 10. 이번 전환에서 삭제된 것

| 삭제 | 대체 |
|---|---|
| `app/routers/` (buildings.py, query.py) | `app/router/` (buildingRouter.py, queryRouter.py) |
| `app/services/building_service.py` | `app/service/buildingService.py` |
| `app/repositories/` (memory 구현 포함) | `app/repository/` (SQLite 구현) |
| `app/schemas/building.py` | (dict 응답으로 대체, 필요 시 response_model 도입) |
| `app/core/dependencies.py` | `app/FastAPIConfig.py` |
| `app/data/sample_building.json` | `app/data/navigation_1f.json` |
| `tests/unit/test_building_core.py` | `tests/unit/test_building_service.py` |

## 11. 함정 모음 (직접 밟았거나 밟기 쉬운 것)

1. **`async def` + sqlite3 금지.** 블로킹 IO 핸들러는 `def`. 이유는
   fastapi-request-flow.md 6단계.
2. **SQLite 커넥션 스레드 공유 금지.** 요청당 열고 닫기(yield dependency).
   전역 커넥션 + 스레드풀 = `check_same_thread` 에러.
3. **순환 import.** FastAPIConfig(DI 제공) ↔ router(DI 사용) 구조에서는
   라우터 import를 create_app() 안으로.
4. **Python 3.14에서 pip install 실패.** fastapi 0.115/pydantic 2.9/shapely 2.0
   고정 버전은 3.14용 휠이 없어 소스 빌드(MSVC 요구)로 떨어진다. CI와 같은
   **3.12로 venv**를 만들 것 (`py -3.12 -m venv .venv`).
5. **모듈명 대소문자.** `FastAPIConfig.py`, `sqliteBuildingRepository.py` 같은
   camelCase 모듈은 Windows(대소문자 무시)에서는 오타가 통과되지만 Linux CI에서는
   `ModuleNotFoundError`가 난다. import 문의 대소문자를 파일명과 정확히 맞출 것.
6. **DB 파일을 git에 넣지 않기.** `api/data/`는 .gitignore에 추가했다.
   ETL이 멱등이므로 언제든 재생성하면 된다.
