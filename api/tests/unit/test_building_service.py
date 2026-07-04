from app.domain.building import Building
from app.services.building_service import BuildingService


class FakeBuildingRepository:
    def __init__(self, buildings: list[Building]):
        self._buildings = {building.id: building for building in buildings}

    def find_all(self) -> list[Building]:
        return list(self._buildings.values())

    def find_by_id(self, building_id: str) -> Building | None:
        return self._buildings.get(building_id)


def _sample_building() -> Building:
    return Building(
        id="bldg-001",
        name="테스트 건물",
        floors=[1, 2],
        floor_data={
            "1": {"type": "FeatureCollection", "features": [{"type": "Feature"}]},
            "2": {"type": "FeatureCollection", "features": []},
        },
    )


def test_get_all_buildings_excludes_floor_data():
    # Given
    service = BuildingService(FakeBuildingRepository([_sample_building()]))

    # When
    summaries = service.get_all_buildings()

    # Then
    assert len(summaries) == 1
    assert summaries[0]["id"] == "bldg-001"
    assert "floor_data" not in summaries[0]


def test_get_building_returns_summary_when_found():
    # Given
    service = BuildingService(FakeBuildingRepository([_sample_building()]))

    # When
    result = service.get_building("bldg-001")

    # Then
    assert result["id"] == "bldg-001"
    assert result["name"] == "테스트 건물"


def test_get_building_returns_none_when_not_found():
    # Given
    service = BuildingService(FakeBuildingRepository([_sample_building()]))

    # When
    result = service.get_building("nonexistent")

    # Then
    assert result is None


def test_get_floor_geojson_returns_geojson_when_found():
    # Given
    service = BuildingService(FakeBuildingRepository([_sample_building()]))

    # When
    result = service.get_floor_geojson("bldg-001", 1)

    # Then
    assert result["type"] == "FeatureCollection"
    assert len(result["features"]) == 1


def test_get_floor_geojson_returns_none_when_building_not_found():
    # Given
    service = BuildingService(FakeBuildingRepository([_sample_building()]))

    # When
    result = service.get_floor_geojson("nonexistent", 1)

    # Then
    assert result is None


def test_get_floor_geojson_returns_none_when_floor_not_found():
    # Given
    service = BuildingService(FakeBuildingRepository([_sample_building()]))

    # When
    result = service.get_floor_geojson("bldg-001", 99)

    # Then
    assert result is None
