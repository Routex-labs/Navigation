"""벡터 타일(MVT) HTTP API 통합 테스트."""

import mapbox_vector_tile

from tests.conftest import BUILDING_ID, FLOOR_NAME


# 시드 데이터 지역(서울)을 덮는 낮은 줌 타일 하나면 항상 존재/디코딩 가능해야 한다.
def test_유효한_타일을_MVT로_디코딩할_수_있다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/tiles/0/0/0.mvt")

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/vnd.mapbox-vector-tile"
    decoded = mapbox_vector_tile.decode(response.content)
    assert set(decoded) <= {"footprint", "stores", "pois"}


def test_존재하지_않는_건물의_타일은_찾을수없음_응답을_반환한다(api_client):
    response = api_client.get(f"/buildings/nonexistent/floors/{FLOOR_NAME}/tiles/0/0/0.mvt")

    assert response.status_code == 404
    assert response.json()["detail"] == "Floor not found"


def test_존재하지_않는_층의_타일은_찾을수없음_응답을_반환한다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/99F/tiles/0/0/0.mvt")

    assert response.status_code == 404
    assert response.json()["detail"] == "Floor not found"


def test_범위를_벗어난_타일_좌표는_잘못된요청_응답을_반환한다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/tiles/-1/0/0.mvt")

    assert response.status_code == 400


# 헤더가 없으면 MapLibre가 같은 타일을 줌 전환·층 재방문마다 다시 받아 간다.
def test_타일_응답에_캐시_헤더가_붙는다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/tiles/0/0/0.mvt")

    assert response.status_code == 200
    assert response.headers["cache-control"] == "public, max-age=60"
    assert response.headers["etag"]


def test_같은_타일은_같은_ETag를_돌려준다(api_client):
    url = f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/tiles/0/0/0.mvt"

    first = api_client.get(url)
    second = api_client.get(url)

    assert first.headers["etag"] == second.headers["etag"]


def test_ETag가_같으면_본문없는_304를_돌려준다(api_client):
    url = f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/tiles/0/0/0.mvt"
    etag = api_client.get(url).headers["etag"]

    response = api_client.get(url, headers={"If-None-Match": etag})

    assert response.status_code == 304
    assert response.content == b""
    # 304에도 헤더를 붙여야 브라우저가 만료 시각을 갱신한다.
    assert response.headers["cache-control"] == "public, max-age=60"


def test_ETag가_다르면_본문을_다시_내려준다(api_client):
    url = f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/tiles/0/0/0.mvt"

    response = api_client.get(url, headers={"If-None-Match": '"stale"'})

    assert response.status_code == 200
    assert response.content
