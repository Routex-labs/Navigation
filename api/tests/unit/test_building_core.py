from app.domain.building import Building
from app.services.building_service import BuildingService


def test_건물_내부상태_격리(sample_building: Building):
    # Given
    floors = sample_building.floors
    floor_data = sample_building.floor_data

    # When
    floors.append(99)
    floor_data["1"]["features"].clear()

    # Then
    assert sample_building.floors == [1, 2]
    assert len(sample_building.floor_data["1"]["features"]) == 1


def test_저장소_ID로_건물_조회(building_repository):
    # Given
    building_id = "bldg-001"

    # When
    building = building_repository.find_by_id(building_id)
    missing_building = building_repository.find_by_id("nonexistent")

    # Then
    assert building is not None
    assert building.id == building_id
    assert missing_building is None


def test_서비스_건물_요약_반환(building_repository):
    # Given
    service = BuildingService(building_repository)

    # When
    buildings = service.get_all_buildings()
    building = service.get_building("bldg-001")

    # Then
    assert buildings == [{"id": "bldg-001", "name": "테스트 건물", "floors": [1, 2]}]
    assert building == buildings[0]
    assert "floor_data" not in building


def test_서비스_층_GeoJSON_반환(building_repository):
    # Given
    service = BuildingService(building_repository)

    # When
    floor = service.get_floor_geojson("bldg-001", 1)
    missing_floor = service.get_floor_geojson("bldg-001", 99)
    missing_building = service.get_floor_geojson("nonexistent", 1)

    # Then
    assert floor is not None
    assert floor["type"] == "FeatureCollection"
    assert missing_floor is None
    assert missing_building is None
