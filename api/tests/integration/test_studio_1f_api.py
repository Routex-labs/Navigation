"""Studio 1F 데이터만 시드한 층 지도 API 통합 테스트."""

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import app.models  # noqa: F401
from app.core.database import get_db
from app.main import create_app
from app.models.base import Base
from scripts.studio_adapter import seed_studio


def test_studio_1f_층지도는_그래프와_매장_폴리곤을_함께_응답한다(tmp_path):
    """레거시 JSON 없이 Studio 1F만으로 프런트의 최초 호출을 만족한다."""
    database_path = tmp_path / "studio-1f.db"
    engine = create_engine(
        f"sqlite:///{database_path.as_posix()}",
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine)

    session = session_factory()
    try:
        seed_studio(["1f"], session=session)
        session.commit()
    finally:
        session.close()

    app = create_app()

    def override_get_db():
        session = session_factory()
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_db] = override_get_db
    try:
        with TestClient(app) as client:
            response = client.get("/buildings/thehyundai-seoul/floors/1F")
    finally:
        app.dependency_overrides.clear()
        engine.dispose()

    assert response.status_code == 200
    body = response.json()
    assert len(body["navigation_graph"]["nodes"]) == 167
    assert len(body["navigation_graph"]["edges"]) == 294
    assert len(body["stores"]) == 59
    assert sum(store["polygon_local_m"] is not None for store in body["stores"]) == 57
