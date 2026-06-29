import pytest
from fastapi.testclient import TestClient

from app.core.dependencies import get_building_repository
from app.domain.building import Building
from app.main import app
from app.repositories.memory_building_repository import MemoryBuildingRepository


def _test_building() -> Building:
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


def _create_test_building_repository() -> MemoryBuildingRepository:
    return MemoryBuildingRepository(buildings=[_test_building()])


@pytest.fixture
def api_client():
    # BeforeEach
    app.dependency_overrides.clear()
    get_building_repository.cache_clear()
    app.dependency_overrides[get_building_repository] = _create_test_building_repository
    with TestClient(app) as client:
        yield client

    # AfterEach
    app.dependency_overrides.clear()
    get_building_repository.cache_clear()


def test_health(api_client):
    # Given
    expected_body = {"status": "ok"}

    # When
    response = api_client.get("/health")

    # Then
    assert response.status_code == 200
    assert response.json() == expected_body


def test_list_buildings(api_client):
    # Given
    expected_building_id = "bldg-001"

    # When
    response = api_client.get("/buildings")

    # Then
    assert response.status_code == 200
    buildings = response.json()
    assert isinstance(buildings, list)
    assert buildings[0]["id"] == expected_building_id
    assert "floor_data" not in buildings[0]


def test_get_building(api_client):
    # Given
    building_id = "bldg-001"

    # When
    response = api_client.get(f"/buildings/{building_id}")

    # Then
    assert response.status_code == 200
    assert response.json()["id"] == building_id


def test_get_building_not_found(api_client):
    # Given
    building_id = "nonexistent"

    # When
    response = api_client.get(f"/buildings/{building_id}")

    # Then
    assert response.status_code == 404
    assert response.json()["detail"] == "Building not found"


def test_get_floor(api_client):
    # Given
    building_id = "bldg-001"
    floor = 1

    # When
    response = api_client.get(f"/buildings/{building_id}/floors/{floor}")

    # Then
    assert response.status_code == 200
    geojson = response.json()
    assert geojson["type"] == "FeatureCollection"
    assert len(geojson["features"]) > 0


def test_get_floor_not_found(api_client):
    # Given
    building_id = "bldg-001"
    floor = 99

    # When
    response = api_client.get(f"/buildings/{building_id}/floors/{floor}")

    # Then
    assert response.status_code == 404
    assert response.json()["detail"] == "Floor not found"


def test_query_destination_stub(api_client):
    # Given
    payload = {"text": "강의실 101", "building_id": "bldg-001"}

    # When
    response = api_client.post("/query/destination", json=payload)

    # Then
    body = response.json()
    assert response.status_code == 200
    assert body["status"] == "stub"
    assert body["query"] == payload["text"]
    assert body["result"] is None


def test_query_info_stub(api_client):
    # Given
    payload = {"text": "화장실 위치", "building_id": "bldg-001"}

    # When
    response = api_client.post("/query/info", json=payload)

    # Then
    body = response.json()
    assert response.status_code == 200
    assert body["status"] == "stub"
    assert body["query"] == payload["text"]
    assert body["result"] is None
