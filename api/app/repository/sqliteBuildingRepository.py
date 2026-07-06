"""
BuildingRepository의 SQLite 구현체
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
            "select id, name, area_m2, perimeter_m, footprint_local_m from buildings"
        ).fetchall()
        return [self._to_building(r) for r in rows]
    
    def find_building_by_id(self, building_id: str) -> Building | None:
        row = self._conn.execute(
            "select id, name, area_m2, perimeter_m, footprint_local_m from buildings"
            " where id = ?",
            (building_id,),
            ).fetchone()

        return self._to_building(row) if row else None
        

    # --- floors ---
    def find_floors_by_building(self, building_id: str) -> list[Floor]:
        rows = self._conn.execute(
            "select id, building_id, name, level from floors"
            " where building_id = ? order by level",
            (building_id, ),
        ).fetchall()
        # 칼럼 명과 dataclass 피드명이 같으므로 dict 언패킹으로 바로 매핑한다.
        return [Floor(**dict(r)) for r in rows]
    
    def find_floor_by_name(self, building_id: str, floor_name: str) -> Floor | None:
        row = self._conn.execute(
            "select id, building_id, name, level from floors"
            " where building_id = ? and name = ?",
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