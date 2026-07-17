"""
공용 픽스처

테스트는 데이터 출처에 따라 두 갈래다.

1) 합성 픽스처(tests/fixtures/studio/test-tower) — 기본.
   입력이 고정이라 응답 값을 그대로 단언할 수 있다. Studio에서 실데이터를 편집해도
   깨지지 않는다. 2F는 일부러 1F와 다른 local_m 프레임(2배 스케일 + 오프셋)으로
   만들어, 다층 좌표 정규화가 정답을 복원하는지 검증할 수 있게 했다.

2) 실데이터(app/data/studio/thehyundai-seoul) — 스모크용.
   실제 파이프라인이 도는지만 본다. 매장 수 같은 값은 편집으로 계속 바뀌므로
   단언하지 않고 불변식(참조 무결성 등)만 검사한다. real_* 픽스처를 쓴다.
"""

from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import app.models  # noqa: F401  # 모든 모델을 Base.metadata에 등록
from app.core.database import get_db
from app.main import create_app
from app.models.base import Base
from scripts import studio_adapter
from scripts.studio_adapter import seed_studio

FIXTURE_DIR = Path(__file__).parent / "fixtures" / "studio" / "test-tower"

# 합성 픽스처 식별자 — 동작 검증 테스트가 쓴다.
BUILDING_ID = "test-tower"
FLOOR_NAME = "1F"
FLOOR_NAMES = ["1F", "2F"]  # 건물 목록은 지상 저층이 앞(_to_building_summary 참고)
FLOOR_ID = "FL-TEST-1F"

# 실데이터 식별자 — 스모크 테스트가 쓴다.
REAL_BUILDING_ID = "thehyundai-seoul"
REAL_FLOOR_NAME = "1F"


def _seeded_engine(tmp_path_factory, name: str, directory: Path):
    db_path = tmp_path_factory.mktemp(name) / "navigation.db"
    engine = create_engine(
        f"sqlite:///{db_path.as_posix()}",
        # TestClient 요청은 스레드풀에서 실행되므로 스레드 검사를 끈다.
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    try:
        seed_studio(session=session, directory=directory)
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
    return engine


@pytest.fixture(scope="session")
def db_engine(tmp_path_factory):
    """합성 픽스처를 시드한 임시 SQLite (세션당 1회)."""
    engine = _seeded_engine(tmp_path_factory, "db", FIXTURE_DIR)
    yield engine
    engine.dispose()


@pytest.fixture(scope="session")
def real_db_engine(tmp_path_factory):
    """실제 Studio 데이터를 시드한 임시 SQLite (스모크용, 세션당 1회)."""
    engine = _seeded_engine(tmp_path_factory, "real_db", studio_adapter.STUDIO_DIR)
    yield engine
    engine.dispose()


def _make_session_factory(engine):
    return sessionmaker(bind=engine, autocommit=False, autoflush=False)


def _session(factory):
    # 각 테스트에 독립 Session을 제공하고 종료 시 닫는다.
    session = factory()
    yield session
    session.close()


def _client(factory):
    # 실제 앱과 같은 라우터 구성을 사용하되 DB dependency만 시드 DB로 교체한다.
    app = create_app()

    def override_get_db():
        session = factory()
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as client:
        yield client
    # 다른 테스트에 override가 남지 않도록 사용 후 초기화한다.
    app.dependency_overrides.clear()


@pytest.fixture(scope="session")
def session_factory(db_engine):
    return _make_session_factory(db_engine)


@pytest.fixture(scope="session")
def real_session_factory(real_db_engine):
    return _make_session_factory(real_db_engine)


@pytest.fixture
def db_session(session_factory):
    yield from _session(session_factory)


@pytest.fixture
def real_db_session(real_session_factory):
    yield from _session(real_session_factory)


@pytest.fixture
def api_client(session_factory):
    yield from _client(session_factory)


@pytest.fixture
def real_api_client(real_session_factory):
    yield from _client(real_session_factory)
