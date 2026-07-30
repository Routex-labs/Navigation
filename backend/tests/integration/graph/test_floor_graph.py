"""층 지도와 길찾기 그래프 HTTP API 통합 테스트.

합성 픽스처(test-tower)를 시드하므로 응답 값을 그대로 단언한다.
픽스처 1F: 노드 8(엘리베이터 4·분기 2·매장입구 2) · 간선 7 · 매장 2.
"""

from tests.conftest import BUILDING_ID, FLOOR_NAME

FIXTURE_NODE_COUNT = 8
FIXTURE_EDGE_COUNT = 7
FIXTURE_POI_COUNT = 4  # 엘리베이터 4개가 POI로 승격된다


# 층 지도 API가 층 정보와 매장·관심 지점을 반환하는지 검증한다.
def test_층_지도를_조회한다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}")

    assert response.status_code == 200
    body = response.json()
    assert body["floor"]["name"] == FLOOR_NAME
    assert [store["name"] for store in body["stores"]] == ["가게A", "가게B"]
    assert len(body["pois"]) == FIXTURE_POI_COUNT
    assert {poi["name"] for poi in body["pois"]} == {
        "엘리베이터A",
        "엘리베이터B",
        "엘리베이터C",
        "엘리베이터D",
    }


# 층 지도 응답에 Studio 그래프와 매장 폴리곤이 포함되는지 검증한다.
def test_층_지도에_Studio_그래프와_매장_폴리곤을_응답한다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}")

    assert response.status_code == 200
    body = response.json()
    assert body["navigation_coordinate_system"] == "local_m"
    assert body["map_calibration_version"] == "unversioned"
    assert len(body["navigation_graph"]["nodes"]) == FIXTURE_NODE_COUNT
    assert len(body["navigation_graph"]["edges"]) == FIXTURE_EDGE_COUNT

    shop_a = next(store for store in body["stores"] if store["name"] == "가게A")
    # 1F는 기준층이라 정규화가 항등이다 → Studio가 준 local_m이 그대로 보존돼야 한다.
    assert shop_a["polygon_local_m"] == [
        {"x": 25.0, "y": 35.0},
        {"x": 35.0, "y": 35.0},
        {"x": 35.0, "y": 45.0},
        {"x": 25.0, "y": 45.0},
    ]
    assert shop_a["centroid_local_m"] == {"x": 30.0, "y": 40.0}
    # wgs84 폴리곤도 같은 꼭짓점 수로 함께 내려온다.
    assert len(shop_a["polygon_wgs84"]) == len(shop_a["polygon_local_m"])
    assert all(store["polygon_local_m"] is not None for store in body["stores"])


# 건물 외곽이 Studio '테두리' 입력 그대로 응답에 실리는지 검증한다.
def test_층_지도에_건물_외곽이_실린다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}")

    body = response.json()
    assert body["footprint_local_m"] == [
        {"x": 0.0, "y": 0.0},
        {"x": 100.0, "y": 0.0},
        {"x": 100.0, "y": 80.0},
        {"x": 0.0, "y": 80.0},
    ]
    assert len(body["footprint_wgs84"]) == 4


# 존재하지 않는 층 요청이 찾을 수 없음 응답으로 변환되는지 검증한다.
def test_없는_층은_찾을수없음_응답을_반환한다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/99F")

    assert response.status_code == 404
    assert response.json()["detail"] == "Floor not found"


# 층 그래프 API가 저장된 노드와 간선을 반환하는지 검증한다.
def test_층_그래프를_조회한다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/graph")

    assert response.status_code == 200
    body = response.json()
    assert len(body["nodes"]) == FIXTURE_NODE_COUNT
    assert len(body["edges"]) == FIXTURE_EDGE_COUNT
    # 노드 ID는 층 스코프로 네임스페이싱된다(층 간 ID 충돌 방지).
    assert {node["id"] for node in body["nodes"]} == {
        "FL-TEST-1F:EV-A",
        "FL-TEST-1F:EV-B",
        "FL-TEST-1F:EV-C",
        "FL-TEST-1F:EV-D",
        "FL-TEST-1F:J-N",
        "FL-TEST-1F:J-S",
        "FL-TEST-1F:S-1",
        "FL-TEST-1F:S-2",
    }


# 층 그래프에는 층 내부 간선만 있고 수직 전이 간선은 섞이지 않아야 한다.
def test_층_그래프에_수직_전이_간선은_포함되지_않는다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/graph")

    body = response.json()
    assert not [edge for edge in body["edges"] if edge["id"].startswith("xfer:")]
