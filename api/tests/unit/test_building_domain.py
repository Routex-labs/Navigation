from app.domain.building import Building


def _sample_floor_data() -> dict:
    return {"1": {"type": "FeatureCollection", "features": []}}


def test_building_holds_given_fields():
    # Given / When
    building = Building(
        id="bldg-001",
        name="테스트 건물",
        floors=[1, 2],
        floor_data=_sample_floor_data(),
    )

    # Then
    assert building.id == "bldg-001"
    assert building.name == "테스트 건물"
    assert building.floors == [1, 2]
    assert building.floor_data == _sample_floor_data()


def test_floors_property_returns_copy_not_reference():
    # Given
    original_floors = [1, 2]
    building = Building(
        id="bldg-001", name="테스트 건물", floors=original_floors, floor_data={}
    )

    # When
    building.floors.append(99)

    # Then
    assert building.floors == [1, 2]


def test_floor_data_property_returns_deep_copy():
    # Given
    building = Building(
        id="bldg-001", name="테스트 건물", floors=[1], floor_data=_sample_floor_data()
    )

    # When
    building.floor_data["1"]["features"].append({"type": "Feature"})

    # Then
    assert building.floor_data == _sample_floor_data()
