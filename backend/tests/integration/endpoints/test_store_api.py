"""매장 검색 HTTP API 통합 테스트.

합성 픽스처(test-tower) 기준. 1F/2F에 각각 가게A·가게B가 있다.
"""

from tests.conftest import BUILDING_ID


# 검색어가 포함된 매장을 반환하는지 검증한다.
def test_검색어로_매장을_조회한다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/stores", params={"q": "가게A"})

    assert response.status_code == 200
    stores = response.json()
    # 같은 이름의 매장이 층마다 있으므로 두 층 모두에서 잡혀야 한다.
    assert sorted(store["id"] for store in stores) == ["shop-a-1f", "shop-a-2f"]
    assert all(store["name"] == "가게A" for store in stores)


# 검색어가 없을 때 건물의 전체 매장(모든 층)을 반환하는지 검증한다.
def test_검색어가_없으면_전체_매장을_조회한다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/stores")

    assert response.status_code == 200
    assert sorted(store["id"] for store in response.json()) == [
        "shop-a-1f",
        "shop-a-2f",
        "shop-b-1f",
        "shop-b-2f",
    ]
