"""
건물/층/그래프/매장 비즈니스 로직
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