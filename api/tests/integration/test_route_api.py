"""최단 경로 HTTP API 통합 테스트."""

from tests.conftest import BUILDING_ID, FLOOR_NAME


def _first_edge(api_client) -> dict:
    graph = api_client.get(
        f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/graph"
    ).json()
    return graph["edges"][0]


# 그래프 조회부터 최단 경로 좌표 응답까지 전체 흐름을 검증한다.
def test_최단_경로를_조회한다(api_client):
    edge = _first_edge(api_client)

    response = api_client.get(
        f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/route",
        params={
            "start_node_id": edge["from"],
            "end_node_id": edge["to"],
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["path_found"] is True
    assert body["node_ids"][0] == edge["from"]
    assert body["node_ids"][-1] == edge["to"]
    assert len(body["edge_ids"]) >= 1
    assert body["coordinate_system"] == "local_m"
    assert len(body["path_points"]) >= 2
    assert set(body["path_points"][0]) == {"x", "y"}
    assert body["total_distance_m"] >= 0


# 존재하지 않는 출발 노드가 잘못된 요청 응답으로 변환되는지 검증한다.
def test_존재하지_않는_출발_노드는_잘못된요청_응답을_반환한다(api_client):
    edge = _first_edge(api_client)

    response = api_client.get(
        f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/route",
        params={
            "start_node_id": "nonexistent",
            "end_node_id": edge["to"],
        },
    )

    assert response.status_code == 400
    assert "존재하지 않습니다" in response.json()["detail"]


# 존재하지 않는 층의 경로 요청이 찾을 수 없음 응답으로 변환되는지 검증한다.
def test_존재하지_않는_층은_찾을수없음_응답을_반환한다(api_client):
    response = api_client.get(
        f"/buildings/{BUILDING_ID}/floors/99F/route",
        params={"start_node_id": "start", "end_node_id": "end"},
    )

    assert response.status_code == 404
    assert response.json()["detail"] == "Floor not found"
