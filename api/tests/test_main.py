import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_health():
    res = client.get("/health")
    assert res.status_code == 200
    assert res.json() == {"status": "ok"}


def test_list_buildings():
    res = client.get("/buildings")
    assert res.status_code == 200
    assert isinstance(res.json(), list)
    assert len(res.json()) > 0


def test_get_building():
    res = client.get("/buildings/bldg-001")
    assert res.status_code == 200
    assert res.json()["id"] == "bldg-001"


def test_get_building_not_found():
    res = client.get("/buildings/nonexistent")
    assert res.status_code == 404


def test_get_floor():
    res = client.get("/buildings/bldg-001/floors/1")
    assert res.status_code == 200
    assert res.json()["type"] == "FeatureCollection"


def test_get_floor_not_found():
    res = client.get("/buildings/bldg-001/floors/99")
    assert res.status_code == 404


def test_query_destination_stub():
    res = client.post("/query/destination", json={"text": "강의실 101", "building_id": "bldg-001"})
    assert res.status_code == 200
    assert res.json()["status"] == "stub"


def test_query_info_stub():
    res = client.post("/query/info", json={"text": "화장실 위치", "building_id": "bldg-001"})
    assert res.status_code == 200
    assert res.json()["status"] == "stub"
