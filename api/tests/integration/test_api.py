"""서버 상태와 건물 HTTP API 통합 테스트."""

from tests.conftest import BUILDING_ID, FLOOR_NAME, FLOOR_NAMES


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


# 존재하지 않는 건물 요청이 찾을 수 없음 응답으로 변환되는지 검증한다.
def test_없는_건물은_찾을수없음_응답을_반환한다(api_client):
    response = api_client.get("/buildings/nonexistent")

    assert response.status_code == 404
    assert response.json()["detail"] == "Building not found"
