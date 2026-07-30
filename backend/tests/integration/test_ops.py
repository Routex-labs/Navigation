"""운영 안정화 항목 통합 테스트.

07번(Dockerfile 단일화·seed 분리·보안 정리)에서 추가한 세 가지를 검증한다.
  1) CORS 화이트리스트 — 운영에서 와일드카드('*')를 쓰지 않는다.
  2) 요청 본문 크기 제한 — 한도를 넘는 본문은 413으로 끊는다.
  3) /health readiness/liveness 분리 — liveness는 항상 ok, readiness는 DB를 확인한다.

CORS·본문 제한은 settings 값에 따라 갈리므로, settings를 monkeypatch한 뒤 create_app()으로
앱을 새로 만들어 확인한다(main은 같은 settings 인스턴스를 참조한다).
"""

from collections.abc import Iterator

from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.core import config
from app.core.database import get_db
from app.main import create_app


def _client(session_factory, monkeypatch, **overrides) -> Iterator[TestClient]:
    for key, value in overrides.items():
        monkeypatch.setattr(config.settings, key, value)

    app = create_app()

    def override_get_db() -> Iterator[Session]:
        session = session_factory()
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as client:
        yield client
    app.dependency_overrides.clear()


# --- CORS: 운영에서 와일드카드 금지 ---------------------------------------


def test_개발_기본은_localhost_출처를_허용한다(session_factory, monkeypatch):
    for client in _client(session_factory, monkeypatch, environment="development", cors_origins=""):
        response = client.get("/health", headers={"Origin": "http://localhost:53123"})
        assert response.headers.get("access-control-allow-origin") == "http://localhost:53123"


def test_개발이라도_임의_외부_출처는_허용하지_않는다(session_factory, monkeypatch):
    for client in _client(session_factory, monkeypatch, environment="development", cors_origins=""):
        response = client.get("/health", headers={"Origin": "https://evil.example.com"})
        # localhost 정규식에 맞지 않으므로 CORS 허용 헤더가 붙지 않는다(와일드카드가 아님).
        assert "access-control-allow-origin" not in response.headers


def test_운영은_명시한_출처만_허용한다(session_factory, monkeypatch):
    for client in _client(
        session_factory,
        monkeypatch,
        environment="production",
        cors_origins="https://app.example.com",
    ):
        allowed = client.get("/health", headers={"Origin": "https://app.example.com"})
        assert allowed.headers.get("access-control-allow-origin") == "https://app.example.com"

        other = client.get("/health", headers={"Origin": "https://evil.example.com"})
        assert other.headers.get("access-control-allow-origin") != "*"
        assert other.headers.get("access-control-allow-origin") != "https://evil.example.com"


def test_운영에서_출처_미지정이면_교차출처를_전부_막는다(session_factory, monkeypatch):
    for client in _client(session_factory, monkeypatch, environment="production", cors_origins=""):
        response = client.get("/health", headers={"Origin": "https://app.example.com"})
        assert "access-control-allow-origin" not in response.headers


# --- 본문 크기 제한 -------------------------------------------------------


def test_한도를_넘는_본문은_413으로_끊는다(session_factory, monkeypatch):
    for client in _client(session_factory, monkeypatch, max_request_body_bytes=100):
        response = client.post("/query/destination", content=b"x" * 500)
        assert response.status_code == 413
        assert response.json()["detail"] == "Request body too large"


def test_한도_이내_요청은_통과한다(session_factory, monkeypatch):
    for client in _client(session_factory, monkeypatch, max_request_body_bytes=1_000_000):
        # 본문 제한 미들웨어가 정상 요청을 막지 않는지만 본다(라우팅 이후 응답은 무관).
        response = client.get("/health")
        assert response.status_code == 200


# --- /health liveness / readiness 분리 -----------------------------------


def test_liveness는_의존성_없이_항상_ok다(api_client):
    for path in ("/health", "/health/live"):
        response = api_client.get(path)
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}


def test_readiness는_DB가_되면_ready를_돌려준다(api_client):
    response = api_client.get("/health/ready")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ready"
    assert body["database"] == "ok"
    # 임베딩 워밍 상태는 06번 연계 전까지 "unknown"이며 readiness를 막지 않는다.
    assert body["embedding_model"] in {"ready", "unknown"}
