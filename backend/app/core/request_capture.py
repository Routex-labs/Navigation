"""개발 중 HTTP JSON 요청/응답을 파일로 남기는 선택형 ASGI 미들웨어."""

from __future__ import annotations

import json
import re
import shutil
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import Any

from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.config import API_ROOT

_SENSITIVE_MARKERS = ("password", "secret", "token", "apikey", "api_key", "authorization")
_LOG_DIRS = (API_ROOT / "app" / "sql", API_ROOT / "app" / "args")

# 종료 절차가 시작되면 False로 내려 잔여 요청이 파일을 다시 쓰지 못하게 한다.
_capture_enabled = True


def _is_sensitive(key: str) -> bool:
    return any(marker in key.lower() for marker in _SENSITIVE_MARKERS)


# 비밀값으로 보이는 키를 ***로 가린다. 중첩 dict·list 안쪽까지 재귀로 훑는다.
def _mask(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: "***" if _is_sensitive(str(key)) else _mask(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_mask(item) for item in value]
    return value


# JSON 본문만 기록한다. 파싱이 깨져도 예외를 올리지 않고 길이만 남긴다.
def _json_body(raw: bytes, content_type: str) -> Any | None:
    if not raw or "application/json" not in content_type.lower():
        return None
    try:
        return _mask(json.loads(raw.decode("utf-8")))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return {"_unparsed_json_bytes": len(raw)}


class RequestCaptureMiddleware:
    """실제 요청 인자와 상태 코드만 기록하는 선택형 ASGI 미들웨어."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app
        self.log_dir = API_ROOT / "app" / "args"
        self._health_logged = False
        self._health_lock = threading.Lock()

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        # websocket·lifespan 등 HTTP가 아닌 scope는 그대로 흘려보낸다.
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        # Docker healthcheck는 주기적으로 호출되므로 시작 확인용 첫 한 건만 남긴다.
        capture_request = True
        if scope["path"] == "/health":
            with self._health_lock:
                if self._health_logged:
                    capture_request = False
                else:
                    self._health_logged = True
        if not capture_request:
            await self.app(scope, receive, send)
            return

        # 요청 본문과 응답 상태는 아래 래퍼가 흘려보내면서 곁다리로 주워 담는다.
        request_chunks: list[bytes] = []
        response_status = 500

        # ASGI 콜러블을 감싸 오가는 값을 곁다리로 주워 담는다. 흐름 자체는 바꾸지 않는다.
        async def receive_and_capture() -> Message:
            message = await receive()
            if message["type"] == "http.request":
                request_chunks.append(message.get("body", b""))
            return message

        async def send_and_capture(message: Message) -> None:
            nonlocal response_status
            if message["type"] == "http.response.start":
                response_status = message["status"]
            await send(message)

        # 핸들러가 예외로 끝나도 기록은 남긴다(그래서 finally).
        try:
            await self.app(scope, receive_and_capture, send_and_capture)
        finally:
            self._write(scope, b"".join(request_chunks), response_status)

    def _write(
        self,
        scope: Scope,
        request_body: bytes,
        response_status: int,
    ) -> None:
        if not _capture_enabled:
            return

        try:
            self.log_dir.mkdir(parents=True, exist_ok=True)

            query_string = scope.get("query_string", b"").decode("utf-8", errors="replace")
            # 실제로 들어온 인자와 나간 상태 코드만 남긴다(응답 본문은 크고 불필요).
            record = {
                "timestamp": datetime.now().astimezone().isoformat(timespec="milliseconds"),
                "request": {
                    "method": scope["method"],
                    "path": scope["path"],
                    "query_string": query_string,
                    "json": _json_body(
                        request_body,
                        next(
                            (
                                value.decode("latin-1")
                                for key, value in scope.get("headers", [])
                                if key.lower() == b"content-type"
                            ),
                            "",
                        ),
                    ),
                },
                "response_status": response_status,
            }

            # 경로를 파일명으로 쓸 수 있게 정리하고 나노초를 붙여 충돌을 피한다.
            safe_path = re.sub(r"[^a-zA-Z0-9_-]+", "-", scope["path"].strip("/")) or "root"
            filename = f"{time.time_ns()}-{scope['method'].lower()}-{safe_path}.json"
            (self.log_dir / filename).write_text(
                json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8"
            )
        except OSError:
            # 진단 로그 저장 실패가 실제 API 응답을 막으면 안 된다.
            pass


def start_runtime_logs() -> None:
    """새 서버 실행의 진단 세션을 시작하고 이전 파일을 비운다."""
    global _capture_enabled

    _capture_enabled = True
    _delete_runtime_log_files()


def clear_runtime_logs() -> None:
    """서버 시작·정상 종료 시 진단 파일을 전부 지운다.

    Docker bind mount 자체는 삭제할 수 없으므로 폴더는 남기고 내부 파일만 비운다.
    """
    global _capture_enabled
    # 종료 직전 이미 들어온 healthcheck가 삭제 뒤 파일을 다시 쓰지 못하게 한다.
    _capture_enabled = False
    _delete_runtime_log_files()


# Docker bind mount 자체는 지울 수 없으므로 폴더는 남기고 내부 항목만 비운다.
def _delete_runtime_log_files() -> None:
    for log_dir in _LOG_DIRS:
        if not log_dir.exists():
            continue

        for entry in log_dir.iterdir():
            try:
                if entry.is_dir():
                    shutil.rmtree(entry)
                else:
                    entry.unlink()
            except OSError as error:
                print(f"진단 로그를 삭제하지 못했습니다: {error}")
