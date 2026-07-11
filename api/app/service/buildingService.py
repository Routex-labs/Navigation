"""
건물/층/그래프/매장 비즈니스 로직
"""

from typing import Any

from app.domain.building import Building, Edge, FloorVectorMap, MapFeature, Node, Poi, Store
from app.domain.dijkstra import ShortestPath, find_shortest_path
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
        vector_map = self.building_repository.find_vector_map_by_floor(floor.id)
        # Flutter 지도 한 화면을 그리는 데 필요한 데이터를 한 응답으로 조합한다.
        return {
            "floor": {"id": floor.id, "name": floor.name, "level": floor.level},
            "navigation_coordinate_system": "local_m",
            "footprint_local_m": building.footprint_local_m if building else [],
            "vector_map": self._to_vector_map_dict(vector_map) if vector_map else None,
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

    def get_shortest_path(
        self,
        building_id: str,
        floor_name: str,
        start_node_id: str,
        end_node_id: str,
    ) -> dict[str, Any] | None:
        floor = self.building_repository.find_floor_by_name(
            building_id,
            floor_name,
        )
        if floor is None:
            return None

        nodes = self.building_repository.find_nodes_by_floor(floor.id)
        edges = self.building_repository.find_edges_by_floor(floor.id)

        path = find_shortest_path(
            nodes=nodes,
            edges=edges,
            start_node_id=start_node_id,
            end_node_id=end_node_id,
        )

        if path is None:
            return {
                "start_node_id": start_node_id,
                "end_node_id": end_node_id,
                "path_found": False,
            }

        return {
            "start_node_id": start_node_id,
            "end_node_id": end_node_id,
            "path_found": True,
            "node_ids": list(path.node_ids),
            "edge_ids": list(path.edge_ids),
            "coordinate_system": "local_m",
            "path_points": self._build_path_points(path, nodes, edges),
            "total_distance_m": round(path.total_distance_m, 3),
        }

    @staticmethod
    def _build_path_points(
        path: ShortestPath,
        nodes: list[Node],
        edges: list[Edge],
    ) -> list[dict[str, float]]:
        """최단 경로의 간선 geometry를 진행 방향에 맞춰 하나의 선으로 합친다."""
        nodes_by_id = {node.id: node for node in nodes}
        edges_by_id = {edge.id: edge for edge in edges}

        if not path.edge_ids:
            node = nodes_by_id[path.node_ids[0]]
            return [{"x": node.position.x_m, "y": node.position.y_m}]

        path_points: list[dict[str, float]] = []

        for index, edge_id in enumerate(path.edge_ids):
            edge = edges_by_id[edge_id]
            from_node_id = path.node_ids[index]
            to_node_id = path.node_ids[index + 1]

            geometry = [dict(point) for point in edge.geometry_local_m]
            if not geometry:
                from_node = nodes_by_id[from_node_id]
                to_node = nodes_by_id[to_node_id]
                geometry = [
                    {"x": from_node.position.x_m, "y": from_node.position.y_m},
                    {"x": to_node.position.x_m, "y": to_node.position.y_m},
                ]
            elif (
                edge.from_node_id == to_node_id
                and edge.to_node_id == from_node_id
            ):
                geometry.reverse()
            elif not (
                edge.from_node_id == from_node_id
                and edge.to_node_id == to_node_id
            ):
                raise ValueError(
                    f"간선 {edge.id}가 경로 노드 {from_node_id}, {to_node_id}와 연결되지 않습니다."
                )

            if path_points and path_points[-1] == geometry[0]:
                path_points.extend(geometry[1:])
            else:
                path_points.extend(geometry)

        return path_points

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
            "entrance_local_m": {
                "x": store.entrance.x_m,
                "y": store.entrance.y_m,
            }
            if store.entrance
            else None,
            "entrance_node_id": store.entrance_node_id,
            "polygon_local_m": store.polygon_local_m,
        }

    @staticmethod
    def _to_vector_map_dict(vector_map: FloorVectorMap) -> dict[str, Any]:
        return {
            "coordinate_system": vector_map.coordinate_system,
            "source": vector_map.source,
            "features": [
                BuildingService._to_map_feature_dict(feature)
                for feature in vector_map.features
            ],
        }

    @staticmethod
    def _to_map_feature_dict(feature: MapFeature) -> dict[str, Any]:
        return {
            "id": feature.id,
            "kind": feature.kind,
            "name": feature.name,
            "category": feature.category,
            "geometry": {
                "type": feature.geometry_type,
                "coordinates": feature.coordinates,
            },
            "centroid": feature.centroid,
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
