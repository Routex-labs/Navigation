"""벡터 타일(MVT) HTTP API 통합 테스트."""

import mapbox_vector_tile

from tests.conftest import BUILDING_ID, FLOOR_NAME, REAL_BUILDING_ID, REAL_FLOOR_NAME


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


# 타일은 gzip이 평균 48% 줄이는 응답이다(app/main.py 미들웨어 주석의 실측 참고).
# 미들웨어가 빠지면 전송량이 조용히 두 배가 되므로 계약으로 고정한다.
#
# **합성 픽스처(test-tower)가 아니라 실데이터 클라이언트를 쓰는 이유**: GZipMiddleware는
# `minimum_size`(500바이트) 미만을 압축하지 않는데, test-tower의 z0 타일은 매장이
# 몇 개뿐이라 그 아래다. 픽스처로 테스트하면 미들웨어가 붙어 있어도 실패한다.
def test_타일_응답은_gzip으로_압축된다(real_api_client):
    response = real_api_client.get(
        f"/buildings/{REAL_BUILDING_ID}/floors/{REAL_FLOOR_NAME}/tiles/0/0/0.mvt",
        headers={"Accept-Encoding": "gzip"},
    )

    assert response.status_code == 200
    assert response.headers["content-encoding"] == "gzip"
    # 중간 캐시가 압축본을 비압축 요청에 주지 않도록 Vary가 반드시 붙어야 한다.
    assert "accept-encoding" in response.headers["vary"].lower()
    # httpx가 자동으로 풀어 주므로 본문은 그대로 MVT로 디코딩된다.
    assert mapbox_vector_tile.decode(response.content)


# gzip을 못 받는 클라이언트에게는 그대로 원본을 준다. 미들웨어가 Accept-Encoding을
# 무시하고 압축하면 MapLibre 네이티브가 타일을 못 읽는다.
def test_gzip을_받지_않는_클라이언트에는_원본을_준다(real_api_client):
    response = real_api_client.get(
        f"/buildings/{REAL_BUILDING_ID}/floors/{REAL_FLOOR_NAME}/tiles/0/0/0.mvt",
        headers={"Accept-Encoding": "identity"},
    )

    assert response.status_code == 200
    assert "content-encoding" not in response.headers
    assert mapbox_vector_tile.decode(response.content)
