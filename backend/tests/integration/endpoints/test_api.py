"""서버 상태와 건물 HTTP API 통합 테스트."""

from tests.conftest import BUILDING_ID, DEFAULT_FLOOR, FLOOR_NAMES


# 서버 생존 확인 API가 정상 상태를 반환하는지 검증한다.
def test_서버_상태를_정상적으로_조회한다(api_client):
    response = api_client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


# 건물 목록 API가 저장된 건물 요약을 반환하는지 검증한다.
def test_건물_목록을_조회한다(api_client):
    response = api_client.get("/buildings")

    assert response.status_code == 200
    buildings = response.json()
    assert isinstance(buildings, list)
    assert buildings[0]["id"] == BUILDING_ID
    assert buildings[0]["floors"] == FLOOR_NAMES
    assert buildings[0]["default_floor"] == DEFAULT_FLOOR


# Studio 건물 상세 API가 현재 제공하는 메타데이터를 검증한다.
def test_건물_상세를_조회한다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}")

    assert response.status_code == 200
    body = response.json()
    assert body["id"] == BUILDING_ID
    assert body["area_m2"] is None
    # Studio '테두리' 도구로 찍은 건물 외곽이 그대로 실린다.
    assert body["footprint_local_m"] == [
        {"x": 0.0, "y": 0.0},
        {"x": 100.0, "y": 0.0},
        {"x": 100.0, "y": 80.0},
        {"x": 0.0, "y": 80.0},
    ]
    # 야외 지도용 wgs84 외곽선. local_m 꼭지점 개수만큼 lat/lng 쌍이 실려야 한다.
    assert isinstance(body["footprint_wgs84"], list)
    assert len(body["footprint_wgs84"]) == len(body["footprint_local_m"])
    for point in body["footprint_wgs84"]:
        assert set(point) == {"lat", "lng"}
        assert isinstance(point["lat"], float) and isinstance(point["lng"], float)


# 존재하지 않는 건물 요청이 찾을 수 없음 응답으로 변환되는지 검증한다.
def test_없는_건물은_찾을수없음_응답을_반환한다(api_client):
    response = api_client.get("/buildings/nonexistent")

    assert response.status_code == 404
    assert response.json()["detail"] == "Building not found"


# 카테고리 필터가 층 지도를 층마다 받지 않고 이 응답 하나로 pill과 개수를 만든다.
def test_카테고리_개수를_층_대분류_소분류로_묶어_반환한다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/categories")

    assert response.status_code == 200
    rows = response.json()
    assert rows, "픽스처 건물에 카테고리가 붙은 매장이 있어야 한다"
    for row in rows:
        assert set(row) == {"floor", "category", "subcategory", "count"}
        assert row["floor"] in FLOOR_NAMES
        assert row["count"] >= 1

    # 같은 (층·대분류·소분류)가 두 줄로 나뉘면 클라이언트가 개수를 두 번 센다.
    keys = [(r["floor"], r["category"], r["subcategory"]) for r in rows]
    assert len(keys) == len(set(keys))


# 대분류가 없는 매장은 pill을 만들 수 없어 응답에서 빠진다.
def test_카테고리_개수에_대분류_없는_매장은_빠진다(api_client):
    rows = api_client.get(f"/buildings/{BUILDING_ID}/categories").json()

    assert all(row["category"] for row in rows)


def test_없는_건물의_카테고리는_찾을수없음_응답을_반환한다(api_client):
    response = api_client.get("/buildings/nonexistent/categories")

    assert response.status_code == 404
    assert response.json()["detail"] == "Building not found"
