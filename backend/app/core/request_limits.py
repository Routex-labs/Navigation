# 요청 본문 크기 제한 미들웨어(순수 ASGI).
#
# 우리 API는 짧은 JSON 질의만 받는데, 제한이 없으면 거대한 본문 하나로 메모리를
# 통째로 밀어 넣는 요청(의도적 남용·버그 클라이언트)을 그대로 받아 읽는다. 여기서
# 두 겹으로 막는다.
#   1) Content-Length가 한도를 넘으면 본문을 읽기도 전에 413으로 끊는다(정상 클라이언트
#      경로 — requests/httpx/Flutter는 항상 Content-Length를 보낸다).
#   2) Content-Length가 없는(chunked) 스트림은 바이트를 세다가 한도를 넘는 순간 중단
#      신호를 올려, 응답이 아직 시작되지 않았으면 413으로 끊는다.
# BaseHTTPMiddleware 대신 순수 ASGI로 짜는 이유: 본문을 버퍼링하지 않고 receive를
# 감싸 흘려보내면서 크기만 세기 위해서다.

from __future__ import annotations

from starlette.types import ASGIApp, Message, Receive, Scope, Send


# 스트리밍 중 본문 초과를 알리는 내부 신호. 미들웨어 밖으로 새지 않는다.
class _BodyTooLarge(Exception):
    pass


class BodySizeLimitMiddleware:
    def __init__(self, app: ASGIApp, max_body_bytes: int) -> None:
        self.app = app
        self.max_body_bytes = max_body_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        # HTTP가 아니거나 제한이 꺼져 있으면 그대로 통과시킨다.
        if scope["type"] != "http" or self.max_body_bytes <= 0:
            await self.app(scope, receive, send)
            return

        # 1) Content-Length 빠른 경로 — 본문을 읽기 전에 거절한다.
        declared = self._content_length(scope)
        if declared is not None and declared > self.max_body_bytes:
            await self._send_413(send)
            return

        # 2) 스트리밍 경로 — receive를 감싸 누적 바이트를 센다.
        received = 0
        response_started = False

        async def guarded_send(message: Message) -> None:
            nonlocal response_started
            if message["type"] == "http.response.start":
                response_started = True
            await send(message)

        async def guarded_receive() -> Message:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > self.max_body_bytes and not response_started:
                    raise _BodyTooLarge
            return message

        try:
            await self.app(scope, guarded_receive, guarded_send)
        except _BodyTooLarge:
            # 응답이 아직 시작되지 않았을 때만 413을 보낼 수 있다.
            if not response_started:
                await self._send_413(send)

    # Content-Length 헤더를 정수로 읽는다. 없거나 형식이 틀리면 None.
    @staticmethod
    def _content_length(scope: Scope) -> int | None:
        for key, value in scope.get("headers") or []:
            if key == b"content-length":
                try:
                    return int(value)
                except ValueError:
                    return None
        return None

    # 최소한의 413 응답을 직접 내보낸다(앱을 거치지 않는다).
    async def _send_413(self, send: Send) -> None:
        body = b'{"detail":"Request body too large"}'
        await send(
            {
                "type": "http.response.start",
                "status": 413,
                "headers": [
                    (b"content-type", b"application/json"),
                    (b"content-length", str(len(body)).encode("ascii")),
                ],
            }
        )
        await send({"type": "http.response.body", "body": body})
