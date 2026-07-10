"""Service가 데이터 저장 방식과 분리되도록 하는 Repository 계약."""

from typing import Protocol

from app.domain.building import Building, Edge, Floor, Node, Poi, Store


class BuildingRepository(Protocol):
    # Protocol은 Java interface처럼 필요한 메서드 형태만 선언한다.
    # 구현체가 명시적으로 상속하지 않아도 이 메서드를 제공하면 사용할 수 있다.

    # --- buildings / floors ---

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

    # --- navigation graph ---

    def find_nodes_by_floor(self, floor_id: str) -> list[Node]:
        """층의 길찾기 그래프 노드 목록."""
        ...

    def find_edges_by_floor(self, floor_id: str) -> list[Edge]:
        """층의 길찾기 그래프 엣지 목록."""
        ...

    # --- stores / POIs ---

    def find_stores_by_floor(self, floor_id: str) -> list[Store]:
        """층의 매장 목록."""
        ...

    def find_pois_by_floor(self, floor_id: str) -> list[Poi]:
        """층의 POI(엘리베이터/화장실/출구 등) 목록."""
        ...

    def search_stores(self, building_id: str, query: str) -> list[Store]:
        """건물 전체에서 이름에 query가 포함된 매장 검색."""
        ...
