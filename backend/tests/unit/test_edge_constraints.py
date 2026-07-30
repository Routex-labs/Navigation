"""Edge 모델의 DB CheckConstraint 검증.

검증 기준:
    손상된 간선(음수 거리/비용, 자기 참조, 미지의 전이 수단)은 commit 전에
    IntegrityError로 거부된다 — 주석·시드 로직이 아니라 DB가 강제한다.
"""

from __future__ import annotations

import pytest
from sqlalchemy import create_engine
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

import app.models  # noqa: F401  # 모든 모델을 Base.metadata에 등록
from app.core.database import enable_sqlite_pragmas
from app.models import Building, Edge, Floor, Node
from app.models.base import Base


@pytest.fixture
def session(tmp_path):
    engine = create_engine(f"sqlite:///{(tmp_path / 'edges.db').as_posix()}")
    enable_sqlite_pragmas(engine)
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    # 간선의 FK 대상이 되도록 최소 그래프(건물·층·노드 2개)를 미리 심는다.
    session.add(Building(id="b1", name="건물"))
    session.add(Floor(id="f1", building_id="b1", name="1F", level=1))
    session.add(Node(id="n1", floor_id="f1", type="junction", x_m=0.0, y_m=0.0))
    session.add(Node(id="n2", floor_id="f1", type="junction", x_m=1.0, y_m=0.0))
    session.commit()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _add_edge(session: Session, **overrides) -> None:
    defaults = dict(
        id="e1",
        floor_id="f1",
        from_node_id="n1",
        to_node_id="n2",
        length_m=1.0,
        cost_m=1.0,
        bidirectional=True,
    )
    defaults.update(overrides)
    session.add(Edge(**defaults))
    session.commit()


def test_정상_간선은_저장된다(session):
    _add_edge(session)
    assert session.get(Edge, "e1") is not None


def test_음수_거리는_거부된다(session):
    with pytest.raises(IntegrityError):
        _add_edge(session, length_m=-1.0)


def test_음수_비용은_거부된다(session):
    with pytest.raises(IntegrityError):
        _add_edge(session, cost_m=-0.5)


def test_자기_자신을_잇는_간선은_거부된다(session):
    with pytest.raises(IntegrityError):
        _add_edge(session, to_node_id="n1")


def test_미지의_전이수단은_거부된다(session):
    with pytest.raises(IntegrityError):
        _add_edge(session, transfer_mode="stairs")


def test_알려진_전이수단은_허용된다(session):
    # floor_id=None인 전이 간선도 저장돼야 한다(층에 속하지 않음).
    _add_edge(session, floor_id=None, transfer_mode="elevator")
    assert session.get(Edge, "e1") is not None


def test_존재하지_않는_노드를_가리키면_거부된다(session):
    # FK 강제(PRAGMA foreign_keys=ON)가 없으면 조용히 저장되는 고아 참조.
    with pytest.raises(IntegrityError):
        _add_edge(session, to_node_id="does-not-exist")
