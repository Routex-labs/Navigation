"""
app/services/building_service.py
=================================
건물 비즈니스 로직.

역할:
  - BuildingRepository 인터페이스에 의존해 건물 도메인 객체를 조회
  - 라우터가 필요한 응답 형태로 비즈니스 로직을 수행하고 가공
  - 나중에 DB(PostgreSQL 등)로 교체할 때 repository 구현체만 바꾸면 됨

Spring Boot로 치면 BuildingService 역할.
"""

from typing import Any

from app.repositories.building_repository import BuildingRepository


class BuildingService:
    def __init__(self, building_repository: BuildingRepository):
        self.building_repository = building_repository

    def get_all_buildings(self) -> list[dict[str, Any]]:
        """
        전체 건물 목록 반환.
        floor_data(층별 GeoJSON)는 용량이 크므로 목록에서 제외하고 요약 필드만 반환.
        """
        return [building.to_summary() for building in self.building_repository.find_all()]

    def get_building(self, building_id: str) -> dict[str, Any] | None:
        """
        building_id가 일치하는 건물 반환. 없으면 None.
        라우터에서 None을 받으면 HTTP 404로 변환.
        """
        building = self.building_repository.find_by_id(building_id)
        if building is None:
            return None
        return building.to_summary()

    def get_floor_geojson(self, building_id: str, floor: int) -> dict[str, Any] | None:
        """
        특정 건물의 특정 층 GeoJSON 반환. 건물이나 층이 없으면 None.
        floor는 int로 받지만 JSON 키는 문자열이므로 도메인 객체가 내부에서 변환한다.
        """
        building = self.building_repository.find_by_id(building_id)
        if building is None:
            return None
        return building.get_floor_geojson(floor)
