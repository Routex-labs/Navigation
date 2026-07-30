# 애플리케이션 로깅 설정과 예외 로깅 핸들러.
#
# 진단 캡처(NAV_SQL_ECHO/NAV_HTTP_CAPTURE — 모든 SQL·요청 본문을 파일로 남김)와는
# 별개다. 그쪽은 개발 중에만 켜는 무거운 진단이고, 이쪽은 운영에서도 항상 켜두는 경량
# 로깅이다 — 요청 상태와 에러만 stdout에 한 줄씩 남긴다. Cloud Run 등은 stdout을 자동
# 수집하므로 별도 로그 파일이 필요 없다. 각 모듈은 logging.getLogger(__name__)으로
# "app.*" 로거를 얻어 찍고, 포맷·레벨은 configure_logging()이 한 곳에서 잡는다.

from __future__ import annotations

import logging
from logging.config import dictConfig

from fastapi import FastAPI, Request, Response
from fastapi.exception_handlers import (
    http_exception_handler,
    request_validation_exception_handler,
)
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.config import settings

logger = logging.getLogger("app")


# 로그 포맷·레벨을 프로세스 전체에 통일한다. uvicorn이 자기 로깅을 먼저 설정한 뒤
# app.main:app을 import하므로, create_app()에서 이 함수를 부르면 uvicorn 포맷까지
# 우리 포맷으로 덮어써 로그 모양이 하나로 통일된다.
def configure_logging() -> None:
    level = settings.log_level.upper()
    dictConfig(
        {
            "version": 1,
            # 이미 만들어진 로거(uvicorn.* 등)를 죽이지 않고 레벨·핸들러만 다시 건다.
            "disable_existing_loggers": False,
            "formatters": {
                "default": {
                    "format": "%(asctime)s %(levelname)-8s %(name)s %(message)s",
                    "datefmt": "%Y-%m-%dT%H:%M:%S%z",
                },
            },
            "handlers": {
                "stdout": {
                    "class": "logging.StreamHandler",
                    "stream": "ext://sys.stdout",
                    "formatter": "default",
                },
            },
            # 우리 코드(app.*)와 그 외 라이브러리는 root 핸들러로 stdout에 찍는다.
            "root": {"handlers": ["stdout"], "level": level},
            "loggers": {
                # uvicorn 로거는 자체 핸들러가 있어 root로 올리면 두 번 찍힌다.
                # propagate=False로 막고 같은 stdout 핸들러만 재사용한다.
                "uvicorn": {"handlers": ["stdout"], "level": level, "propagate": False},
                "uvicorn.access": {"handlers": ["stdout"], "level": level, "propagate": False},
                "uvicorn.error": {"handlers": ["stdout"], "level": level, "propagate": False},
                # 우리 코드는 root로 전파해 stdout 한 곳에서만 찍는다.
                "app": {"level": level},
            },
        }
    )


# HTTPException(4xx/5xx)을 로그로 남기고 응답 본문은 FastAPI 기본 핸들러에 위임한다.
# 상태 코드 자체는 uvicorn.access가 요청마다 남기지만, detail(왜 실패했는지)은 여기서만
# 남는다. 5xx는 서버 잘못이라 ERROR, 4xx는 대부분 클라이언트가 잘못 보낸 것이라 WARNING.
async def _log_http_exception(request: Request, exc: StarletteHTTPException) -> Response:
    level = logging.ERROR if exc.status_code >= 500 else logging.WARNING
    logger.log(
        level,
        "%s %s -> %d: %s",
        request.method,
        request.url.path,
        exc.status_code,
        exc.detail,
    )
    return await http_exception_handler(request, exc)


# 요청 검증 실패(422)를 어느 필드가 왜 막혔는지와 함께 남기고, 응답은 기본 핸들러에
# 위임한다. 클라이언트 버그 추적용이라 WARNING.
async def _log_validation_exception(request: Request, exc: RequestValidationError) -> Response:
    logger.warning(
        "%s %s -> 422 검증 실패: %s",
        request.method,
        request.url.path,
        exc.errors(),
    )
    return await request_validation_exception_handler(request, exc)


# 4xx/422 예외 로깅 핸들러를 앱에 건다. 미처리 예외(500)는 uvicorn이 "Exception in
# ASGI application" 트레이스백을 uvicorn.error로 이미 남기므로 따로 잡지 않는다 —
# configure_logging()이 그 로거도 stdout으로 통일한다.
def install_exception_logging(app: FastAPI) -> None:
    # add_exception_handler의 타입 힌트는 두 번째 인자를 Exception으로 넓게 잡지만,
    # 실제로는 첫 인자에 등록한 예외 타입만 전달된다. 핸들러를 구체 타입으로 두는 편이
    # 안전해서 여기서만 타입 검사를 눌러 둔다(Starlette 알려진 제약).
    app.add_exception_handler(StarletteHTTPException, _log_http_exception)  # type: ignore[arg-type]
    app.add_exception_handler(RequestValidationError, _log_validation_exception)  # type: ignore[arg-type]
