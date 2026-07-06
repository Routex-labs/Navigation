"""
공용 픽스처
실 데이터 json 을 etl 로 임시 sqlite 에 적재하여 세션 전체에서 재사용한다.
테스트가 실제 적재 경로를 그대로 검증한다.

api client는 FastAPI의 dependency_overrides 로 get_db만 임시 db로 바꾼다.
"""


import sqlite3

import pytest
from fastapi.testclient import TestClient

from app.FastAPIConfig import create_app, get_db
from app.repository.sqliteBuildingRepository import SqliteBuildingRepository
from scripts.load_dataset import DEFAULT_JSON, load_navigation_db

BUILDING_ID = "thehyundai-seoul"
FLOOR_NAME = "1F"


@pytest.fixture(scope="session")
def navigation_db_path(tmp_path_factory):
    """실데이터 JSON을 임시 SQLite로 적재 (세션당 1회)."""
    db_path = tmp_path_factory.mktemp("db") / "navigation.db"
    counts = load_navigation_db(json_path=DEFAULT_JSON, db_path=db_path)
    assert counts["buildings"] == 1  # 적재 자체가 깨지면 여기서 바로 실패
    return db_path


@pytest.fixture
def db_connection(navigation_db_path):
    conn = sqlite3.connect(navigation_db_path)
    conn.row_factory = sqlite3.Row
    yield conn
    conn.close()


@pytest.fixture
def building_repository(db_connection) -> SqliteBuildingRepository:
    return SqliteBuildingRepository(db_connection)


@pytest.fixture
def api_client(navigation_db_path):
    app = create_app()

    def override_get_db():
        # TestClient 요청은 스레드풀에서 실행되므로 요청당 커넥션 생성
        conn = sqlite3.connect(navigation_db_path)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
        finally:
            conn.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as client:
        yield client
    app.dependency_overrides.clear()