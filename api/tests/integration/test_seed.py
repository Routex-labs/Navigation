"""시드한 지도 데이터를 ORM과 API가 사용할 수 있는지 검증한다.

SQL 문자열 저장 여부가 아니라, 시드 후 핵심 관계(층-노드-간선-매장 폴리곤)가
유효한지를 확인한다.
"""

from sqlalchemy import select

from app.models import Building, Edge, Floor, Node, Store
from tests.conftest import BUILDING_ID, FLOOR_NAME


# 시드된 건물·층·그래프가 ORM으로 조회되고 관계가 유효한지 검증한다.
def test_시드데이터가_ORM_지도그래프로_조회된다(db_session):
    building = db_session.get(Building, BUILDING_ID)
    assert building is not None

    floor = db_session.scalars(
        select(Floor).where(
            Floor.building_id == BUILDING_ID,
            Floor.name == FLOOR_NAME,
        )
    ).one()

    nodes = db_session.scalars(select(Node).where(Node.floor_id == floor.id)).all()
    edges = db_session.scalars(select(Edge).where(Edge.floor_id == floor.id)).all()
    node_ids = {node.id for node in nodes}

    # 빈 목록에서는 all(...)이 True가 되므로 존재 여부를 먼저 확인한다.
    assert nodes and all(node.floor_id == floor.id for node in nodes)
    assert edges and all(
        edge.floor_id == floor.id
        and edge.from_node_id in node_ids
        and edge.to_node_id in node_ids
        for edge in edges
    )
    assert any(len(edge.geometry) >= 2 for edge in edges)


# stores JSON의 매장 경계가 Store.polygon에 그대로 보존되는지 검증한다.
def test_시드데이터에_매장_폴리곤이_있다(db_session):
    floor = db_session.scalars(
        select(Floor).where(
            Floor.building_id == BUILDING_ID,
            Floor.name == FLOOR_NAME,
        )
    ).one()

    stores = db_session.scalars(select(Store).where(Store.floor_id == floor.id)).all()
    assert sorted(store.id for store in stores) == ["shop-a-1f", "shop-b-1f"]
    # 1F는 기준층이라 정규화가 항등 → 픽스처 좌표가 변형 없이 저장돼야 한다.
    shop_a = next(store for store in stores if store.id == "shop-a-1f")
    assert shop_a.polygon == [
        {"x": 25.0, "y": 35.0},
        {"x": 35.0, "y": 35.0},
        {"x": 35.0, "y": 45.0},
        {"x": 25.0, "y": 45.0},
    ]
    assert (shop_a.centroid_x_m, shop_a.centroid_y_m) == (30.0, 40.0)
    assert all(store.polygon for store in stores)
