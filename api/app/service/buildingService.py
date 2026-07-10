"""
건물/층/그래프/매장 비즈니스 로직
"""

from typing import Any

from app.domain.building import Building, Edge, Node, Poi, Store
from app.repository.BuildingRepository import BuildingRepository


class BuildingService:
    def __init__(self, building_repository: BuildingRepository):
        # 구체적인 SQLite 구현 대신 Repository 계약을 주입받아 저장소와 결합도를 낮춘다.
        self.building_repository = building_repository

    def get_all_buildings(self) -> list[dict[str, Any]]:
        """전체 건물 목록. footprint 같은 무거운 필드는 제외한 요약."""
        # 목록 화면에 필요한 값만 남겨 큰 footprint JSON 전송을 피한다.
        return [
            self._to_building_summary(b)
            for b in self.building_repository.find_all_buildings()
        ]

    def get_building(self, building_id: str) -> dict[str, Any] | None:
        """건물 상세. footprint 포함. 없으면 None."""
        # 데이터가 없다는 사실만 None으로 전달하고 HTTP 404 변환은 Router가 담당한다.
        building = self.building_repository.find_building_by_id(building_id)
        if building is None:
            return None
        # 목록용 공통 필드에 상세 화면용 면적/외곽선을 추가한다.
        summary = self._to_building_summary(building)
        summary["area_m2"] = building.area_m2
        summary["perimeter_m"] = building.perimeter_m
        summary["footprint_local_m"] = building.footprint_local_m
        return summary

    def get_floor_map(self, building_id: str, floor_name: str) -> dict[str, Any] | None:
        """층 지도 데이터(footprint + 매장 폴리곤 + POI). 렌더링용."""
        # URL의 층 이름을 DB 내부 floor_id로 먼저 해석한다.
        floor = self.building_repository.find_floor_by_name(building_id, floor_name)
        if floor is None:
            return None
        building = self.building_repository.find_building_by_id(building_id)
        # Flutter 지도 한 화면을 그리는 데 필요한 데이터를 한 응답으로 조합한다.
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
        # 층 존재 여부를 먼저 확인한 뒤 해당 층의 그래프만 조회한다.
        floor = self.building_repository.find_floor_by_name(building_id, floor_name)
        if floor is None:
            return None
        # 아직 경로 계산은 하지 않고 탐색 입력인 노드/간선 전체를 반환한다.
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
        # "없는 건물"과 "검색 결과 없음"을 구분하기 위해 건물을 먼저 확인한다.
        if self.building_repository.find_building_by_id(building_id) is None:
            return None
        return [
            self._to_store_dict(s)
            for s in self.building_repository.search_stores(building_id, query)
        ]

    # --- domain 객체 → API 응답 dict 변환 ---
    # 도메인 모델을 그대로 노출하지 않고 Flutter가 소비할 JSON 구조로 변환한다.

    def _to_building_summary(self, building: Building) -> dict[str, Any]:
        # Building에는 층 이름 목록이 없으므로 Repository에서 조회해 요약에 결합한다.
        floors = self.building_repository.find_floors_by_building(building.id)
        return {
            "id": building.id,
            "name": building.name,
            "floors": [f.name for f in floors],
        }

    @staticmethod
    def _to_node_dict(node: Node) -> dict[str, Any]:
        # LocalPoint 값 객체를 기존 API 규약의 x_m/y_m 평면 필드로 펼친다.
        return {
            "id": node.id,
            "type": node.type,
            "name": node.name,
            "x_m": node.position.x_m,
            "y_m": node.position.y_m,
            "lat": node.lat,
            "lng": node.lng,
        }

    @staticmethod
    def _to_edge_dict(edge: Edge) -> dict[str, Any]:
        # 도메인의 from_node_id/to_node_id를 API에서는 짧은 from/to 이름으로 노출한다.
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
        # 매장 중심점을 Flutter가 바로 읽을 수 있는 중첩 JSON 좌표로 만든다.
        return {
            "id": store.id,
            "floor_id": store.floor_id,
            "name": store.name,
            "centroid_local_m": {
                "x": store.centroid.x_m,
                "y": store.centroid.y_m,
            },
            "entrance_node_id": store.entrance_node_id,
            "polygon_local_m": store.polygon_local_m,
        }

    @staticmethod
    def _to_poi_dict(poi: Poi) -> dict[str, Any]:
        # POI 위치도 매장과 동일한 {x, y} 좌표 규약으로 반환한다.
        return {
            "id": poi.id,
            "type": poi.type,
            "name": poi.name,
            "position_local_m": {
                "x": poi.position.x_m,
                "y": poi.position.y_m,
            },
            "linked_node_id": poi.linked_node_id,
        }
