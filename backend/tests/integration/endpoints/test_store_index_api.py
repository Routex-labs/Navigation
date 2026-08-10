"""자동완성용 경량 매장 목록(`/store-index`) HTTP API 통합 테스트.

합성 픽스처(test-tower) 기준. 1F/2F에 각각 가게A·가게B가 있다.
설계 근거는 docs/client/search-input-assist.md K절.
"""

from tests.conftest import BUILDING_ID, REAL_BUILDING_ID

# 이 엔드포인트의 존재 이유 — 좌표·폴리곤을 싣지 않는다는 계약. 하나라도 새면
# 응답이 다시 1MB 쪽으로 돌아가므로 필드 이름을 직접 못박아 둔다.
COORDINATE_FIELDS = {
    "polygon_local_m",
    "polygon_wgs84",
    "centroid_local_m",
    "centroid_wgs84",
    "entrance_local_m",
}

EXPECTED_FIELDS = {
    "id",
    "name",
    "floor_id",
    "floor_name",
    "category",
    "subcategory",
    # 상세와 같은 분류. 이 목록에는 상세를 열지 않는 주차·에스컬레이터·엘리베이터가
    # 61% 섞여 있어서, 매장만 골라야 하는 화면(근처 매장)이 규칙을 다시 만들지 않도록
    # 서버가 함께 준다.
    "kind",
    "entrance_node_id",
}


# 앱이 1회 받아 온디바이스 검색에 쓰는 목록이므로 건물의 전 층 매장이 빠짐없이 와야 한다.
def test_건물의_전체_매장을_반환한다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/store-index")

    assert response.status_code == 200
    stores = response.json()
    assert sorted(store["id"] for store in stores) == [
        "shop-a-1f",
        "shop-a-2f",
        "shop-b-1f",
        "shop-b-2f",
    ]
    # 기존 전체 목록(`/stores`)과 같은 집합이어야 한다. 경량화로 매장이 누락되면
    # 자동완성에서만 조용히 안 잡히는 매장이 생긴다.
    full = api_client.get(f"/buildings/{BUILDING_ID}/stores").json()
    assert {store["id"] for store in stores} == {store["id"] for store in full}


# 자동완성 한 줄을 그리는 데 필요한 필드가 전부 채워지는지 검증한다.
def test_자동완성에_필요한_필드를_모두_담는다(api_client):
    stores = api_client.get(f"/buildings/{BUILDING_ID}/store-index").json()

    for store in stores:
        assert set(store) == EXPECTED_FIELDS
        assert store["name"]
        # 층 라벨을 함께 주는 이유 — 클라이언트가 건물 응답과 다시 조인하지 않고
        # "가게A · 1F"를 바로 그릴 수 있어야 한다.
        assert store["floor_name"] in {"1F", "2F"}
        assert store["floor_id"] in {"FL-TEST-1F", "FL-TEST-2F"}

    shop_a = next(store for store in stores if store["id"] == "shop-a-1f")
    assert shop_a["name"] == "가게A"
    assert shop_a["floor_name"] == "1F"
    assert shop_a["category"] == "패션"
    assert shop_a["subcategory"] == "여성패션"
    # 후보를 고른 즉시 길찾기로 이어지려면 도착 노드가 있어야 한다.
    assert shop_a["entrance_node_id"]

    # 카테고리가 없는 매장도 목록에서 빠지지 않고 null로 실린다.
    shop_b = next(store for store in stores if store["id"] == "shop-b-1f")
    assert shop_b["category"] is None
    assert shop_b["subcategory"] is None


# kind는 상세(`/places/{id}`)와 **같은 값**이어야 한다. 두 곳이 갈리면 "목록에는
# 있는데 눌러도 상세가 안 열리는" 매장이 조용히 생기고, 그 반대(근처 매장 목록에
# 주차구역이 섞임)도 마찬가지다. 규칙의 단일 출처는 classify_place_kind다.
def test_kind가_상세와_같은_값이다(real_api_client):
    stores = real_api_client.get(f"/buildings/{REAL_BUILDING_ID}/store-index").json()

    assert {store["kind"] for store in stores} <= {"store", "facility", "excluded"}

    # 실데이터에는 세 종류가 모두 있다. 하나라도 비면 이 검증이 아무것도 보지 않는다.
    excluded = [store for store in stores if store["kind"] == "excluded"]
    facilities = [store for store in stores if store["kind"] == "facility"]
    assert excluded and facilities

    for sample in (excluded[0], facilities[0]):
        detail = real_api_client.get(f"/buildings/{REAL_BUILDING_ID}/places/{sample['id']}").json()
        assert detail["kind"] == sample["kind"]


# 폴리곤·좌표가 빠졌는지 검증한다. 이 엔드포인트를 신설한 이유 그 자체다.
def test_폴리곤과_좌표를_싣지_않는다(api_client):
    stores = api_client.get(f"/buildings/{BUILDING_ID}/store-index").json()

    assert stores
    for store in stores:
        assert not COORDINATE_FIELDS & set(store)

    # 기존 `/stores`에는 그 좌표들이 그대로 있어야 한다. 둘의 차이가 곧 절감분이고,
    # 기존 계약을 건드리지 않았다는 확인이기도 하다.
    full = api_client.get(f"/buildings/{BUILDING_ID}/stores").json()
    assert COORDINATE_FIELDS <= set(full[0])


# 응답 순서가 매 호출 같아야 클라이언트가 인덱스를 캐시할 수 있다.
def test_응답_순서가_결정적이다(api_client):
    first = api_client.get(f"/buildings/{BUILDING_ID}/store-index").json()
    second = api_client.get(f"/buildings/{BUILDING_ID}/store-index").json()

    assert [store["id"] for store in first] == [store["id"] for store in second]
    # 층은 위층부터(건물 요약의 층 순서와 동일), 층 안에서는 id 오름차순.
    assert [store["id"] for store in first] == [
        "shop-a-2f",
        "shop-b-2f",
        "shop-a-1f",
        "shop-b-1f",
    ]


# 없는 건물은 빈 목록이 아니라 404여야 한다(기존 `/stores`와 같은 계약).
def test_없는_건물은_찾을수없음_응답을_반환한다(api_client):
    response = api_client.get("/buildings/nonexistent/store-index")

    assert response.status_code == 404
    assert response.json()["detail"] == "Building not found"


# 실데이터에서도 전 층이 실리고 필수 필드가 채워지는지 스모크 확인한다.
def test_실데이터에서_전_층_매장이_실린다(real_api_client):
    response = real_api_client.get(f"/buildings/{REAL_BUILDING_ID}/store-index")

    assert response.status_code == 200
    stores = response.json()
    # 매장 수는 편집으로 계속 바뀌므로 값이 아니라 불변식만 본다.
    assert len(stores) > 100
    assert len({store["floor_name"] for store in stores}) > 1
    for store in stores:
        assert set(store) == EXPECTED_FIELDS
        assert store["id"] and store["name"] and store["floor_id"] and store["floor_name"]
