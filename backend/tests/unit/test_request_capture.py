"""HTTP 진단 로그의 민감값 마스킹 단위 테스트."""

from app.core.request_capture import _headers, _json_body, _mask


def test_중첩_JSON의_민감값을_마스킹한다():
    value = {
        "text": "나이키",
        "token": "do-not-log",
        "nested": {"api_key": "do-not-log", "safe": 1},
    }

    assert _mask(value) == {
        "text": "나이키",
        "token": "***",
        "nested": {"api_key": "***", "safe": 1},
    }


def test_JSON_본문과_인증_헤더를_마스킹한다():
    body = b'{"query":"MLB","authorization":"secret"}'
    headers = [(b"content-type", b"application/json"), (b"authorization", b"Bearer secret")]

    assert _json_body(body, "application/json") == {"query": "MLB", "authorization": "***"}
    assert _headers(headers)["authorization"] == "***"
