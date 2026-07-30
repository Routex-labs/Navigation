"""시드 그래프 무결성 게이트(validate_seeded_graph) 통합 테스트.

검증 기준:
    DB 제약은 통과하지만 의미상 잘못된 그래프(같은 층을 잇는 전이 간선)는
    커밋 전 게이트에서 GraphIntegrityError로 중단된다 — 반쯤 시드된 DB를 남기지 않는다.
    정상 그래프는 통계를 담은 리포트를 반환한다.
"""

from __future__ import annotations

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import app.models  # noqa: F401
from app.core.database import enable_sqlite_pragmas
from app.graph.integrity import GraphIntegrityError, validate_seeded_graph
from app.models import Building, Edge, Floor, Node
from app.models.base import Base


@pytest.fixture
def session(tmp_path):
    engine = create_engine(f"sqlite:///{(tmp_path / 'gate.db').as_posix()}")
    enable_sqlite_pragmas(engine)
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    session.add(Building(id="b1", name="건물"))
    session.add(Floor(id="f1", building_id="b1", name="1F", level=1))
    session.add(Node(id="n1", floor_id="f1", type="junction", x_m=0.0, y_m=0.0))
    session.add(Node(id="n2", floor_id="f1", type="elevator", x_m=1.0, y_m=0.0))
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def test_정상_그래프는_리포트를_반환한다(session):
    session.add(Edge(id="e1", floor_id="f1", from_node_id="n1", to_node_id="n2", length_m=1.0, cost_m=1.0))
    report = validate_seeded_graph(session)
    assert report.ok
    assert report.stats["nodes"] == 2


def test_같은_층_전이간선은_게이트에서_막힌다(session):
    # DB는 이 간선을 허용한다(floor_id=None, from<>to, 알려진 전이 수단). 하지만 두 노드가
    # 같은 층이라 의미상 전이가 아니다 — 검증기가 이걸 잡아 게이트가 중단시켜야 한다.
    session.add(
        Edge(
            id="bad",
            floor_id=None,
            from_node_id="n1",
            to_node_id="n2",
            length_m=1.0,
            cost_m=40.0,
            transfer_mode="elevator",
        )
    )
    with pytest.raises(GraphIntegrityError) as excinfo:
        validate_seeded_graph(session)
    assert "transfer_same_floor" in {issue.code for issue in excinfo.value.report.errors}
