# API Refactor 코드 레퍼런스 (전체 코드 + 상세 주석)

> SQLite 전환 후 api/ 각 디렉토리 파일의 **전체 코드**를 상세 주석과 함께 기록한 문서.
> 현재 저장소의 py 파일들은 0바이트 빈 껍데기 상태이므로, 이 문서의 코드를 그대로
> 채워 넣으면 된다. 개념 설명과 단계별 절차는 `sqlite-migration-guide.md` 참고.

## 0. 작성 전 체크리스트

### 빠져 있는 `__init__.py` 를 먼저 만들 것

현재 트리에는 `__init__.py`가 하나도 없다. **이 파일들이 없으면 `from app.domain...`
import가 전부 깨진다.** 아래 7개를 전부 빈 파일로 생성한다 (내용 없음).

```text
api/app/__init__.py
api/app/domain/__init__.py
api/app/repository/__init__.py
api/app/router/__init__.py
api/app/service/__init__.py
api/scripts/__init__.py          # tests가 scripts.load_dataset을 import하는 데 필요
api/tests/__init__.py
api/tests/unit/__init__.py
api/tests/integration/__init__.py
```

### 권장 작성 순서 (의존 방향 역순)

```text
① scripts/load_dataset.py   (ETL — 다른 코드에 의존 없음)
② app/domain/building.py    (모두가 의존하는 값 객체)
③ app/repository/BuildingRepository.py      (인터페이스)
④ app/repository/sqliteBuildingRepository.py (구현)
⑤ app/service/buildingService.py
⑥ app/FastAPIConfig.py      (DI 조립)
⑦ app/router/buildingRouter.py, queryRouter.py
⑧ app/main.py
⑨ tests/conftest.py → tests/unit → tests/integration
```

### 완성 후 검증

```bash
cd api
python scripts/load_dataset.py                     # buildings 1 / nodes 234 / edges 282 / stores 61 / pois 47
python -m pytest tests/unit tests/integration -q   # 20 passed
uvicorn app.main:app --reload                      # http://localhost:8000/docs
```

---

## 1. `scripts/load_dataset.py` — ETL (JSON → SQLite)

역할: 가공된 실데이터 `app/data/navigation_1f.json`을 읽어 `data/navigation.db`를
생성한다. DROP 후 재생성이라 몇 번을 실행해도 같은 결과(멱등). 함수
`load_navigation_db`는 테스트 conftest가 import해서 임시 DB를 만들 때도 쓰인다.

```python
"""
scripts/load_dataset.py
=======================
가공된 실데이터(navigation_1f.json)를 SQLite(navigation.db)에 적재하는 ETL.

- 앱 기동과 분리된 1회성 스크립트. 실행할 때마다 테이블을 DROP 후 재생성한다(멱등).
- 스키마 근거: docs/api-design.md, 데이터 근거: docs/dataset-analysis.md
- 폴리곤/폴리라인 같은 가변 길이 기하는 JSON 문자열(TEXT) 컬럼에 저장한다.

실행 (api/ 디렉토리에서):
  python scripts/load_dataset.py                 # 기본 경로 사용
  python scripts/load_dataset.py --db data/navigation.db
"""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path

# 이 파일 기준으로 api/ 루트를 찾는다. 어디서 실행해도 경로가 안 깨진다.
API_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_JSON = API_ROOT / "app" / "data" / "navigation_1f.json"
DEFAULT_DB = API_ROOT / "data" / "navigation.db"

# 스키마 정의. DROP -> CREATE 순서라 재실행해도 항상 같은 상태가 된다.
DDL = """
PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS pois;
DROP TABLE IF EXISTS stores;
DROP TABLE IF EXISTS edges;
DROP TABLE IF EXISTS nodes;
DROP TABLE IF EXISTS floors;
DROP TABLE IF EXISTS buildings;

CREATE TABLE buildings (
    id                TEXT PRIMARY KEY,
    name              TEXT NOT NULL,
    area_m2           REAL,
    perimeter_m       REAL,
    footprint_local_m TEXT              -- [{"x":..,"y":..}, ...] JSON
);

CREATE TABLE floors (
    id          TEXT PRIMARY KEY,
    building_id TEXT NOT NULL REFERENCES buildings(id),
    name        TEXT NOT NULL,          -- 예: 1F
    level       INTEGER NOT NULL,       -- 정렬용 층 순번
    UNIQUE (building_id, name)
);

CREATE TABLE nodes (
    id       TEXT PRIMARY KEY,
    floor_id TEXT NOT NULL REFERENCES floors(id),
    type     TEXT NOT NULL,             -- corridor|junction|store_entrance|escalator|elevator|dead_end
    name     TEXT,
    x_m      REAL NOT NULL,             -- local_m 좌표 (top-left, y아래)
    y_m      REAL NOT NULL,
    lat      REAL,                      -- WGS84 (provisional, 외부 지도 연동용)
    lng      REAL,
    source_x REAL,                      -- 도면 원본 좌표 (재보정 대비 보존)
    source_y REAL
);
CREATE INDEX idx_nodes_floor ON nodes(floor_id);
CREATE INDEX idx_nodes_type  ON nodes(type);

CREATE TABLE edges (
    id            TEXT PRIMARY KEY,
    floor_id      TEXT NOT NULL REFERENCES floors(id),
    from_node_id  TEXT NOT NULL REFERENCES nodes(id),
    to_node_id    TEXT NOT NULL REFERENCES nodes(id),
    length_m      REAL NOT NULL,
    bidirectional INTEGER NOT NULL DEFAULT 1,
    geometry      TEXT                  -- local_m polyline JSON
);
CREATE INDEX idx_edges_floor ON edges(floor_id);
CREATE INDEX idx_edges_from  ON edges(from_node_id);
CREATE INDEX idx_edges_to    ON edges(to_node_id);

CREATE TABLE stores (
    id               TEXT PRIMARY KEY,
    floor_id         TEXT NOT NULL REFERENCES floors(id),
    name             TEXT NOT NULL,
    centroid_x_m     REAL NOT NULL,
    centroid_y_m     REAL NOT NULL,
    entrance_x_m     REAL,
    entrance_y_m     REAL,
    entrance_node_id TEXT REFERENCES nodes(id),
    polygon          TEXT               -- local_m Polygon JSON
);
CREATE INDEX idx_stores_floor ON stores(floor_id);
CREATE INDEX idx_stores_name  ON stores(name);

CREATE TABLE pois (
    id             TEXT PRIMARY KEY,
    floor_id       TEXT NOT NULL REFERENCES floors(id),
    type           TEXT NOT NULL,
    name           TEXT,
    x_m            REAL NOT NULL,
    y_m            REAL NOT NULL,
    linked_node_id TEXT REFERENCES nodes(id)
);
CREATE INDEX idx_pois_floor ON pois(floor_id);
CREATE INDEX idx_pois_type  ON pois(type);
"""


def load_navigation_db(
    json_path: Path = DEFAULT_JSON, db_path: Path = DEFAULT_DB
) -> dict[str, int]:
    """navigation JSON을 읽어 SQLite로 적재하고 테이블별 건수를 반환한다."""
    with open(json_path, encoding="utf-8") as f:
        data = json.load(f)

    building = data["building"]
    floor = building["floor"]
    building_id = building["id"]
    floor_id = floor["id"]

    db_path = Path(db_path)
    db_path.parent.mkdir(parents=True, exist_ok=True)  # data/ 폴더 없으면 생성

    conn = sqlite3.connect(db_path)
    try:
        conn.executescript(DDL)  # DROP + CREATE (멱등의 핵심)

        conn.execute(
            "INSERT INTO buildings (id, name, area_m2, perimeter_m, footprint_local_m)"
            " VALUES (?, ?, ?, ?, ?)",
            (
                building_id,
                building["name"],
                building["area_m2"],
                building["perimeter_m"],
                # 폴리곤 리스트는 JSON 문자열로 직렬화해서 TEXT 컬럼에 저장
                json.dumps(building["footprint_local_m"], ensure_ascii=False),
            ),
        )
        conn.execute(
            "INSERT INTO floors (id, building_id, name, level) VALUES (?, ?, ?, ?)",
            (floor_id, building_id, floor["name"], floor["level"]),
        )
        # 대량 INSERT는 executemany — 한 건씩 execute보다 훨씬 빠르다
        conn.executemany(
            "INSERT INTO nodes (id, floor_id, type, name, x_m, y_m, lat, lng, source_x, source_y)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                (
                    n["id"],
                    floor_id,
                    n["type"],
                    n.get("name"),          # name이 없는 노드도 있으므로 .get
                    n["position"]["local_m"]["x"],
                    n["position"]["local_m"]["y"],
                    n["position"]["wgs84"]["lat"],
                    n["position"]["wgs84"]["lng"],
                    n["position"]["source"]["x"],
                    n["position"]["source"]["y"],
                )
                for n in data["nodes"]
            ],
        )
        conn.executemany(
            "INSERT INTO edges (id, floor_id, from_node_id, to_node_id, length_m, bidirectional, geometry)"
            " VALUES (?, ?, ?, ?, ?, ?, ?)",
            [
                (
                    e["id"],
                    floor_id,
                    e["from"],
                    e["to"],
                    e["length_m"],
                    1 if e["bidirectional"] else 0,  # SQLite에는 bool이 없어 0/1
                    json.dumps(e["geometry_local_m"]),
                )
                for e in data["edges"]
            ],
        )
        conn.executemany(
            "INSERT INTO stores (id, floor_id, name, centroid_x_m, centroid_y_m,"
            " entrance_x_m, entrance_y_m, entrance_node_id, polygon)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                (
                    s["id"],
                    floor_id,
                    s["name"],
                    s["centroid"]["local_m"]["x"],
                    s["centroid"]["local_m"]["y"],
                    # entrance가 없는 매장 대비 — None이면 NULL로 들어간다
                    s["entrance_local_m"]["x"] if s["entrance_local_m"] else None,
                    s["entrance_local_m"]["y"] if s["entrance_local_m"] else None,
                    s["entrance_node_id"],
                    json.dumps(s["polygon_local_m"]) if s["polygon_local_m"] else None,
                )
                for s in data["stores"]
            ],
        )
        conn.executemany(
            "INSERT INTO pois (id, floor_id, type, name, x_m, y_m, linked_node_id)"
            " VALUES (?, ?, ?, ?, ?, ?, ?)",
            [
                (
                    p["id"],
                    floor_id,
                    p["type"],
                    p.get("name"),
                    p["position"]["local_m"]["x"],
                    p["position"]["local_m"]["y"],
                    p.get("linked_node_id"),
                )
                for p in data["pois"]
            ],
        )
        conn.commit()

        # 적재 결과 요약 — CLI 출력과 테스트 검증에 사용
        counts = {
            table: conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            for table in ("buildings", "floors", "nodes", "edges", "stores", "pois")
        }
        return counts
    finally:
        conn.close()  # 예외가 나도 커넥션은 반드시 닫는다


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    args = parser.parse_args()

    result = load_navigation_db(args.json, args.db)
    print(f"적재 완료: {args.db}")
    for table, count in result.items():
        print(f"  {table}: {count}")
```

**포인트**
- SQL 값은 전부 `?` 바인딩. f-string으로 SQL을 조립하면 인젝션 구멍.
- `source_x/source_y`를 저장하는 이유: 현재 WGS84는 provisional이라, 건물 외곽을
  재추출하면 DB의 원본 좌표만으로 재계산할 수 있게 하기 위함.

---

## 2. `app/domain/building.py` — 도메인 값 객체

역할: 계층 간에 오가는 순수 데이터. `frozen=True`라 생성 후 수정 불가(실수로
service에서 값을 바꾸는 사고 방지). FastAPI/sqlite3 를 전혀 모른다.

```python
"""
app/domain/building.py
======================
순수 도메인 데이터 객체.

FastAPI/sqlite3 어디에도 의존하지 않는 불변 dataclass만 둔다.
비즈니스 로직은 Service, 저장/조회는 Repository가 담당한다.
좌표 단위는 모두 building-local meter(local_m, top-left 원점, y아래)다.
"""

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Building:
    id: str
    name: str
    area_m2: float
    perimeter_m: float
    footprint_local_m: list[dict] = field(default_factory=list)  # [{"x","y"}, ...]


@dataclass(frozen=True)
class Floor:
    id: str
    building_id: str
    name: str  # 예: "1F"
    level: int


@dataclass(frozen=True)
class Node:
    id: str
    floor_id: str
    type: str  # corridor | junction | store_entrance | escalator | elevator | dead_end
    name: str | None
    x_m: float
    y_m: float
    lat: float | None  # WGS84 (provisional)
    lng: float | None


@dataclass(frozen=True)
class Edge:
    id: str
    floor_id: str
    from_node_id: str
    to_node_id: str
    length_m: float
    bidirectional: bool
    geometry_local_m: list[dict] = field(default_factory=list)


@dataclass(frozen=True)
class Store:
    id: str
    floor_id: str
    name: str
    centroid_x_m: float
    centroid_y_m: float
    entrance_node_id: str | None
    polygon_local_m: list[dict] | None = None


@dataclass(frozen=True)
class Poi:
    id: str
    floor_id: str
    type: str  # elevator | escalator | toilet | exit | ...
    name: str | None
    x_m: float
    y_m: float
    linked_node_id: str | None
```

**포인트**
- 가변 기본값(list)은 `field(default_factory=list)`. `= []`로 쓰면 모든 인스턴스가
  같은 리스트를 공유하는 파이썬 고전 버그.
- JPA Entity처럼 getter/setter를 두지 않는다 — 불변이므로 필요 없음.

---

## 3. `app/repository/BuildingRepository.py` — 저장소 인터페이스

역할: Service가 의존하는 계약. `typing.Protocol`은 Spring interface 대응인데,
구현 클래스가 `implements`를 선언할 필요 없이 **메서드 시그니처만 맞으면**
구현체로 인정된다(구조적 타이핑).

```python
"""
app/repository/BuildingRepository.py
====================================
저장소 인터페이스.

Python에서는 Spring의 interface 대신 typing.Protocol로 메서드 계약을 표현한다.
Service는 이 Protocol에만 의존하므로 구현체(SQLite ↔ 인메모리)를 자유롭게
교체할 수 있다. "없음"은 예외가 아니라 None/빈 리스트로 표현한다.
"""

from typing import Protocol

from app.domain.building import Building, Edge, Floor, Node, Poi, Store


class BuildingRepository(Protocol):
    def find_all_buildings(self) -> list[Building]:
        """저장된 모든 건물을 반환한다."""
        ...

    def find_building_by_id(self, building_id: str) -> Building | None:
        """building_id에 해당하는 건물. 없으면 None."""
        ...

    def find_floors_by_building(self, building_id: str) -> list[Floor]:
        """건물의 층 목록을 level 오름차순으로 반환한다."""
        ...

    def find_floor_by_name(self, building_id: str, floor_name: str) -> Floor | None:
        """건물의 특정 층(예: '1F'). 없으면 None."""
        ...

    def find_nodes_by_floor(self, floor_id: str) -> list[Node]:
        """층의 길찾기 그래프 노드 목록."""
        ...

    def find_edges_by_floor(self, floor_id: str) -> list[Edge]:
        """층의 길찾기 그래프 엣지 목록."""
        ...

    def find_stores_by_floor(self, floor_id: str) -> list[Store]:
        """층의 매장 목록."""
        ...

    def find_pois_by_floor(self, floor_id: str) -> list[Poi]:
        """층의 POI(엘리베이터/화장실/출구 등) 목록."""
        ...

    def search_stores(self, building_id: str, query: str) -> list[Store]:
        """건물 전체에서 이름에 query가 포함된 매장 검색."""
        ...
```

---

## 4. `app/repository/sqliteBuildingRepository.py` — SQLite 구현체

역할: SQL 실행 + row → domain 매핑. 커넥션은 **주입받기만** 한다(수명 관리는
FastAPIConfig의 `get_db` 책임).

```python
"""
app/repository/sqliteBuildingRepository.py
==========================================
BuildingRepository의 SQLite 구현체.

- 생성자로 sqlite3.Connection을 주입받는다. 커넥션 수명은 FastAPIConfig의
  get_db(yield dependency)가 관리한다 — 요청마다 열고 응답 후 닫는다.
  (def 핸들러는 스레드풀에서 실행되므로 커넥션을 스레드 간 공유하면 안 됨)
- row → domain 매핑만 담당한다. 비즈니스 판단은 Service의 몫.
- JSON TEXT 컬럼(footprint/polygon/geometry)은 여기서 json.loads로 복원한다.
"""

import json
import sqlite3

from app.domain.building import Building, Edge, Floor, Node, Poi, Store


class SqliteBuildingRepository:
    def __init__(self, conn: sqlite3.Connection):
        self._conn = conn

    # --- buildings ---

    def find_all_buildings(self) -> list[Building]:
        rows = self._conn.execute(
            "SELECT id, name, area_m2, perimeter_m, footprint_local_m FROM buildings"
        ).fetchall()
        return [self._to_building(r) for r in rows]

    def find_building_by_id(self, building_id: str) -> Building | None:
        row = self._conn.execute(
            "SELECT id, name, area_m2, perimeter_m, footprint_local_m FROM buildings"
            " WHERE id = ?",
            (building_id,),
        ).fetchone()
        return self._to_building(row) if row else None

    # --- floors ---

    def find_floors_by_building(self, building_id: str) -> list[Floor]:
        rows = self._conn.execute(
            "SELECT id, building_id, name, level FROM floors"
            " WHERE building_id = ? ORDER BY level",
            (building_id,),
        ).fetchall()
        # 컬럼명과 dataclass 필드명이 같아서 dict 언패킹으로 바로 매핑된다
        return [Floor(**dict(r)) for r in rows]

    def find_floor_by_name(self, building_id: str, floor_name: str) -> Floor | None:
        row = self._conn.execute(
            "SELECT id, building_id, name, level FROM floors"
            " WHERE building_id = ? AND name = ?",
            (building_id, floor_name),
        ).fetchone()
        return Floor(**dict(row)) if row else None

    # --- graph ---

    def find_nodes_by_floor(self, floor_id: str) -> list[Node]:
        rows = self._conn.execute(
            "SELECT id, floor_id, type, name, x_m, y_m, lat, lng FROM nodes"
            " WHERE floor_id = ?",
            (floor_id,),
        ).fetchall()
        return [Node(**dict(r)) for r in rows]

    def find_edges_by_floor(self, floor_id: str) -> list[Edge]:
        rows = self._conn.execute(
            "SELECT id, floor_id, from_node_id, to_node_id, length_m, bidirectional,"
            " geometry FROM edges WHERE floor_id = ?",
            (floor_id,),
        ).fetchall()
        return [
            Edge(
                id=r["id"],
                floor_id=r["floor_id"],
                from_node_id=r["from_node_id"],
                to_node_id=r["to_node_id"],
                length_m=r["length_m"],
                bidirectional=bool(r["bidirectional"]),  # 0/1 → bool 복원
                geometry_local_m=json.loads(r["geometry"]) if r["geometry"] else [],
            )
            for r in rows
        ]

    # --- stores / pois ---

    def find_stores_by_floor(self, floor_id: str) -> list[Store]:
        rows = self._conn.execute(
            "SELECT id, floor_id, name, centroid_x_m, centroid_y_m, entrance_node_id,"
            " polygon FROM stores WHERE floor_id = ?",
            (floor_id,),
        ).fetchall()
        return [self._to_store(r) for r in rows]

    def find_pois_by_floor(self, floor_id: str) -> list[Poi]:
        rows = self._conn.execute(
            "SELECT id, floor_id, type, name, x_m, y_m, linked_node_id FROM pois"
            " WHERE floor_id = ?",
            (floor_id,),
        ).fetchall()
        return [Poi(**dict(r)) for r in rows]

    def search_stores(self, building_id: str, query: str) -> list[Store]:
        # 층을 거쳐 건물로 join — stores에는 building_id가 없기 때문
        rows = self._conn.execute(
            "SELECT s.id, s.floor_id, s.name, s.centroid_x_m, s.centroid_y_m,"
            " s.entrance_node_id, s.polygon"
            " FROM stores s JOIN floors f ON s.floor_id = f.id"
            " WHERE f.building_id = ? AND s.name LIKE ?",
            (building_id, f"%{query}%"),  # LIKE 패턴도 값 바인딩으로
        ).fetchall()
        return [self._to_store(r) for r in rows]

    # --- 매핑 ---

    @staticmethod
    def _to_building(row: sqlite3.Row) -> Building:
        return Building(
            id=row["id"],
            name=row["name"],
            area_m2=row["area_m2"],
            perimeter_m=row["perimeter_m"],
            footprint_local_m=json.loads(row["footprint_local_m"])
            if row["footprint_local_m"]
            else [],
        )

    @staticmethod
    def _to_store(row: sqlite3.Row) -> Store:
        return Store(
            id=row["id"],
            floor_id=row["floor_id"],
            name=row["name"],
            centroid_x_m=row["centroid_x_m"],
            centroid_y_m=row["centroid_y_m"],
            entrance_node_id=row["entrance_node_id"],
            polygon_local_m=json.loads(row["polygon"]) if row["polygon"] else None,
        )
```

**포인트**
- `row["컬럼명"]` 접근은 `get_db`에서 `conn.row_factory = sqlite3.Row`를 설정해야 동작.
- `implements BuildingRepository` 같은 선언이 없어도 Protocol의 시그니처와 일치하므로
  타입 체크를 통과한다.

---

## 5. `app/service/buildingService.py` — 비즈니스 로직

역할: repository에서 domain을 받아 API 응답 dict로 가공. HTTP를 모르고
(HTTPException import 금지), "없음"은 None으로 알린다.

```python
"""
app/service/buildingService.py
==============================
건물/층/그래프/매장 비즈니스 로직.

- BuildingRepository 인터페이스(Protocol)에만 의존한다. HTTP를 모르며
  HTTPException을 import하지 않는다. "없음"은 None 반환 — router가 404로 번역.
- 도메인 객체를 API 응답용 dict로 가공하는 책임을 가진다.
"""

from typing import Any

from app.domain.building import Building, Edge, Node, Poi, Store
from app.repository.BuildingRepository import BuildingRepository


class BuildingService:
    def __init__(self, building_repository: BuildingRepository):
        self.building_repository = building_repository

    def get_all_buildings(self) -> list[dict[str, Any]]:
        """전체 건물 목록. footprint 같은 무거운 필드는 제외한 요약."""
        return [
            self._to_building_summary(b)
            for b in self.building_repository.find_all_buildings()
        ]

    def get_building(self, building_id: str) -> dict[str, Any] | None:
        """건물 상세. footprint 포함. 없으면 None."""
        building = self.building_repository.find_building_by_id(building_id)
        if building is None:
            return None
        summary = self._to_building_summary(building)
        summary["area_m2"] = building.area_m2
        summary["perimeter_m"] = building.perimeter_m
        summary["footprint_local_m"] = building.footprint_local_m
        return summary

    def get_floor_map(self, building_id: str, floor_name: str) -> dict[str, Any] | None:
        """층 지도 데이터(footprint + 매장 폴리곤 + POI). 렌더링용."""
        floor = self.building_repository.find_floor_by_name(building_id, floor_name)
        if floor is None:
            return None
        building = self.building_repository.find_building_by_id(building_id)
        return {
            "floor": {"id": floor.id, "name": floor.name, "level": floor.level},
            "footprint_local_m": building.footprint_local_m if building else [],
            "stores": [
                self._to_store_dict(s)
                for s in self.building_repository.find_stores_by_floor(floor.id)
            ],
            "pois": [
                self._to_poi_dict(p)
                for p in self.building_repository.find_pois_by_floor(floor.id)
            ],
        }

    def get_floor_graph(self, building_id: str, floor_name: str) -> dict[str, Any] | None:
        """층 길찾기 그래프(nodes + edges). A*/Dijkstra 입력용."""
        floor = self.building_repository.find_floor_by_name(building_id, floor_name)
        if floor is None:
            return None
        return {
            "floor": {"id": floor.id, "name": floor.name},
            "nodes": [
                self._to_node_dict(n)
                for n in self.building_repository.find_nodes_by_floor(floor.id)
            ],
            "edges": [
                self._to_edge_dict(e)
                for e in self.building_repository.find_edges_by_floor(floor.id)
            ],
        }

    def search_stores(self, building_id: str, query: str) -> list[dict[str, Any]] | None:
        """건물 내 매장 이름 검색. 건물이 없으면 None(→404), 결과 없으면 빈 리스트."""
        if self.building_repository.find_building_by_id(building_id) is None:
            return None
        return [
            self._to_store_dict(s)
            for s in self.building_repository.search_stores(building_id, query)
        ]

    # --- dict 변환 ---

    def _to_building_summary(self, building: Building) -> dict[str, Any]:
        floors = self.building_repository.find_floors_by_building(building.id)
        return {
            "id": building.id,
            "name": building.name,
            "floors": [f.name for f in floors],
        }

    @staticmethod
    def _to_node_dict(node: Node) -> dict[str, Any]:
        return {
            "id": node.id,
            "type": node.type,
            "name": node.name,
            "x_m": node.x_m,
            "y_m": node.y_m,
            "lat": node.lat,
            "lng": node.lng,
        }

    @staticmethod
    def _to_edge_dict(edge: Edge) -> dict[str, Any]:
        return {
            "id": edge.id,
            "from": edge.from_node_id,   # API에서는 짧은 이름 사용
            "to": edge.to_node_id,
            "length_m": edge.length_m,
            "bidirectional": edge.bidirectional,
            "geometry_local_m": edge.geometry_local_m,
        }

    @staticmethod
    def _to_store_dict(store: Store) -> dict[str, Any]:
        return {
            "id": store.id,
            "floor_id": store.floor_id,
            "name": store.name,
            "centroid_local_m": {"x": store.centroid_x_m, "y": store.centroid_y_m},
            "entrance_node_id": store.entrance_node_id,
            "polygon_local_m": store.polygon_local_m,
        }

    @staticmethod
    def _to_poi_dict(poi: Poi) -> dict[str, Any]:
        return {
            "id": poi.id,
            "type": poi.type,
            "name": poi.name,
            "position_local_m": {"x": poi.x_m, "y": poi.y_m},
            "linked_node_id": poi.linked_node_id,
        }
```

**포인트**
- "건물 없음(None → 404)"과 "검색 결과 없음(빈 리스트 → 200 [])"을 구분한다.
- 목록 응답에는 footprint를 빼고 상세 응답에만 넣는다 — payload 크기 관리.

---

## 6. `app/FastAPIConfig.py` — 설정 + DI + 앱 팩토리

역할: Spring의 application.yml + @Configuration + DI 컨테이너.
DI 체인: `get_db`(요청당 커넥션) → `get_building_repository` → `get_building_service`.

```python
"""
app/FastAPIConfig.py
====================
앱 조립(설정 + DI + 팩토리)을 한 곳에서 담당한다. Spring으로 치면
application.yml + @Configuration + DI 컨테이너 역할.

구성:
  - 설정: DB 경로를 환경변수 NAV_DB_PATH로 주입 (기본값 api/data/navigation.db)
  - DI 체인: get_db(요청당 SQLite 커넥션) → get_building_repository → get_building_service
  - create_app(): FastAPI 인스턴스 생성, CORS, 라우터 등록, /health

주의:
  - get_db는 yield dependency다. 핸들러 실행 전에 커넥션을 열고, 응답 전송 후
    finally에서 닫는다. def 핸들러는 스레드풀에서 실행되므로 커넥션을 전역으로
    공유하면 sqlite3 check_same_thread 에러가 난다 — 반드시 요청당 생성.
  - 라우터 import는 create_app() 안에서 한다. 라우터가 이 모듈의
    get_building_service를 import하므로, 모듈 레벨에서 서로 import하면
    순환 import가 발생한다.
"""

import os
import sqlite3
from collections.abc import Iterator
from pathlib import Path

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.repository.BuildingRepository import BuildingRepository
from app.repository.sqliteBuildingRepository import SqliteBuildingRepository
from app.service.buildingService import BuildingService

API_ROOT = Path(__file__).resolve().parents[1]


def get_db_path() -> str:
    """DB 파일 경로. 운영/테스트에서 NAV_DB_PATH 환경변수로 교체 가능."""
    return os.getenv("NAV_DB_PATH", str(API_ROOT / "data" / "navigation.db"))


def get_db() -> Iterator[sqlite3.Connection]:
    """요청당 SQLite 커넥션. 응답 전송 후 자동으로 닫힌다."""
    conn = sqlite3.connect(get_db_path())
    conn.row_factory = sqlite3.Row  # 컬럼명으로 접근 가능한 row
    try:
        yield conn      # ← 여기서 핸들러가 실행된다
    finally:
        conn.close()    # ← 응답 전송 후 실행 (try-with-resources 대응)


def get_building_repository(
    conn: sqlite3.Connection = Depends(get_db),
) -> BuildingRepository:
    return SqliteBuildingRepository(conn)


def get_building_service(
    repository: BuildingRepository = Depends(get_building_repository),
) -> BuildingService:
    return BuildingService(repository)


def create_app() -> FastAPI:
    """FastAPI 앱 팩토리. main.py와 테스트가 이 함수로 앱을 만든다."""
    # 순환 import 방지를 위해 함수 안에서 import (모듈 docstring 참고)
    from app.router import buildingRouter, queryRouter

    app = FastAPI(title="Navigation API", version="0.2.0")

    # 개발 중에는 모든 출처(*) 허용. 운영 배포 시 Flutter 앱 도메인으로 교체 필요
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(buildingRouter.router)
    app.include_router(queryRouter.router)

    @app.get("/health", tags=["health"])
    def health():
        """서버 생존 확인. Flutter가 서버 연결 전 호출."""
        return {"status": "ok"}

    return app
```

**포인트**
- 더미 시절의 `@lru_cache` 싱글톤 repository는 제거 — 커넥션이 요청 스코프가
  되면서 repository도 요청 스코프.
- 앱 팩토리 패턴이라 테스트가 독립된 app 인스턴스를 만들 수 있다.

---

## 7. `app/router/buildingRouter.py` — 건물 엔드포인트

역할: HTTP ↔ 비즈니스 번역만. service가 None을 주면 404.

```python
"""
app/router/buildingRouter.py
============================
건물/층/그래프/매장 HTTP 엔드포인트. Spring으로 치면 Controller.

- URL과 함수를 연결하고, service가 None을 주면 404로 번역한다.
- 비즈니스 로직은 전부 BuildingService에 위임한다.
- 블로킹 IO(sqlite3)를 쓰므로 모든 핸들러는 def(동기)로 선언한다.
  (async def로 바꾸면 이벤트 루프가 막혀 서버 전체가 멈춘다)

등록된 경로 (prefix=/buildings):
  GET /buildings                                → 건물 목록
  GET /buildings/{id}                           → 건물 상세 (footprint 포함)
  GET /buildings/{id}/stores?q=검색어           → 매장 검색
  GET /buildings/{id}/floors/{floor}            → 층 지도 데이터 (매장+POI)
  GET /buildings/{id}/floors/{floor}/graph      → 길찾기 그래프 (nodes+edges)
"""

from fastapi import APIRouter, Depends, HTTPException

from app.FastAPIConfig import get_building_service
from app.service.buildingService import BuildingService

router = APIRouter(prefix="/buildings", tags=["buildings"])


@router.get("")
def list_buildings(service: BuildingService = Depends(get_building_service)):
    """전체 건물 목록. footprint 같은 무거운 데이터는 제외한 요약."""
    return service.get_all_buildings()


@router.get("/{building_id}")
def get_building(
    building_id: str,
    service: BuildingService = Depends(get_building_service),
):
    """건물 상세 정보 (면적, 둘레, footprint 폴리곤 포함)."""
    result = service.get_building(building_id)
    if result is None:
        raise HTTPException(status_code=404, detail="Building not found")
    return result


@router.get("/{building_id}/stores")
def search_stores(
    building_id: str,
    q: str = "",  # 경로에 없는 단순 타입 → 쿼리 파라미터 (?q=...)
    service: BuildingService = Depends(get_building_service),
):
    """건물 내 매장 이름 검색. q 미지정 시 전체 매장 반환."""
    result = service.search_stores(building_id, q)
    if result is None:
        raise HTTPException(status_code=404, detail="Building not found")
    return result


@router.get("/{building_id}/floors/{floor_name}")
def get_floor_map(
    building_id: str,
    floor_name: str,
    service: BuildingService = Depends(get_building_service),
):
    """층 지도 데이터. Flutter 지도 화면이 footprint/매장 폴리곤/POI를 그리는 데 사용."""
    result = service.get_floor_map(building_id, floor_name)
    if result is None:
        raise HTTPException(status_code=404, detail="Floor not found")
    return result


@router.get("/{building_id}/floors/{floor_name}/graph")
def get_floor_graph(
    building_id: str,
    floor_name: str,
    service: BuildingService = Depends(get_building_service),
):
    """층 길찾기 그래프. 클라이언트/서버 A* 경로 탐색의 입력."""
    result = service.get_floor_graph(building_id, floor_name)
    if result is None:
        raise HTTPException(status_code=404, detail="Floor not found")
    return result
```

**포인트**
- `{floor_name}`은 문자열(`1F`). 더미 시절 int였던 것에서 변경.
- 라우트는 등록 순서 매칭 — 나중에 `/buildings/search` 같은 고정 경로를 추가하면
  `/{building_id}`보다 위에 선언할 것.

---

## 8. `app/router/queryRouter.py` — RAG 스텁

역할: 자연어 질의 엔드포인트 자리만 확보(스텁). 기존 `routers/query.py`를
새 디렉토리 규약으로 옮긴 것.

```python
"""
app/router/queryRouter.py
=========================
자연어 질의(RAG) 관련 HTTP 엔드포인트.

현재는 스텁(stub) — 실제 RAG 로직(sentence-transformers + FAISS)은 후속 이슈.
Pydantic 모델로 요청 Body 스키마를 강제한다.

등록된 경로 (prefix=/query):
  POST /query/destination → 목적지 질의 (예: "편의점 어디야?")
  POST /query/info        → 장소 정보 질의 (예: "화장실 몇 층이야?")
"""

from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter(prefix="/query", tags=["query"])


class DestinationRequest(BaseModel):
    """POST /query/destination 요청 Body. 예: {"text": "구찌", "building_id": "thehyundai-seoul"}"""

    text: str
    building_id: str


class InfoRequest(BaseModel):
    """POST /query/info 요청 Body. DestinationRequest와 동일 구조."""

    text: str
    building_id: str


@router.post("/destination")
def query_destination(body: DestinationRequest):
    """목적지 자연어 질의 처리. 현재는 stub."""
    return {"status": "stub", "query": body.text, "result": None}


@router.post("/info")
def query_info(body: InfoRequest):
    """장소 정보 자연어 질의 처리. 현재는 stub."""
    return {"status": "stub", "query": body.text, "result": None}
```

---

## 9. `app/main.py` — 진입점

역할: uvicorn이 import하는 `app` 객체 하나만 노출. 조립은 전부 FastAPIConfig.

```python
"""
app/main.py
===========
FastAPI 애플리케이션 진입점(entry point).

앱 조립은 전부 FastAPIConfig.create_app()이 담당하고, 이 모듈은 uvicorn이
import할 `app` 객체만 노출한다.

실행 방법 (api/ 디렉토리에서):
  1) 최초 1회 DB 적재: python scripts/load_dataset.py
  2) 서버 실행:        uvicorn app.main:app --reload
"""

from app.FastAPIConfig import create_app

app = create_app()
```

---

## 10. `tests/conftest.py` — 공용 픽스처

역할: 실데이터 JSON을 임시 SQLite에 적재(세션당 1회)하고, `dependency_overrides`로
DI 체인의 맨 아래(`get_db`)만 임시 DB로 갈아끼운다. repository/service는
실제 코드가 그대로 돈다.

```python
"""
tests/conftest.py
=================
공용 픽스처.

- 실데이터 JSON(navigation_1f.json)을 ETL(load_navigation_db)로 임시 SQLite에
  적재해 세션 전체에서 재사용한다. 테스트가 실제 적재 경로를 그대로 검증한다.
- api_client는 FastAPI의 dependency_overrides로 get_db만 임시 DB로 바꾼다.
"""

import sqlite3

import pytest
from fastapi.testclient import TestClient

from app.FastAPIConfig import create_app, get_db
from app.repository.sqliteBuildingRepository import SqliteBuildingRepository
from scripts.load_dataset import DEFAULT_JSON, load_navigation_db

BUILDING_ID = "thehyundai-seoul"
FLOOR_NAME = "1F"


@pytest.fixture(scope="session")
def navigation_db_path(tmp_path_factory):
    """실데이터 JSON을 임시 SQLite로 적재 (세션당 1회)."""
    db_path = tmp_path_factory.mktemp("db") / "navigation.db"
    counts = load_navigation_db(json_path=DEFAULT_JSON, db_path=db_path)
    assert counts["buildings"] == 1  # 적재 자체가 깨지면 여기서 바로 실패
    return db_path


@pytest.fixture
def db_connection(navigation_db_path):
    conn = sqlite3.connect(navigation_db_path)
    conn.row_factory = sqlite3.Row
    yield conn
    conn.close()


@pytest.fixture
def building_repository(db_connection) -> SqliteBuildingRepository:
    return SqliteBuildingRepository(db_connection)


@pytest.fixture
def api_client(navigation_db_path):
    app = create_app()

    def override_get_db():
        # TestClient 요청은 스레드풀에서 실행되므로 요청당 커넥션 생성
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

---

## 11. `tests/unit/test_building_service.py` — 서비스 단위 테스트

```python
"""
BuildingService 단위 테스트.

repository는 실데이터가 적재된 임시 SQLite 기반 SqliteBuildingRepository를
사용한다 (conftest 픽스처). HTTP 계층 없이 service 반환값을 직접 검증한다.
"""

import pytest

from app.service.buildingService import BuildingService
from tests.conftest import BUILDING_ID, FLOOR_NAME


@pytest.fixture
def service(building_repository) -> BuildingService:
    return BuildingService(building_repository)


def test_건물_목록_조회(service):
    # When
    buildings = service.get_all_buildings()

    # Then
    assert len(buildings) == 1
    assert buildings[0]["id"] == BUILDING_ID
    assert buildings[0]["floors"] == [FLOOR_NAME]
    assert "footprint_local_m" not in buildings[0]  # 목록은 요약만


def test_건물_상세_조회(service):
    # When
    building = service.get_building(BUILDING_ID)

    # Then
    assert building["id"] == BUILDING_ID
    assert building["area_m2"] == pytest.approx(16182.4, abs=1.0)
    assert len(building["footprint_local_m"]) >= 4


def test_없는_건물은_None(service):
    assert service.get_building("nonexistent") is None


def test_층_그래프_조회(service):
    # When
    graph = service.get_floor_graph(BUILDING_ID, FLOOR_NAME)

    # Then — 가공 결과 기준 (docs/dataset-analysis.md)
    assert len(graph["nodes"]) == 234
    assert len(graph["edges"]) == 282

    # 엣지가 참조하는 노드가 전부 존재해야 한다
    node_ids = {n["id"] for n in graph["nodes"]}
    for edge in graph["edges"]:
        assert edge["from"] in node_ids
        assert edge["to"] in node_ids
        assert edge["length_m"] >= 0


def test_층_지도_조회(service):
    # When
    floor_map = service.get_floor_map(BUILDING_ID, FLOOR_NAME)

    # Then
    assert floor_map["floor"]["name"] == FLOOR_NAME
    assert len(floor_map["footprint_local_m"]) >= 4
    assert len(floor_map["stores"]) == 61
    assert len(floor_map["pois"]) == 47


def test_없는_층은_None(service):
    assert service.get_floor_graph(BUILDING_ID, "99F") is None
    assert service.get_floor_map(BUILDING_ID, "99F") is None


def test_매장_검색(service):
    # When
    results = service.search_stores(BUILDING_ID, "베네타")

    # Then
    assert len(results) >= 1
    assert any("베네타" in s["name"] for s in results)
    assert all(s["entrance_node_id"] for s in results)


def test_매장_검색_빈_질의는_전체(service):
    assert len(service.search_stores(BUILDING_ID, "")) == 61


def test_없는_건물_매장_검색은_None(service):
    assert service.search_stores("nonexistent", "베네타") is None
```

---

## 12. `tests/integration/test_api.py` — API 통합 테스트

```python
"""
API 통합 테스트.

TestClient로 HTTP 왕복 전체(라우팅 → DI → service → SQLite → 직렬화)를 검증한다.
데이터는 실데이터(navigation_1f.json)를 적재한 임시 SQLite.
"""

from tests.conftest import BUILDING_ID, FLOOR_NAME


def test_헬스체크(api_client):
    response = api_client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_건물_목록_조회(api_client):
    response = api_client.get("/buildings")

    assert response.status_code == 200
    buildings = response.json()
    assert isinstance(buildings, list)
    assert buildings[0]["id"] == BUILDING_ID
    assert buildings[0]["floors"] == [FLOOR_NAME]


def test_건물_단건_조회(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}")

    assert response.status_code == 200
    body = response.json()
    assert body["id"] == BUILDING_ID
    assert body["area_m2"] > 16000
    assert len(body["footprint_local_m"]) >= 4


def test_없는_건물_404(api_client):
    response = api_client.get("/buildings/nonexistent")

    assert response.status_code == 404
    assert response.json()["detail"] == "Building not found"


def test_층_지도_조회(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}")

    assert response.status_code == 200
    body = response.json()
    assert body["floor"]["name"] == FLOOR_NAME
    assert len(body["stores"]) == 61
    assert len(body["pois"]) == 47


def test_없는_층_404(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/99F")

    assert response.status_code == 404
    assert response.json()["detail"] == "Floor not found"


def test_층_그래프_조회(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/graph")

    assert response.status_code == 200
    body = response.json()
    assert len(body["nodes"]) == 234
    assert len(body["edges"]) == 282


def test_매장_검색(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/stores", params={"q": "베네타"})

    assert response.status_code == 200
    stores = response.json()
    assert len(stores) >= 1
    assert any("베네타" in s["name"] for s in stores)


def test_매장_검색_전체(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/stores")

    assert response.status_code == 200
    assert len(response.json()) == 61


def test_목적지_질의_스텁(api_client):
    payload = {"text": "구찌 어디야", "building_id": BUILDING_ID}

    response = api_client.post("/query/destination", json=payload)

    body = response.json()
    assert response.status_code == 200
    assert body["status"] == "stub"
    assert body["query"] == payload["text"]
    assert body["result"] is None


def test_정보_질의_스텁(api_client):
    payload = {"text": "화장실 위치", "building_id": BUILDING_ID}

    response = api_client.post("/query/info", json=payload)

    body = response.json()
    assert response.status_code == 200
    assert body["status"] == "stub"
    assert body["query"] == payload["text"]
    assert body["result"] is None
```

---

## 13. 코드 외 필요한 것

- **`.gitignore`에 추가**: `api/data/` 등 생성되는 DB 파일 (ETL이 멱등이라 재생성하면 됨)
- **`api/requirements.txt`**: fastapi / uvicorn / pydantic / pytest / httpx.
  sqlite3는 표준 라이브러리라 추가 불필요, shapely는 더 이상 쓰지 않아 제외
- **venv는 Python 3.12로**: `py -3.12 -m venv .venv` — 3.14는 fastapi/pydantic/shapely
  고정 버전 휠이 없어 pip 설치가 실패한다.
