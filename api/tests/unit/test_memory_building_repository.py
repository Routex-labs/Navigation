from app.domain.building import Building
from app.repositories.memory_building_repository import MemoryBuildingRepository


def _sample_building(building_id: str = "bldg-001") -> Building:
    return Building(
        id=building_id,
        name="테스트 건물",
        floors=[1],
        floor_data={"1": {"type": "FeatureCollection", "features": []}},
    )


def test_find_all_returns_seeded_buildings():
    # Given
    repository = MemoryBuildingRepository(buildings=[_sample_building()])

    # When
    result = repository.find_all()

    # Then
    assert len(result) == 1
    assert result[0].id == "bldg-001"


def test_find_by_id_returns_matching_building():
    # Given
    repository = MemoryBuildingRepository(buildings=[_sample_building()])

    # When
    result = repository.find_by_id("bldg-001")

    # Then
    assert result is not None
    assert result.id == "bldg-001"


def test_find_by_id_returns_none_when_missing():
    # Given
    repository = MemoryBuildingRepository(buildings=[_sample_building()])

    # When
    result = repository.find_by_id("nonexistent")

    # Then
    assert result is None


def test_loads_default_sample_data_when_no_buildings_given():
    # Given / When
    repository = MemoryBuildingRepository()

    # Then
    assert len(repository.find_all()) >= 1
