# M1-002 · FastAPI 백엔드 골격 생성

- **상태**: 구현 완료
- **마일스톤**: M1 · 프로젝트 초기 설정
- **컴포넌트**: api
- **GitHub**: #7
- **선행 이슈**: 없음 (M1-001과 병렬 가능)

## 한눈에

평면도 GeoJSON을 서빙하고, 이후 RAG 엔드포인트가 붙을 **최소 FastAPI 골격**을 만든다.
측위 연산은 클라이언트(온디바이스)가 하므로 백엔드 책임은 **① 정적 데이터 서빙 + ② (이후)RAG** 두 가지로 한정한다.

이미 만들어진 코드를 **그냥 돌려보고 싶다면** 이것만:

```powershell
cd api
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

→ http://localhost:8000/docs 가 뜨면 끝. 처음부터 직접 만들어보려면 아래 [따라하기](#따라하기)로.

---

## 따라하기

아래로 내려가며 파일을 하나씩 만든다. 순서는 **의존성 순서**(데이터 → 로직 → 경로 → 진입점)라,
각 단계에서 필요한 게 이미 앞 단계에 존재한다. 각 코드 블록은 그대로 붙여넣어도 동작한다.

만들 최종 구조:

```
api/
├── app/
│   ├── main.py          ← 진입점 (라우터 연결 + 미들웨어)
│   ├── routers/         ← URL → 함수 매핑
│   │   ├── buildings.py
│   │   └── query.py     (스텁)
│   ├── services/        ← 데이터 읽기·가공
│   │   └── building_service.py
│   ├── schemas/         ← 응답 데이터 구조 (Pydantic, 현재 미연결)
│   │   └── building.py
│   └── data/
│       └── sample_building.json
├── tests/test_main.py
├── requirements.txt
└── README.md
```

> 각 폴더가 "왜" 나뉘어 있는지, 코드가 "왜" 그렇게 생겼는지는 끝의 [더 알아보기](#더-알아보기-참고)에 모아뒀다. 일단은 만드는 데 집중.

### 0단계 — 폴더 만들기 + 가상환경 준비

프로젝트 루트(`Navigation`)에서 시작한다. 먼저 `api/`와 하위 폴더들을 만든다.

```powershell
# 1) api 폴더 생성 후 진입
mkdir api
cd api

# 2) 하위 폴더 한 번에 생성 (중간 폴더는 자동 생성됨)
mkdir app\routers, app\services, app\schemas, app\data, tests

# 3) 빈 __init__.py 5개 — 이 폴더들을 "파이썬 패키지"로 인식시켜
#    from app.routers import buildings 같은 import가 동작하게 한다
New-Item app\__init__.py, app\routers\__init__.py, app\services\__init__.py, app\schemas\__init__.py, tests\__init__.py -ItemType File

# 4) 가상환경 생성 + 활성화
python -m venv .venv
.venv\Scripts\activate
```

만들어진 뼈대 확인:

```powershell
tree /F app        # app\, app\routers\, app\services\, app\schemas\, app\data\, __init__.py 들이 보이면 OK
```

`(.venv)`가 터미널 앞에 붙으면 성공.
(`__init__.py`가 왜 필요한지, venv가 뭔지는 끝의 [더 알아보기](#더-알아보기-참고) 참고.)

### 1단계 — 의존성 — `requirements.txt`

**지금 골격에 실제로 필요한 것만** 버전 핀으로 적는다.

```
fastapi==0.115.*
uvicorn[standard]==0.32.*
pydantic==2.9.*
shapely==2.0.*
pytest
httpx
```

설치:

```powershell
pip install -r requirements.txt
```

- `httpx` — pytest의 `TestClient`가 내부적으로 요구해서 포함.
- `shapely`(공간 연산)는 **이 골격에선 아직 쓰지 않지만**, 곧 이어질 라우팅/공간 쿼리(**M2**)를 대비해 미리 넣어 둔다.

### 2단계 — 샘플 데이터 — `app/data/sample_building.json`

골격 검증용 최소 데이터. 건물 1개, 층 2개(`1`,`2`), 각 층에 복도(`LineString`) + POI(`Point`).
좌표는 실제 GPS(서울 시청 부근)를 쓴다 — GeoJSON 좌표는 **`[경도, 위도]` 순서**임에 주의.

```json
{
  "id": "bldg-001",
  "name": "데모 건물",
  "floors": [1, 2],
  "floor_data": {
    "1": {
      "type": "FeatureCollection",
      "features": [
        { "type": "Feature",
          "properties": { "type": "corridor", "name": "1층 복도" },
          "geometry": { "type": "LineString", "coordinates": [[126.9780, 37.5665], [126.9785, 37.5665]] } },
        { "type": "Feature",
          "properties": { "type": "poi", "name": "강의실 101", "id": "poi-101" },
          "geometry": { "type": "Point", "coordinates": [126.9782, 37.5665] } }
      ]
    },
    "2": {
      "type": "FeatureCollection",
      "features": [
        { "type": "Feature",
          "properties": { "type": "corridor", "name": "2층 복도" },
          "geometry": { "type": "LineString", "coordinates": [[126.9780, 37.5665], [126.9785, 37.5665]] } },
        { "type": "Feature",
          "properties": { "type": "poi", "name": "강의실 201", "id": "poi-201" },
          "geometry": { "type": "Point", "coordinates": [126.9782, 37.5665] } }
      ]
    }
  }
}
```

건물·층을 늘리거나 실제 평면도 좌표로 바꾸는 일은 **M2**에서.

### 3단계 — 비즈니스 로직 — `app/services/building_service.py`

JSON을 읽어 라우터에 넘겨줄 함수들. **데이터 소스를 나중에 DB로 바꿀 때 여기만 고친다.**

```python
import json
from pathlib import Path

_DATA_DIR = Path(__file__).parent.parent / "data"   # 어느 폴더에서 실행해도 app/data/ 를 가리킴

def _load_building() -> dict:                         # 앞의 _ = 이 파일 내부 전용 함수
    with open(_DATA_DIR / "sample_building.json", encoding="utf-8") as f:
        return json.load(f)

def get_all_buildings() -> list[dict]:                # 목록: 무거운 floor_data는 빼고 요약만
    b = _load_building()
    return [{"id": b["id"], "name": b["name"], "floors": b["floors"]}]

def get_building(building_id: str) -> dict | None:
    b = _load_building()
    if b["id"] != building_id:
        return None
    return {"id": b["id"], "name": b["name"], "floors": b["floors"]}

def get_floor_geojson(building_id: str, floor: int) -> dict | None:
    b = _load_building()
    if b["id"] != building_id:
        return None
    return b["floor_data"].get(str(floor))            # JSON 키는 문자열이라 str(floor)
```

- `get_all_buildings`/`get_building`은 목록·상세에서 **요약 필드(`id`,`name`,`floors`)만** 반환하고, 용량 큰 `floor_data`는 층 조회(`get_floor_geojson`)로 분리한다.
- 반환 타입 `dict | None` — 못 찾으면 `None`. 라우터가 이걸 보고 404로 바꾼다.

### 4단계 — 건물 엔드포인트 — `app/routers/buildings.py`

URL을 함수에 연결한다.

```python
from fastapi import APIRouter, HTTPException
from app.services import building_service

router = APIRouter(prefix="/buildings", tags=["buildings"])

@router.get("")
def list_buildings():
    return building_service.get_all_buildings()   # 목록은 요약만 (floor_data 제외)

@router.get("/{building_id}")
def get_building(building_id: str):
    result = building_service.get_building(building_id)
    if result is None:
        raise HTTPException(status_code=404, detail="Building not found")
    return result

@router.get("/{building_id}/floors/{floor}")
def get_floor(building_id: str, floor: int):
    result = building_service.get_floor_geojson(building_id, floor)
    if result is None:
        raise HTTPException(status_code=404, detail="Floor not found")
    return result
```

- `APIRouter(prefix="/buildings")` — 이 파일의 모든 경로 앞에 `/buildings` 자동 삽입.
- 경로의 `{building_id}`가 함수 파라미터로 자동 바인딩 (`/buildings/bldg-001` → `building_id="bldg-001"`).
- 데이터 처리는 service에 위임. `None`이면 404로 변환.

### 5단계 — 응답 스키마 — `app/schemas/building.py`

응답 데이터의 "모양"을 Pydantic으로 정의해 둔다. **지금은 정의만 하고 라우터엔 연결하지 않는다**
— 라우터는 여전히 dict를 그대로 반환한다. 응답 형식을 고정·검증해야 할 때 각 엔드포인트에
`response_model=...`로 이어 붙이면 된다.

```python
from pydantic import BaseModel
from typing import Any

class POI(BaseModel):           # 관심 지점 (강의실·화장실 등)
    id: str
    name: str
    type: str
    geometry: dict[str, Any]              # GeoJSON geometry (Point 등)
    properties: dict[str, Any] = {}       # 추가 속성 (기본값: 빈 dict)

class Floor(BaseModel):         # 층 = 층 번호 + GeoJSON 평면도
    floor: int
    geojson: dict[str, Any]

class Building(BaseModel):      # 건물 기본 정보 (목록·상세 응답용)
    id: str
    name: str
    floors: list[int]
```

> 왜 지금 연결하지 않나: dict를 그대로 돌려줘도 서버는 동작하고, `response_model`을 붙이면
> 응답이 모델과 어긋날 때 에러가 난다. 형식을 "고정"할 준비가 됐을 때 붙이는 게 안전하다.
> 즉 이 파일은 **다음 단계를 위한 밑그림**이다. (`query.py`의 요청 모델과 달리 아직 사용처가 없다.)

### 6단계 — 쿼리 스텁 — `app/routers/query.py`

RAG가 붙을 자리. 지금은 **받은 걸 그대로 돌려주는 스텁**만.

```python
from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter(prefix="/query", tags=["query"])

class DestinationRequest(BaseModel):   # 받을 JSON 모양 선언 → 자동 파싱·검증
    text: str
    building_id: str

class InfoRequest(BaseModel):
    text: str
    building_id: str

@router.post("/destination")
def query_destination(body: DestinationRequest):
    return {"status": "stub", "query": body.text, "result": None}

@router.post("/info")
def query_info(body: InfoRequest):
    return {"status": "stub", "query": body.text, "result": None}
```

- Body에 필드가 빠지거나 타입이 틀리면 FastAPI가 **자동으로 422** 반환.
- 이 핸들러를 처음부터 손으로 써보며 흐름을 익히고 싶으면 → [부록: 쿼리 핸들러 직접 써보기](#부록--쿼리-핸들러-직접-써보기).

### 7단계 — 진입점 — `app/main.py`

라우터들을 하나의 앱에 모은다.

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import buildings, query

app = FastAPI(title="Navigation API", version="0.1.0")

app.add_middleware(                       # 다른 출처(Flutter 앱)의 요청 허용
    CORSMiddleware,
    allow_origins=["*"],                  # 개발용 전체 허용. 배포 시 앱 주소로 교체
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(buildings.router)      # routers/ 파일의 모든 경로를 한 줄로 등록
app.include_router(query.router)

@app.get("/health")                       # 배포·헬스체크용
def health():
    return {"status": "ok"}
```

### 8단계 — 서버 실행

```powershell
uvicorn app.main:app --reload
```

`Uvicorn running on http://127.0.0.1:8000` 이 나오면 성공. (`--reload` = 코드 저장 시 자동 재시작, 개발용.)

브라우저로 확인:

- http://localhost:8000/health → `{"status": "ok"}`
- http://localhost:8000/buildings → 건물 목록
- http://localhost:8000/docs → Swagger UI (전체 엔드포인트, 여기서 바로 테스트 가능)

### 9단계 — 테스트 — `tests/test_main.py`

```python
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_health():
    assert client.get("/health").json() == {"status": "ok"}

def test_list_buildings():
    assert client.get("/buildings").status_code == 200

def test_get_floor():
    assert client.get("/buildings/bldg-001/floors/1").status_code == 200

def test_query_destination_stub():
    r = client.post("/query/destination", json={"text": "101호 어디야?", "building_id": "bldg-001"})
    assert r.json()["status"] == "stub"
```

실행 (서버를 끄지 않아도 됨, 새 터미널이면 venv 활성화 후):

```powershell
pytest
```

전부 통과하면 골격 완성. **마지막으로 `api/README.md`에 실행법·엔드포인트 표를 적어둔다.**

---

## 검증 (수용 기준)

전부 ✅ 면 이슈 완료:

- [ ] `uvicorn app.main:app --reload`로 서버가 뜬다.
- [ ] `GET /health` → `200 OK`, `{"status":"ok"}`
- [ ] `GET /buildings` → 샘플 건물 목록
- [ ] `GET /buildings/{id}/floors/{floor}` → 유효한 GeoJSON
- [ ] `/docs`(Swagger UI)에 모든 엔드포인트가 보인다.
- [ ] `pytest` 통과

빠른 명령 확인:

```powershell
curl http://localhost:8000/health
curl http://localhost:8000/buildings
```

### 작업 종료 / 다음에 재개

```powershell
deactivate                  # 종료

# 재개 시 (venv는 한 번만 만들면 됨)
cd api
.venv\Scripts\activate
uvicorn app.main:app --reload
```

---

## 부록 — 쿼리 핸들러 직접 써보기

`/query/destination`을 처음부터 손으로 써보며 "요청 → 함수 → 응답" 흐름을 익히는 연습. (실제 RAG 로직은 09 후속 이슈.)

**1) 받을 JSON 모양을 먼저 상상한다**

```json
{ "text": "101호 어디야?", "building_id": "bldg-001" }
```

**2) 그 모양을 Pydantic 클래스로 옮긴다** (필드 이름·타입만)

```python
from pydantic import BaseModel

class DestinationRequest(BaseModel):
    text: str          # 사용자가 입력한 질문
    building_id: str   # 어느 건물에 대한 질문인지
```

**3) 그 클래스를 파라미터 타입으로 받는 함수를 만든다** (FastAPI가 JSON→클래스 자동 변환)

```python
@router.post("/destination")
def query_destination(body: DestinationRequest):
    return { "status": "stub", "query": body.text, "result": None }   # 받은 질문을 메아리처럼 반환
```

**4) `/docs`에서 직접 호출해 확인한다**

`POST /query/destination` → **Try it out** → 1)의 JSON 입력 → 실행. 아래가 나오면 성공:

```json
{ "status": "stub", "query": "101호 어디야?", "result": null }
```

`result`가 지금은 `null`이다. **09 후속 이슈**에서 이 자리에 "찾은 목적지 좌표"를 채운다.
즉 지금 할 일은 **입출력 통로만 뚫어두는 것**.

---

## 더 알아보기 (참고)

따라하기엔 필요 없지만 "왜 이렇게 나눴나"가 궁금할 때.

### 요청 → 응답이 흐르는 길

요청은 위에서 아래로 계층을 타고 내려가 데이터에 닿고, 응답은 같은 길을 거꾸로 올라온다.
(아래 다이어그램은 GitHub에서 그림으로 렌더된다.)

```mermaid
sequenceDiagram
    participant F as Flutter 앱
    participant M as main.py
    participant R as routers/buildings.py
    participant S as services/<br/>building_service.py
    participant D as data/<br/>sample_building.json

    F->>M: GET /buildings/bldg-001/floors/1
    M->>R: 경로 매칭 → get_floor()
    R->>S: get_floor_geojson("bldg-001", 1)
    S->>D: JSON 파일 읽기
    D-->>S: dict
    S-->>R: 층 GeoJSON 또는 None
    alt 데이터 있음
        R-->>F: 200 OK + GeoJSON
    else None
        R-->>F: 404 Not Found
    end
```

| 역할 | 폴더 | 이걸 바꾸는 경우 |
|------|------|------------------|
| URL 라우팅 | `routers/` | API 경로를 추가·변경할 때 |
| 비즈니스 로직 | `services/` | 데이터 소스를 JSON→DB로 교체할 때 |

한 파일이 한 가지 역할만 담당 → 수정 범위가 좁고 다른 부분에 영향이 없다.

### 데이터를 어떻게 관리하나 (교체 지점)

핵심은 **데이터 소스를 만지는 곳이 `services/` 한 군데뿐**이라는 점.
지금은 정적 JSON을 읽지만, 나중에 DB로 바꿔도 라우터·진입점은 손대지 않는다 —
`building_service.py`의 읽기 함수만 교체하면 된다.

```mermaid
flowchart TD
    C([Flutter 앱]) -->|HTTP 요청| R[routers/<br/>URL → 함수]
    R -->|함수 호출| S[services/<br/>building_service.py]
    S -->|dict 반환| R
    R -->|JSON 응답| C

    S -. 지금 읽는 곳 .-> J[(sample_building.json)]
    S -. 나중에 이것만 교체 .-> DB[(데이터베이스)]

    style S fill:#E1F5EE,stroke:#0F6E56
    style J fill:#FAEEDA,stroke:#854F0B
    style DB fill:#F1EFE8,stroke:#5F5E5A,stroke-dasharray:4
```

> `services/`가 데이터 소스와 나머지 코드 사이의 **이음새(seam)** 역할. 이 한 겹 덕분에 "JSON으로 시작했다가 나중에 DB로 확장"이 라우터를 건드리지 않고 가능하다.

### 가상환경(venv)은 왜 쓰나

`.venv` 폴더 안에 **이 프로젝트 전용** Python 패키지가 설치된다.
프로젝트마다 필요한 패키지 버전이 달라서, 전역 Python에 깔면 다른 프로젝트와 충돌이 난다.

### `__init__.py`는 왜 필요한가

폴더(`app/`, `routers/` 등)를 **파이썬 패키지**로 인식시키는 표식 파일. 내용은 비어 있어도 된다.
이게 있어야 `from app.routers import buildings` 같은 `import`가 동작한다. 없으면 "모듈을 못 찾는다"는 에러가 난다.

### 코드에서 헷갈리기 쉬운 부분

- `app.add_middleware(CORSMiddleware, allow_origins=["*"], ...)` — Flutter 앱은 서버와 **다른 출처**라 브라우저 보안정책상 기본 차단됨. CORS가 이를 허용. 개발엔 `*`, 배포 시 앱 주소로 교체.
- `_DATA_DIR = Path(__file__).parent.parent / "data"` — `__file__`(현재 파일) → `.parent.parent`(`app/`) → `/ "data"`(`app/data/`). 실행 위치와 무관하게 항상 올바른 경로.
- `str(floor)` — `floor`는 정수(`1`)지만 JSON 키는 문자열(`"1"`)이라 변환 필요.
- 함수 앞 `_` (예 `_load_building`) — 이 파일 내부에서만 쓰는 private 함수라는 관례.

---

## 이 이슈 범위 밖 (후속 이슈로 분리)

골격 단계엔 불필요해 **의도적으로 제외**한 항목. 실제로 필요해지는 시점의 이슈에서 추가한다.

| 항목 | 이유 | 진행 시점 |
|------|------|-----------|
| `Dockerfile` | 로컬 개발만으로 충분 | 컨테이너 배포 준비 시점 |
| RAG 실제 구현 (sentence-transformers/FAISS) | 골격을 무겁게 만듦. 현재 `/query/*`는 스텁 | **09 문서 후속 이슈** |

> **현재 "정의만 됐고 아직 안 쓰는" 것들** (코드엔 있으나 미연결):
> - `app/schemas/building.py`(`Building`/`Floor`/`POI`) — 응답 모델. 라우터가 dict를 반환 중이라 아직 `response_model=`로 연결 안 됨. 응답 형식을 고정할 때 연결.
> - `shapely` 의존성 — 설치는 돼 있으나 코드에서 아직 호출 안 함. 공간 연산이 필요한 **M2**부터 사용.
>
> 반면 `query.py`의 `DestinationRequest`/`InfoRequest`는 요청 Body 검증에 **실제로 쓰인다**.

## 파일 (Files)

```
api/requirements.txt
api/app/main.py
api/app/routers/buildings.py
api/app/routers/query.py          (스텁)
api/app/services/building_service.py
api/app/schemas/building.py       (정의만, 라우터 미연결)
api/app/data/sample_building.json
api/tests/test_main.py
api/README.md
```

## 메모

- RAG 엔드포인트는 **스텁만** 둔다. sentence-transformers/FAISS 설치는 09 후속 이슈로 분리해 골격이 무거워지지 않게 한다.
- 1차 데이터 소스는 정적 GeoJSON 파일. DB는 확장 시점에 도입한다(06 문서).
- 참고: [06-tech-stack.md](../../docs/research/06-tech-stack.md) · [09-rag-integration.md](../../docs/research/09-rag-integration.md)
