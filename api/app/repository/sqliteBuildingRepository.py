"""SQL 실행 결과를 순수 도메인 객체로 변환하는 SQLite Repository 구현체."""

import json
import sqlite3

from app.domain.building import Building, Edge, Floor, LocalPoint, Node, Poi, Store

class SqliteBuildingRepository:
    def __init__(self, conn: sqlite3.Connection):
        # 커넥션의 생성/종료 책임은 FastAPI의 get_db dependency가 가진다.
        self._conn = conn

    # --- buildings ---

    def find_all_buildings(self) -> list[Building]:
        # 목록 조회이므로 fetchall로 모든 건물을 가져온다.
        rows = self._conn.execute(
            "select id, name, area_m2, perimeter_m, footprint_local_m from buildings"
        ).fetchall()
        return [self._to_building(r) for r in rows]
    
    def find_building_by_id(self, building_id: str) -> Building | None:
        # 사용자 입력을 SQL 문자열에 합치지 않고 ? 파라미터로 바인딩한다.
        row = self._conn.execute(
            "select id, name, area_m2, perimeter_m, footprint_local_m from buildings"
            " where id = ?",
            (building_id,),
            ).fetchone()

        # 단건 조회 결과가 없으면 Service가 처리할 수 있도록 None을 반환한다.
        return self._to_building(row) if row else None
        

    # --- floors ---
    def find_floors_by_building(self, building_id: str) -> list[Floor]:
        # level 기준 정렬로 API가 1F, 2F 순서를 그대로 사용할 수 있게 한다.
        rows = self._conn.execute(
            "select id, building_id, name, level from floors"
            " where building_id = ? order by level",
            (building_id, ),
        ).fetchall()
        # 칼럼 명과 dataclass 피드명이 같으므로 dict 언패킹으로 바로 매핑한다.
        return [Floor(**dict(r)) for r in rows]
    
    def find_floor_by_name(self, building_id: str, floor_name: str) -> Floor | None:
        # 같은 층 이름이 다른 건물에도 있을 수 있으므로 building_id도 함께 조건에 둔다.
        row = self._conn.execute(
            "select id, building_id, name, level from floors"
            " where building_id = ? and name = ?",
            (building_id, floor_name),
        ).fetchone()

        return Floor(**dict(row)) if row else None
    
    # --- graph --- 
    def find_nodes_by_floor(self, floor_id: str) -> list[Node]:
        # 다익스트라 입력이 될 한 층의 모든 정점을 한 번에 조회한다.
        rows = self._conn.execute(
            "SELECT id, floor_id, type, name, x_m, y_m, lat, lng FROM nodes"
            " WHERE floor_id = ?",
            (floor_id,),
        ).fetchall()
        return [self._to_node(r) for r in rows]

    def find_edges_by_floor(self, floor_id: str) -> list[Edge]:
        # 탐색 도중 SQL을 반복하지 않도록 한 층의 간선을 한 번에 메모리로 가져온다.
        rows = self._conn.execute(
            "SELECT id, floor_id, from_node_id, to_node_id, length_m, bidirectional,"
            " geometry FROM edges WHERE floor_id = ?",
            (floor_id,),
        ).fetchall()
        # SQLite의 0/1과 JSON 문자열을 Python bool/list로 복원한다.
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
        # 지도 렌더링에 필요한 중심점, 입구, 폴리곤을 함께 조회한다.
        rows = self._conn.execute(
            "SELECT id, floor_id, name, centroid_x_m, centroid_y_m,"
            " entrance_x_m, entrance_y_m, entrance_node_id, polygon"
            " FROM stores WHERE floor_id = ?",
            (floor_id,),
        ).fetchall()
        return [self._to_store(r) for r in rows]

    def find_pois_by_floor(self, floor_id: str) -> list[Poi]:
        # 화장실/출구 등 매장이 아닌 지도 지점을 층 단위로 조회한다.
        rows = self._conn.execute(
            "SELECT id, floor_id, type, name, x_m, y_m, linked_node_id FROM pois"
            " WHERE floor_id = ?",
            (floor_id,),
        ).fetchall()
        return [self._to_poi(r) for r in rows]

    def search_stores(self, building_id: str, query: str) -> list[Store]:
        # 층을 거쳐 건물로 join — stores에는 building_id가 없기 때문
        rows = self._conn.execute(
            "SELECT s.id, s.floor_id, s.name, s.centroid_x_m, s.centroid_y_m,"
            " s.entrance_x_m, s.entrance_y_m, s.entrance_node_id, s.polygon"
            " FROM stores s JOIN floors f ON s.floor_id = f.id"
            " WHERE f.building_id = ? AND s.name LIKE ?",
            (building_id, f"%{query}%"),  # LIKE 패턴도 값 바인딩해 SQL injection 방지
        ).fetchall()
        return [self._to_store(r) for r in rows]

    # --- 매핑 ---

    @staticmethod
    def _to_building(row: sqlite3.Row) -> Building:
        # TEXT 컬럼에 저장된 JSON 외곽선을 Python list로 역직렬화한다.
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
        # 반복되는 x/y 컬럼은 LocalPoint 값 객체로 묶어 도메인에 전달한다.
        return Store(
            id=row["id"],
            floor_id=row["floor_id"],
            name=row["name"],
            centroid=LocalPoint(
                x_m=row["centroid_x_m"],
                y_m=row["centroid_y_m"],
            ),
            entrance=SqliteBuildingRepository._to_optional_local_point(
                row,
                "entrance_x_m",
                "entrance_y_m",
            ),
            entrance_node_id=row["entrance_node_id"],
            polygon_local_m=json.loads(row["polygon"]) if row["polygon"] else None,
        )

    @staticmethod
    def _to_node(row: sqlite3.Row) -> Node:
        # DB row의 평면 좌표 컬럼을 Node.position으로 조립한다.
        return Node(
            id=row["id"],
            floor_id=row["floor_id"],
            type=row["type"],
            name=row["name"],
            position=LocalPoint(x_m=row["x_m"], y_m=row["y_m"]),
            lat=row["lat"],
            lng=row["lng"],
        )

    @staticmethod
    def _to_poi(row: sqlite3.Row) -> Poi:
        # POI도 Node와 동일한 LocalPoint 구조를 재사용한다.
        return Poi(
            id=row["id"],
            floor_id=row["floor_id"],
            type=row["type"],
            name=row["name"],
            position=LocalPoint(x_m=row["x_m"], y_m=row["y_m"]),
            linked_node_id=row["linked_node_id"],
        )

    @staticmethod
    def _to_optional_local_point(
        row: sqlite3.Row,
        x_column: str,
        y_column: str,
    ) -> LocalPoint | None:
        # 선택 좌표는 x/y가 모두 NULL일 때만 좌표 없음으로 처리한다.
        x_m = row[x_column]
        y_m = row[y_column]
        if x_m is None and y_m is None:
            return None
        if x_m is None or y_m is None:
            # 한쪽 값만 있으면 데이터가 손상된 것이므로 조용히 통과시키지 않는다.
            raise ValueError(f"{x_column}, {y_column} 좌표 값이 불완전합니다.")
        return LocalPoint(x_m=x_m, y_m=y_m)
