"""매장 검색 HTTP API 통합 테스트."""

from tests.conftest import BUILDING_ID


# 검색어가 포함된 매장을 반환하는지 검증한다.
def test_검색어로_매장을_조회한다(api_client):
    response = api_client.get(
        f"/buildings/{BUILDING_ID}/stores",
        params={"q": "베네타"},
    )

    assert response.status_code == 200
    stores = response.json()
    assert len(stores) >= 1
    assert any("베네타" in store["name"] for store in stores)


# 검색어가 없을 때 건물의 전체 매장을 반환하는지 검증한다.
def test_검색어가_없으면_전체_매장을_조회한다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/stores")

    assert response.status_code == 200
    assert len(response.json()) == 61
