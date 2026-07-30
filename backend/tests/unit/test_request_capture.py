"""HTTP 진단 로그의 민감값 마스킹과 수명주기 단위 테스트."""

from fastapi.testclient import TestClient

from app import main
from app.core import request_capture
from app.core.request_capture import _json_body, _mask


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


def test_JSON_본문의_민감값을_마스킹한다():
    body = b'{"query":"MLB","authorization":"secret"}'

    assert _json_body(body, "application/json") == {"query": "MLB", "authorization": "***"}


def test_SQL_캡처만_켜도_종료_정리_lifespan을_연결한다(monkeypatch):
    """HTTP 캡처 없이 SQL 로그만 남기는 개발 실행도 종료 때 파일을 비운다."""
    calls: list[str] = []
    monkeypatch.setattr(main.settings, "sql_echo", True)
    monkeypatch.setattr(main.settings, "http_capture", False)
    monkeypatch.setattr(main, "start_runtime_logs", lambda: calls.append("start"))
    monkeypatch.setattr(main, "clear_runtime_logs", lambda: calls.append("clear"))

    with TestClient(main.create_app()):
        assert calls == ["start"]

    assert calls == ["start", "clear"]


def test_종료_정리가_SQL과_HTTP_진단_파일을_비운다(tmp_path, monkeypatch):
    sql_dir = tmp_path / "sql"
    args_dir = tmp_path / "args"
    monkeypatch.setattr(request_capture, "_LOG_DIRS", (sql_dir, args_dir))
    for log_dir in (sql_dir, args_dir):
        log_dir.mkdir()
        (log_dir / "leftover.log").write_text("diagnostic", encoding="utf-8")

    request_capture.clear_runtime_logs()

    assert list(sql_dir.iterdir()) == []
    assert list(args_dir.iterdir()) == []
    request_capture.start_runtime_logs()  # 다른 테스트를 위해 캡처 상태를 원복한다.
