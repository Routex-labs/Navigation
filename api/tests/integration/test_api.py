import pytest
from fastapi.testclient import TestClient

from app.core.dependencies import get_building_repository
from app.main import app


@pytest.fixture
def api_client(building_repository):
    # BeforeEach
    app.dependency_overrides.clear()
    get_building_repository.cache_clear()
    app.dependency_overrides[get_building_repository] = lambda: building_repository

    with TestClient(app) as client:
        yield client

    # AfterEach
    app.dependency_overrides.clear()
    get_building_repository.cache_clear()


def test_헬스체크(api_client):
    # Given
    expected_body = {"status": "ok"}

    # When
    response = api_client.get("/health")

    # Then
    assert response.status_code == 200
    assert response.json() == expected_body


def test_건물_목록_조회(api_client):
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


def test_건물_단건_조회(api_client):
    # Given
    building_id = "bldg-001"

    # When
    response = api_client.get(f"/buildings/{building_id}")

    # Then
    assert response.status_code == 200
    assert response.json()["id"] == building_id


def test_없는_건물_404(api_client):
    # Given
    building_id = "nonexistent"

    # When
    response = api_client.get(f"/buildings/{building_id}")

    # Then
    assert response.status_code == 404
    assert response.json()["detail"] == "Building not found"


def test_층_조회(api_client):
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


def test_없는_층_404(api_client):
    # Given
    building_id = "bldg-001"
    floor = 99

    # When
    response = api_client.get(f"/buildings/{building_id}/floors/{floor}")

    # Then
    assert response.status_code == 404
    assert response.json()["detail"] == "Floor not found"


def test_목적지_질의_스텁(api_client):
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


def test_정보_질의_스텁(api_client):
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
