"""
가공된 실 데이터를 SQLite(navigation.db) 에 적재하는 ETL

1회성 스크립트. 실행할 때마다 테이블을 DROP 후 재생성한다 (멱등).

실행방법
python scripts/load_dataset.py
python scripts/load_dataset.py --db data/navigation.db

"""
from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path

# 스크립트를 어느 디렉토리에서 실행해도 같은 입력/출력 경로를 사용한다.
API_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_JSON = API_ROOT / "app" / "data" / "navigation_1f.json"
DEFAULT_DB = API_ROOT / "data" / "navigation.db"

# 개발용 데이터셋을 항상 같은 상태로 만들기 위해 DROP → CREATE를 한 번에 실행한다.
# 자식 테이블부터 DROP해야 외래 키 관계가 있어도 안전하게 다시 생성할 수 있다.
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
    json_path : Path = DEFAULT_JSON, db_path: Path = DEFAULT_DB
) -> dict[str, int]:
    """navigation JSON을 읽어 SQLite로 적재하고 테이블별 건수를 반환한다."""
    # 원본 JSON 전체를 Python dict/list 구조로 읽는다.
    with open(json_path, encoding = "utf-8") as f:
        data = json.load(f)

    # 현재 데이터셋은 건물 하나와 그 안의 단일 층을 기준으로 구성돼 있다.
    building = data["building"]
    floor = building["floor"]
    building_id = building["id"]
    floor_id = floor["id"]

    # 출력 폴더가 아직 없어도 DB 파일을 생성할 수 있게 준비한다.
    db_path = Path(db_path)
    db_path.parent.mkdir(parents = True, exist_ok = True) # data/ 폴더 없으면 생성

    conn = sqlite3.connect(db_path)
    try:
        # 테이블과 인덱스를 초기화한 뒤 아래 INSERT를 시작한다.
        conn.executescript(DDL) # DROP + CREATE ( 멱등의 핵심 ), 자동 transaction 시작

        # --- 건물/층: 각각 한 건씩 INSERT ---
        conn.execute(
            "INSERT INTO buildings (id, name, area_m2, perimeter_m, footprint_local_m)"
            " VALUES (?, ?, ?, ?, ?)",
            (
                building_id, 
                building["name"], 
                building["area_m2"], 
                building["perimeter_m"], 
                # 폴리곤 리스트는 JSON 문자열로 직렬화해서 TEXT 칼럼에 저장합니다.
                json.dumps(building["footprint_local_m"], ensure_ascii = False),
            ),
        )
        conn.execute(
            "INSERT INTO floors (id, building_id, name, level) VALUES (?, ?, ?, ?)",
            (floor_id, building_id, floor["name"], floor["level"]),
        )

        # --- 그래프/지도 데이터: 목록을 executemany로 일괄 INSERT ---
        # 대량 Insert는 한 건씩 execute하는 것보다 DB 호출 횟수가 적다.
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
            # Edge는 Node ID를 참조하고 geometry는 JSON 문자열로 저장한다.
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
            # Store 폴리곤과 선택적 입구 좌표를 평면 컬럼으로 적재한다.
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
            # POI 위치는 Node와 별개로 표시하되 linked_node_id로 길찾기에 연결할 수 있다.
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
        # 모든 테이블 INSERT가 성공한 경우에만 한 번에 영구 반영한다.
        conn.commit() # 자동으로 transaction 마무리

        # 적재 결과 요약은 CLI 출력과 테스트의 데이터 건수 검증에 함께 사용한다.
        counts = {
            table: conn.execute(f"select count(*) from {table}").fetchone()[0]
            for table in ("buildings", "floors", "nodes", "edges", "stores", "pois")
        }
        return counts
    
    finally:
        # 중간 INSERT에서 예외가 발생해도 파일 핸들을 반드시 반환한다.
        conn.close() # 예외가 나도 커넥션은 반드시 닫는다.

if __name__ == "__main__":
    # 모듈 import 때는 실행하지 않고 직접 호출했을 때만 CLI 인자를 처리한다.
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    args = parser.parse_args()

    result = load_navigation_db(args.json, args.db)
    print(f"적재 완료 : {args.db}")
    for table, count in result.items():
        print(f" {table}: {count}")
