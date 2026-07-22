"""개발 중 HTTP JSON 요청/응답을 파일로 남기는 선택형 ASGI 미들웨어."""

from __future__ import annotations

import json
import re
import time
from datetime import datetime
from pathlib import Path
from typing import Any

from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.config import API_ROOT

_SENSITIVE_MARKERS = ("password", "secret", "token", "apikey", "api_key", "authorization")


def _is_sensitive(key: str) -> bool:
    return any(marker in key.lower() for marker in _SENSITIVE_MARKERS)


def _mask(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: "***" if _is_sensitive(str(key)) else _mask(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_mask(item) for item in value]
    return value


def _json_body(raw: bytes, content_type: str) -> Any | None:
    if not raw or "application/json" not in content_type.lower():
        return None
    try:
        return _mask(json.loads(raw.decode("utf-8")))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return {"_unparsed_json_bytes": len(raw)}


def _headers(scope_headers: list[tuple[bytes, bytes]]) -> dict[str, str]:
    result = {key.decode("latin-1"): value.decode("latin-1") for key, value in scope_headers}
    return {key: "***" if _is_sensitive(key) else value for key, value in result.items()}


class RequestCaptureMiddleware:
    """API JSON만 기록하고, 타일/글꼴 같은 바이너리 응답 본문은 기록하지 않는다."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app
        log_root = API_ROOT.parent if API_ROOT.name == "backend" else API_ROOT
        self.log_dir = log_root / "args"

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        request_chunks: list[bytes] = []
        response_chunks: list[bytes] = []
        response_status = 500
        response_content_type = ""

        async def receive_and_capture() -> Message:
            message = await receive()
            if message["type"] == "http.request":
                request_chunks.append(message.get("body", b""))
            return message

        async def send_and_capture(message: Message) -> None:
            nonlocal response_status, response_content_type
            if message["type"] == "http.response.start":
                response_status = message["status"]
                response_headers = _headers(message.get("headers", []))
                response_content_type = response_headers.get("content-type", "")
            elif message["type"] == "http.response.body" and "application/json" in response_content_type.lower():
                response_chunks.append(message.get("body", b""))
            await send(message)

        try:
            await self.app(scope, receive_and_capture, send_and_capture)
        finally:
            self._write(scope, b"".join(request_chunks), response_status, response_content_type, b"".join(response_chunks))

    def _write(
        self,
        scope: Scope,
        request_body: bytes,
        response_status: int,
        response_content_type: str,
        response_body: bytes,
    ) -> None:
        try:
            self.log_dir.mkdir(parents=True, exist_ok=True)
            request_headers = _headers(scope.get("headers", []))
            query_string = scope.get("query_string", b"").decode("utf-8", errors="replace")
            record = {
                "timestamp": datetime.now().astimezone().isoformat(timespec="milliseconds"),
                "request": {
                    "method": scope["method"],
                    "path": scope["path"],
                    "query_string": query_string,
                    "headers": request_headers,
                    "json": _json_body(request_body, request_headers.get("content-type", "")),
                },
                "response": {
                    "status": response_status,
                    "content_type": response_content_type,
                    "json": _json_body(response_body, response_content_type),
                },
            }
            safe_path = re.sub(r"[^a-zA-Z0-9_-]+", "-", scope["path"].strip("/")) or "root"
            filename = f"{time.time_ns()}-{scope['method'].lower()}-{safe_path}.json"
            (self.log_dir / filename).write_text(
                json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8"
            )
        except OSError:
            # 진단 로그 저장 실패가 실제 API 응답을 막으면 안 된다.
            pass
