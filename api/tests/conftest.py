import pytest

from app.domain.building import Building
from app.repositories.memory_building_repository import MemoryBuildingRepository


@pytest.fixture
def sample_building() -> Building:
    return Building(
        id="bldg-001",
        name="테스트 건물",
        floors=[1, 2],
        floor_data={
            "1": {
                "type": "FeatureCollection",
                "features": [
                    {
                        "type": "Feature",
                        "properties": {"type": "corridor", "name": "1층 복도"},
                        "geometry": {
                            "type": "LineString",
                            "coordinates": [[126.9780, 37.5665], [126.9785, 37.5665]],
                        },
                    }
                ],
            },
            "2": {
                "type": "FeatureCollection",
                "features": [],
            },
        },
    )


@pytest.fixture
def building_repository(sample_building: Building) -> MemoryBuildingRepository:
    return MemoryBuildingRepository(buildings=[sample_building])
