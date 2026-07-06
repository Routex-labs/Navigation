"""
API 통합 테스트.

TestClient로 HTTP 왕복 전체(라우팅 → DI → service → SQLite → 직렬화)를 검증한다.
데이터는 실데이터(navigation_1f.json)를 적재한 임시 SQLite.
"""

from tests.conftest import BUILDING_ID, FLOOR_NAME


def test_헬스체크(api_client):
    response = api_client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_건물_목록_조회(api_client):
    response = api_client.get("/buildings")

    assert response.status_code == 200
    buildings = response.json()
    assert isinstance(buildings, list)
    assert buildings[0]["id"] == BUILDING_ID
    assert buildings[0]["floors"] == [FLOOR_NAME]


def test_건물_단건_조회(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}")

    assert response.status_code == 200
    body = response.json()
    assert body["id"] == BUILDING_ID
    assert body["area_m2"] > 16000
    assert len(body["footprint_local_m"]) >= 4


def test_없는_건물_404(api_client):
    response = api_client.get("/buildings/nonexistent")

    assert response.status_code == 404
    assert response.json()["detail"] == "Building not found"


def test_층_지도_조회(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}")

    assert response.status_code == 200
    body = response.json()
    assert body["floor"]["name"] == FLOOR_NAME
    assert len(body["stores"]) == 61
    assert len(body["pois"]) == 47


def test_없는_층_404(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/99F")

    assert response.status_code == 404
    assert response.json()["detail"] == "Floor not found"


def test_층_그래프_조회(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/graph")

    assert response.status_code == 200
    body = response.json()
    assert len(body["nodes"]) == 234
    assert len(body["edges"]) == 282


def test_매장_검색(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/stores", params={"q": "베네타"})

    assert response.status_code == 200
    stores = response.json()
    assert len(stores) >= 1
    assert any("베네타" in s["name"] for s in stores)


def test_매장_검색_전체(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/stores")

    assert response.status_code == 200
    assert len(response.json()) == 61


def test_목적지_질의_스텁(api_client):
    payload = {"text": "구찌 어디야", "building_id": BUILDING_ID}

    response = api_client.post("/query/destination", json=payload)

    body = response.json()
    assert response.status_code == 200
    assert body["status"] == "stub"
    assert body["query"] == payload["text"]
    assert body["result"] is None


def test_정보_질의_스텁(api_client):
    payload = {"text": "화장실 위치", "building_id": BUILDING_ID}

    response = api_client.post("/query/info", json=payload)

    body = response.json()
    assert response.status_code == 200
    assert body["status"] == "stub"
    assert body["query"] == payload["text"]
    assert body["result"] is None