"""다층 적재 검증 — 공통 좌표 프레임·수직 전이 간선 생성.

전 층이 하나의 local_m 프레임을 공유한다는 것이 적재 파이프라인의 전제다
(scripts/seed/studio_adapter.py 좌표계 항목). 합성 픽스처(test-tower)도 실제
데이터와 같게 1F/2F가 한 프레임을 쓰므로, 층이 달라도 같은 자리인 엘리베이터는
좌표가 정확히 겹쳐야 한다.

예전에는 적재 단계에서 층마다 아핀을 피팅해 기준층 프레임으로 되돌렸고, 이
파일이 그 복원을 검증했다. 다베오 데이터로 옮기면서 정렬 단계가 사라졌으므로
이제는 "적재가 좌표를 건드리지 않는다"를 확인한다 — 조용히 변형이 끼어들면
건물당 하나뿐인 wgs84 피팅이 무의미해진다.
"""

from sqlalchemy import select

from app.models import Edge, Floor, Node
from tests.conftest import BUILDING_ID


def _nodes_by_floor(session, floor_name):
    floor = session.scalars(select(Floor).where(Floor.building_id == BUILDING_ID, Floor.name == floor_name)).one()
    return {
        node.id.split(":")[-1]: node for node in session.scalars(select(Node).where(Node.floor_id == floor.id)).all()
    }


# 층이 달라도 같은 자리인 엘리베이터는 같은 좌표로 적재돼야 한다.
def test_층이_달라도_같은_자리는_같은_좌표다(db_session):
    first = _nodes_by_floor(db_session, "1F")
    second = _nodes_by_floor(db_session, "2F")

    for node_id in ("EV-A", "EV-B", "EV-C", "EV-D"):
        assert second[node_id].x_m == first[node_id].x_m
        assert second[node_id].y_m == first[node_id].y_m
    assert (second["EV-A"].x_m, second["EV-A"].y_m) == (10.0, 10.0)


# 적재가 좌표를 변형하지 않는지 확인한다. 엘리베이터는 층끼리 겹쳐서 변형이
# 있어도 눈에 안 띌 수 있으므로, 층마다 자리가 다른 매장 입구로 검증한다.
def test_적재가_좌표를_변형하지_않는다(db_session):
    second = _nodes_by_floor(db_session, "2F")

    # 픽스처 2F의 S-1 원본 좌표가 그대로 저장돼야 한다.
    assert (second["S-1"].x_m, second["S-1"].y_m) == (30.0, 40.0)


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
    transfers = db_session.scalars(select(Edge).where(Edge.transfer_mode.is_not(None))).all()

    assert len(transfers) == 4  # 엘리베이터 4개
    assert {edge.transfer_mode for edge in transfers} == {"elevator"}
    # 전이 간선은 특정 층에 속하지 않는다.
    assert all(edge.floor_id is None for edge in transfers)
    # 1F EV-A <-> 2F EV-A 를 잇는다(양방향 간선이라 방향은 따지지 않는다).
    assert {frozenset((edge.from_node_id, edge.to_node_id)) for edge in transfers} == {
        frozenset((f"FL-TEST-1F:{ev}", f"FL-TEST-2F:{ev}")) for ev in ("EV-A", "EV-B", "EV-C", "EV-D")
    }
    assert all(edge.bidirectional for edge in transfers)
