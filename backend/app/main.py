# FastAPI 애플리케이션 진입점(entry point)
# 앱 생성, CORS, Router 등록, /health를 이 모듈이 담당한다.
# DB 설정과 Session은 core/config.py, core/database.py에 있다.
# 실행 방법 (backend/ 디렉토리에서):
#   1) 최초 1회 DB 적재: python -m scripts.seed.reset_and_seed
#   2) 서버 실행:        uvicorn app.main:app --reload

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.dto.health import HealthResponse


# FastAPI 앱 팩토리. uvicorn과 테스트가 이 함수로 앱을 만든다.
def create_app() -> FastAPI:
    from app.routers import buildings, fonts, query

    app = FastAPI(title="Navigation API", version="0.3.0")

    # 개발 중에는 모든 출처(*) 허용. 운영 배포 시 Flutter 앱 도메인으로 교체 필요
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(buildings.router)  # 건물/지도/그래프/경로 API
    app.include_router(fonts.router)      # MapLibre 심볼 레이어용 글리프
    app.include_router(query.router)      # 자연어 질의 API(현재 stub)

    # 서버 생존 확인. Flutter가 서버 연결 전 호출.
    @app.get("/health", tags=["health"], response_model=HealthResponse)
    def health():
        return {"status": "ok"}

    return app


# uvicorn의 ``app.main:app`` 경로가 참조하는 모듈 전역 ASGI 애플리케이션이다.
app = create_app()
