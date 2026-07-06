"""
설정, DI, 팩토리 담당

DB 경로를 환경변수 NAV_DB_PATH 로 주입
DI : get_db > get_building_repository > get_building_service
create_app() : FastAPI 인스턴스 생성, CORS, 라우터 등록, /health

- get_db는 yield dependency 이다. 핸들러 실행 전에 커넥션을 열고, 응답 전송 후 finally 에서 닫는다.
- 라우터 import는 create_app() 안에서 한다. 라우터가 이 모듈의 get_building_service를 import하므로, 모듈 레벨에서 서로 import하면 순환 import가 발생한다.
"""
import os
import sqlite3
from collections.abc import Iterator
from pathlib import Path

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.repository.BuildingRepository import BuildingRepository
from app.repository.sqliteBuildingRepository import SqliteBuildingRepository
from app.service.buildingService import BuildingService

API_ROOT = Path(__file__).resolve().parents[1]


def get_db_path() -> str:
    """DB 파일 경로. 운영/테스트에서 NAV_DB_PATH 환경변수로 교체 가능."""
    return os.getenv("NAV_DB_PATH", str(API_ROOT / "data" / "navigation.db"))


def get_db() -> Iterator[sqlite3.Connection]:
    """요청당 SQLite 커넥션. 응답 전송 후 자동으로 닫힌다."""
    conn = sqlite3.connect(get_db_path())
    conn.row_factory = sqlite3.Row  # 컬럼명으로 접근 가능한 row
    try:
        yield conn      # ← 여기서 핸들러가 실행된다
    finally:
        conn.close()    # ← 응답 전송 후 실행 (try-with-resources 대응)


def get_building_repository(
    conn: sqlite3.Connection = Depends(get_db),
) -> BuildingRepository:
    return SqliteBuildingRepository(conn)


def get_building_service(
    repository: BuildingRepository = Depends(get_building_repository),
) -> BuildingService:
    return BuildingService(repository)


def create_app() -> FastAPI:
    """FastAPI 앱 팩토리. main.py와 테스트가 이 함수로 앱을 만든다."""
    # 순환 import 방지를 위해 함수 안에서 import (모듈 docstring 참고)
    from app.router import buildingRouter, queryRouter

    app = FastAPI(title="Navigation API", version="0.2.0")

    # 개발 중에는 모든 출처(*) 허용. 운영 배포 시 Flutter 앱 도메인으로 교체 필요
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(buildingRouter.router)
    app.include_router(queryRouter.router)

    @app.get("/health", tags=["health"])
    def health():
        """서버 생존 확인. Flutter가 서버 연결 전 호출."""
        return {"status": "ok"}

    return app