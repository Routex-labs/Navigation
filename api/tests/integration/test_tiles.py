"""벡터 타일(MVT) HTTP API 통합 테스트."""

import mapbox_vector_tile

from tests.conftest import BUILDING_ID, FLOOR_NAME


# 시드 데이터 지역(서울)을 덮는 낮은 줌 타일 하나면 항상 존재/디코딩 가능해야 한다.
def test_유효한_타일을_MVT로_디코딩할_수_있다(api_client):
    response = api_client.get(
        f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/tiles/0/0/0.mvt"
    )

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/vnd.mapbox-vector-tile"
    decoded = mapbox_vector_tile.decode(response.content)
    assert set(decoded) <= {"footprint", "stores", "pois"}


def test_존재하지_않는_건물의_타일은_찾을수없음_응답을_반환한다(api_client):
    response = api_client.get(
        f"/buildings/nonexistent/floors/{FLOOR_NAME}/tiles/0/0/0.mvt"
    )

    assert response.status_code == 404
    assert response.json()["detail"] == "Floor not found"


def test_존재하지_않는_층의_타일은_찾을수없음_응답을_반환한다(api_client):
    response = api_client.get(
        f"/buildings/{BUILDING_ID}/floors/99F/tiles/0/0/0.mvt"
    )

    assert response.status_code == 404
    assert response.json()["detail"] == "Floor not found"


def test_범위를_벗어난_타일_좌표는_잘못된요청_응답을_반환한다(api_client):
    response = api_client.get(
        f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/tiles/-1/0/0.mvt"
    )

    assert response.status_code == 400
