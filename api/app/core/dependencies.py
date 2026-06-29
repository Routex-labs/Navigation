"""
app/core/dependencies.py
========================
FastAPI DI 설정.

Controller 역할의 router는 service만 의존하고, service는 repository interface에 의존한다.
초기 구현체는 MemoryBuildingRepository로 운영한다.
"""

from functools import lru_cache

from fastapi import Depends

from app.repositories.building_repository import BuildingRepository
from app.repositories.memory_building_repository import MemoryBuildingRepository
from app.services.building_service import BuildingService


@lru_cache
def get_building_repository() -> BuildingRepository:
    return MemoryBuildingRepository()


def get_building_service(
    building_repository: BuildingRepository = Depends(get_building_repository),
) -> BuildingService:
    return BuildingService(building_repository)
