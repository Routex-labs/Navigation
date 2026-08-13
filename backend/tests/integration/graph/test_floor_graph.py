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


# 입구(=원본 POI 핀) 좌표를 wgs84로도 내려보내는지 검증한다.
#
# **화면이 이 키를 오래 전부터 읽고 있었는데 서버가 보내지 않았다.** 한 폴리곤에
# 매장이 여럿 붙은 자리(실데이터 31곳·91매장)에서 centroid는 전부 같은 값이라,
# 라벨을 흩어 각각 누를 수 있게 만드는 근거가 이 좌표뿐이다
# (client/lib/widgets/store_label_anchor.dart). 죽은 폴백으로 되돌아가지 않게
# 계약을 여기서 고정한다.
def test_층_지도가_입구_좌표를_wgs84로도_내려준다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}")

    assert response.status_code == 200
    shop_a = next(store for store in response.json()["stores"] if store["name"] == "가게A")

    assert shop_a["entrance_local_m"] == {"x": 30.0, "y": 40.0}
    entrance = shop_a["entrance_wgs84"]
    assert entrance is not None
    # 픽스처는 입구와 중심이 같은 점이라, 같은 변환을 거치면 값도 같아야 한다.
    assert entrance == shop_a["centroid_wgs84"]


# 층 지도 응답의 간선 키가 alias(from/to)인지 검증한다.
#
# **이 엔드포인트만 따로 지켜야 한다.** ETag를 뽑으려고 model_dump_json()을 직접
# 부르는데, 그 기본값은 by_alias=False라 alias가 적용되지 않는다. 그러면 같은
# DTO를 쓰는 /floors/{floor}/graph는 from/to인데 여기만 from_node_id/to_node_id로
# 나가 한 배포 안에서 계약이 갈린다. 클라이언트에서는 조용한 파싱 예외가 되어
# 층 도면·그래프가 통째로 null이 되고, 층 외곽선·카메라 fit·매장 탭·검색 포커스가
# 한꺼번에 죽는다(화면에는 원인 단서가 남지 않는다).
def test_층_지도_그래프_간선은_from_to_alias로_나간다(api_client):
    body = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}").json()
    edge = body["navigation_graph"]["edges"][0]

    assert "from" in edge and "to" in edge
    assert "from_node_id" not in edge and "to_node_id" not in edge

    # 같은 DTO를 쓰는 전용 그래프 엔드포인트와 키가 정확히 같아야 한다.
    graph_edge = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/graph").json()["edges"][0]
    assert set(edge) == set(graph_edge)


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


# 층 지도는 층을 전환할 때마다 요청되는데 재시드 전까지 내용이 같다. 캐시
# 헤더가 없으면 그 전부가 본문째로 다시 흐른다 — 같은 라우터의 타일·상세
# 엔드포인트와 동일한 짧은 캐시 + ETag 재검증 계약을 고정한다.
def test_층_지도_응답에_캐시_헤더가_붙는다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}")

    assert response.status_code == 200
    assert response.headers["cache-control"] == "public, max-age=60"
    assert response.headers["etag"]


def test_층_지도는_ETag가_같으면_본문없는_304를_돌려준다(api_client):
    url = f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}"
    etag = api_client.get(url).headers["etag"]

    response = api_client.get(url, headers={"If-None-Match": etag})

    assert response.status_code == 304
    assert response.content == b""
    # 304에도 헤더를 붙여야 브라우저가 만료 시각을 갱신한다.
    assert response.headers["cache-control"] == "public, max-age=60"


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
