"""건물 그래프가 타 건물로 새는 전이 간선을 배제하는지 검증.

검증 기준:
    수직 전이 간선은 floor_id가 없어 건물 스코프가 없다. get_building_graph는 양 끝
    노드가 모두 그 건물 소속인 전이 간선만 실어야 한다 — from만 확인하면 to가 다른
    건물인 간선이 딸려 와 그래프에 없는 노드를 가리키는 dangling 간선이 응답에 샌다.
"""

from __future__ import annotations

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import app.models  # noqa: F401
from app.core.database import enable_sqlite_pragmas
from app.models import Building, Edge, Floor, Node
from app.models.base import Base
from app.repositories import building_queries


@pytest.fixture
def session(tmp_path):
    engine = create_engine(f"sqlite:///{(tmp_path / 'cross.db').as_posix()}")
    enable_sqlite_pragmas(engine)
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    # 건물 A(층 둘, 각 층 노드 하나)와 건물 B(층 하나, 노드 하나).
    session.add_all(
        [
            Building(id="A", name="A"),
            Building(id="B", name="B"),
            Floor(id="a1", building_id="A", name="1F", level=1),
            Floor(id="a2", building_id="A", name="2F", level=2),
            Floor(id="b1", building_id="B", name="1F", level=1),
            Node(id="A:n1", floor_id="a1", type="elevator", x_m=0.0, y_m=0.0),
            Node(id="A:n2", floor_id="a2", type="elevator", x_m=0.0, y_m=0.0),
            Node(id="B:n1", floor_id="b1", type="elevator", x_m=0.0, y_m=0.0),
        ]
    )
    # 건물 A 안의 정상 전이(1F↔2F)와, A→B로 새는 전이 간선.
    session.add_all(
        [
            Edge(
                id="xfer_ok",
                floor_id=None,
                from_node_id="A:n1",
                to_node_id="A:n2",
                length_m=4.5,
                cost_m=40.0,
                transfer_mode="elevator",
            ),
            Edge(
                id="xfer_cross",
                floor_id=None,
                from_node_id="A:n1",
                to_node_id="B:n1",
                length_m=4.5,
                cost_m=40.0,
                transfer_mode="elevator",
            ),
        ]
    )
    session.commit()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def test_타_건물로_새는_전이간선은_배제된다(session):
    graph = building_queries.get_building_graph(session, "A")
    edge_ids = {edge["id"] for edge in graph["edges"]}
    assert "xfer_ok" in edge_ids  # 건물 A 내부 전이는 실린다
    assert "xfer_cross" not in edge_ids  # A→B로 새는 전이는 빠진다

    # 남은 모든 간선의 endpoint가 그래프 노드 안에 있다(dangling 없음).
    node_ids = {node["id"] for node in graph["nodes"]}
    for edge in graph["edges"]:
        assert edge["from"] in node_ids
        assert edge["to"] in node_ids
