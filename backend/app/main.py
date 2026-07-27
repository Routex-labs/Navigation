# FastAPI 애플리케이션 진입점(entry point)
# 앱 생성, CORS, Router 등록, /health를 이 모듈이 담당한다.
# DB 설정과 Session은 core/config.py, core/database.py에 있다.
# 실행 방법 (backend/ 디렉토리에서):
#   1) 최초 1회 DB 적재: python -m scripts.seed.reset_and_seed
#   2) 서버 실행:        uvicorn app.main:app --reload

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.core.request_capture import RequestCaptureMiddleware, clear_runtime_logs, start_runtime_logs
from app.dto.health import HealthResponse


# 개발 진단 로그의 수명주기. yield 앞이 startup, 뒤가 shutdown이다.
# 새 서버 실행은 새 진단 세션이므로 이전 실행의 로그를 남기지 않고,
# 정상 종료 때 파일을 비운다.
@asynccontextmanager
async def _development_log_lifespan(app: FastAPI) -> AsyncIterator[None]:
    start_runtime_logs()
    try:
        yield
    finally:
        clear_runtime_logs()


# FastAPI 앱 팩토리. uvicorn과 테스트가 이 함수로 앱을 만든다.
def create_app() -> FastAPI:
    from app.routers import buildings, fonts, query

    # lifespan은 생성 시점에 넘겨야 해서, 진단 캡처 여부를 여기서 먼저 정한다.
    app = FastAPI(
        title="Navigation API",
        version="0.3.0",
        lifespan=_development_log_lifespan if settings.http_capture else None,
    )

    # 개발 중에는 모든 출처(*) 허용. 운영 배포 시 Flutter 앱 도메인으로 교체 필요
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )
    # SQL·HTTP 진단 캡처는 개발 실행에서만 켠다(로그 파일 정리는 위 lifespan이 담당).
    if settings.http_capture:
        app.add_middleware(RequestCaptureMiddleware)

    # 라우터 등록.
    app.include_router(buildings.router)  # 건물/지도/그래프/경로 API
    app.include_router(fonts.router)      # MapLibre 심볼 레이어용 글리프
    app.include_router(query.router)      # 자연어 질의 API(경량 매칭 + AI 임베딩 검색)

    # 서버 생존 확인. Flutter가 서버 연결 전 호출.
    @app.get("/health", tags=["health"], response_model=HealthResponse)
    def health():
        return {"status": "ok"}

    # AI 질의용 임베딩 모델을 백그라운드로 미리 올린다(NAV_WARM_EMBEDDING=1일 때만).
    # import까지 이 안에 두는 이유: 끄고 실행하는 프로세스(테스트 등)는 torch를
    # 건드리지 않는다는 query_semantic의 지연 로드 원칙을 그대로 유지하기 위해서다.
    if settings.warm_embedding:
        from app.repositories import query_semantic

        query_semantic.warm_model_in_background()

    # 실내 오버레이 MVT 타일을 기동 시점에 미리 인코딩해 캐시에 채운다. 그러지
    # 않으면 사용자가 처음 층을 훑을 때 CPU 바운드 인코딩이 직렬 처리되며 몇 초씩
    # 걸리고, 그 사이 MapLibre 네이티브의 소켓 취소·재사용 경쟁으로 "Socket
    # closed"가 튀어 일부 층 오버레이가 빈 채로 남던 증상을 사전에 없앤다.
    from app.core.database import SessionLocal
    from app.repositories import tile_queries

    tile_queries.warm_tile_cache_in_background(SessionLocal)

    return app


# uvicorn의 ``app.main:app`` 경로가 참조하는 모듈 전역 ASGI 애플리케이션이다.
app = create_app()
