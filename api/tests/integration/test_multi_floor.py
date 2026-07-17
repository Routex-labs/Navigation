"""다층 적재 검증 — 좌표 정규화·수직 전이·층 간 경로.

합성 픽스처(test-tower)는 2F를 일부러 1F와 다른 프레임으로 만들어 뒀다:
    2F_local = 2 * 1F_local + (5, 3)
정규화가 제대로면 2F를 1F(건물) 프레임으로 정확히 되돌려야 하므로,
층이 달라도 같은 자리인 엘리베이터가 정확히 겹쳐야 한다.
"""

from sqlalchemy import select

from app.models import Edge, Floor, Node
from tests.conftest import BUILDING_ID


def _nodes_by_floor(session, floor_name):
    floor = session.scalars(
        select(Floor).where(Floor.building_id == BUILDING_ID, Floor.name == floor_name)
    ).one()
    return {
        node.id.split(":")[-1]: node
        for node in session.scalars(select(Node).where(Node.floor_id == floor.id)).all()
    }


# 2F는 1F와 다른 프레임으로 들어오지만, 적재 후에는 1F 프레임으로 복원돼야 한다.
def test_다른_프레임의_층이_기준층_좌표로_정규화된다(db_session):
    first = _nodes_by_floor(db_session, "1F")
    second = _nodes_by_floor(db_session, "2F")

    # 픽스처 2F 원본은 EV-A가 (25, 23)이지만, 정규화 후 1F와 같은 (10, 10)이 돼야 한다.
    for node_id in ("EV-A", "EV-B", "EV-C", "EV-D"):
        assert second[node_id].x_m == first[node_id].x_m
        assert second[node_id].y_m == first[node_id].y_m
    assert (second["EV-A"].x_m, second["EV-A"].y_m) == (10.0, 10.0)


# 정규화는 엘리베이터뿐 아니라 매장 입구 등 모든 노드에 적용돼야 한다.
def test_정규화가_모든_노드에_적용된다(db_session):
    first = _nodes_by_floor(db_session, "1F")
    second = _nodes_by_floor(db_session, "2F")

    assert (second["S-1"].x_m, second["S-1"].y_m) == (30.0, 40.0)
    assert (second["J-N"].x_m, second["J-N"].y_m) == (first["J-N"].x_m, first["J-N"].y_m)


# 기준층의 local_m -> wgs84 아핀으로 모든 층의 wgs84가 계산돼야 한다.
def test_모든_층의_wgs84가_기준층_변환으로_계산된다(db_session):
    first = _nodes_by_floor(db_session, "1F")
    second = _nodes_by_floor(db_session, "2F")

    # 픽스처 아핀: lng = 126.9280 + x*1.13e-5, lat = 37.5260 - y*0.9e-5
    assert first["EV-A"].lng == round(126.9280 + 10.0 * 1.13e-5, 9)
    assert first["EV-A"].lat == round(37.5260 - 10.0 * 0.9e-5, 9)
    # 같은 자리이므로 2F도 같은 좌표여야 한다.
    assert (second["EV-A"].lat, second["EV-A"].lng) == (first["EV-A"].lat, first["EV-A"].lng)


# 겹치는 엘리베이터마다 수직 전이 간선이 생겨야 한다.
def test_엘리베이터마다_수직_전이_간선이_생성된다(db_session):
    transfers = db_session.scalars(
        select(Edge).where(Edge.transfer_mode.is_not(None))
    ).all()

    assert len(transfers) == 4  # 엘리베이터 4개
    assert {edge.transfer_mode for edge in transfers} == {"elevator"}
    # 전이 간선은 특정 층에 속하지 않는다.
    assert all(edge.floor_id is None for edge in transfers)
    # 1F EV-A <-> 2F EV-A 를 잇는다(양방향 간선이라 방향은 따지지 않는다).
    assert {
        frozenset((edge.from_node_id, edge.to_node_id)) for edge in transfers
    } == {
        frozenset((f"FL-TEST-1F:{ev}", f"FL-TEST-2F:{ev}"))
        for ev in ("EV-A", "EV-B", "EV-C", "EV-D")
    }
    assert all(edge.bidirectional for edge in transfers)


# 건물 전체 경로가 전이 간선을 타고 층을 넘어가는지 검증한다.
def test_건물_경로가_층을_넘어간다(api_client):
    response = api_client.get(
        f"/buildings/{BUILDING_ID}/route",
        params={
            "start_node_id": "FL-TEST-1F:S-1",  # 1F 가게A 입구
            "end_node_id": "FL-TEST-2F:S-2",  # 2F 가게B 입구
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["path_found"] is True
    # 출발/도착 층이 모두 경로에 나타나야 한다.
    floors = {node_id.split(":")[0] for node_id in body["node_ids"]}
    assert floors == {"FL-TEST-1F", "FL-TEST-2F"}
    # 층을 넘으려면 전이 간선을 정확히 한 번 타야 한다.
    assert len([e for e in body["edge_ids"] if e.startswith("xfer:")]) == 1
    assert len(body["path_points_wgs84"]) == len(body["path_points"])


# 단일 층 경로는 전이 간선을 쓰지 않는다.
def test_층_내_경로는_전이_간선을_쓰지_않는다(api_client):
    response = api_client.get(
        f"/buildings/{BUILDING_ID}/floors/1F/route",
        params={"start_node_id": "FL-TEST-1F:S-1", "end_node_id": "FL-TEST-1F:S-2"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["path_found"] is True
    assert not [e for e in body["edge_ids"] if e.startswith("xfer:")]
