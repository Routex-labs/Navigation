# FastAPI 애플리케이션 진입점(entry point)
# 앱 생성, 미들웨어(CORS·TrustedHost·본문 크기 제한), Router 등록을 이 모듈이 담당한다.
# /health(liveness)·/health/ready(readiness)는 routers/health.py로 분리했다.
# DB 설정과 Session은 core/config.py, core/database.py에 있다.
# 실행 방법 (backend/ 디렉토리에서):
#   1) 최초 1회 DB 적재: python -m scripts.seed.reset_and_seed
#   2) 서버 실행:        uvicorn app.main:app --reload

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.trustedhost import TrustedHostMiddleware

from app.core.config import settings
from app.core.logging import configure_logging, install_exception_logging
from app.core.request_limits import BodySizeLimitMiddleware

logger = logging.getLogger("app")

# 개발 기본값: localhost의 임의 포트만 허용한다(Flutter 웹은 실행마다 포트가 바뀐다).
# 와일드카드('*')가 아니라 정규식으로 localhost/127.0.0.1에 한정한다.
_DEV_CORS_ORIGIN_REGEX = r"http://(localhost|127\.0\.0\.1)(:\d+)?"


# CORS 미들웨어를 환경 기준으로 건다. 운영에서는 절대 와일드카드를 쓰지 않는다.
#   - NAV_CORS_ORIGINS가 있으면(개발·운영 무관) 그 화이트리스트만 허용한다.
#   - 없고 개발 환경이면 localhost 임의 포트만 정규식으로 허용한다(편의).
#   - 없고 운영 환경이면 교차 출처를 전부 막는다(동일 출처 요청은 그대로 동작).
def _configure_cors(app: FastAPI) -> None:
    origins = settings.cors_origins_list
    if origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=origins,
            allow_methods=["*"],
            allow_headers=["*"],
        )
        return
    if not settings.is_production:
        app.add_middleware(
            CORSMiddleware,
            allow_origin_regex=_DEV_CORS_ORIGIN_REGEX,
            allow_methods=["*"],
            allow_headers=["*"],
        )
        return
    # 운영인데 origin이 하나도 지정되지 않았다. 교차 출처를 막되(미들웨어 미등록),
    # 잘못된 배포를 알아채도록 경고를 남긴다.
    logger.warning(
        "운영(environment=production)인데 NAV_CORS_ORIGINS가 비어 있다 — "
        "교차 출처 요청을 전부 차단한다. Flutter 앱 도메인을 지정하라."
    )


# FastAPI 앱 팩토리. uvicorn과 테스트가 이 함수로 앱을 만든다.
def create_app() -> FastAPI:
    # 로그 포맷·레벨을 먼저 통일한다(요청 상태·에러는 stdout으로 남는다).
    configure_logging()

    from app.routers import buildings, fonts, health, query

    app = FastAPI(title="Navigation API", version="0.3.0")

    # 요청 본문 크기 제한. 거대한 본문 하나로 메모리를 밀어 넣는 요청을 413으로 끊는다.
    app.add_middleware(BodySizeLimitMiddleware, max_body_bytes=settings.max_request_body_bytes)

    # CORS는 환경 기준 화이트리스트로 건다(운영 와일드카드 금지).
    _configure_cors(app)

    # TrustedHost는 화이트리스트가 지정됐을 때만 건다. 비어 있으면 필터하지 않아
    # Cloud Run의 동적 호스트명·테스트 클라이언트를 깨지 않는다(운영에서 env로 잠근다).
    if settings.allowed_hosts_list:
        app.add_middleware(TrustedHostMiddleware, allowed_hosts=settings.allowed_hosts_list)

    # 4xx/422 예외를 이유와 함께 로그로 남긴다(500 트레이스백은 uvicorn.error가 담당).
    install_exception_logging(app)

    # 라우터 등록.
    app.include_router(health.router)  # liveness /health · readiness /health/ready
    app.include_router(buildings.router)  # 건물/지도/그래프/경로 API
    app.include_router(fonts.router)  # MapLibre 심볼 레이어용 글리프
    app.include_router(query.router)  # 자연어 질의 API(경량 매칭 + AI 임베딩 검색)

    from app.core.database import SessionLocal

    # AI 질의용 임베딩 모델과 건물별 검색 인덱스를 백그라운드로 미리 올린다
    # (NAV_WARM_EMBEDDING=1일 때만). 모델만 올리면 첫 질의가 인덱스 빌드(전 매장
    # 인코딩)를 그대로 기다리므로 둘을 함께 굽는다(query_semantic._warm).
    # import까지 이 안에 두는 이유: 끄고 실행하는 프로세스(테스트 등)는 torch를
    # 건드리지 않는다는 query_semantic의 지연 로드 원칙을 그대로 유지하기 위해서다.
    if settings.warm_embedding:
        from app.repositories import query_semantic

        query_semantic.warm_in_background(SessionLocal)

    # 형태소 분석기(Kiwi)와 매장 사전을 미리 만든다. 임베딩과 달리 이건 **1차 경량
    # 경로**라 2차를 안 타는 질의("MLB")도 첫 번째면 약 2.2초를 문다(실측: 인스턴스
    # 816ms + 첫 tokenize 1397ms). NAV_WARM_EMBEDDING과 묶지 않고 항상 켠다.
    from app.repositories import query_morph

    query_morph.warm_in_background(SessionLocal)

    # 실내 오버레이 MVT 타일을 기동 시점에 미리 인코딩해 캐시에 채운다. 그러지
    # 않으면 사용자가 처음 층을 훑을 때 CPU 바운드 인코딩이 직렬 처리되며 몇 초씩
    # 걸리고, 그 사이 MapLibre 네이티브의 소켓 취소·재사용 경쟁으로 "Socket
    # closed"가 튀어 일부 층 오버레이가 빈 채로 남던 증상을 사전에 없앤다.
    from app.repositories import tile_queries

    tile_queries.warm_tile_cache_in_background(SessionLocal)

    return app


# uvicorn의 ``app.main:app`` 경로가 참조하는 모듈 전역 ASGI 애플리케이션이다.
app = create_app()
