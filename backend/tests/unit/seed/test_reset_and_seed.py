"""기본 개발 시드가 Studio 전 층 적재 경로를 호출하는지 검증한다."""

from scripts.seed.reset_and_seed import reset_and_seed_studio


def test_DB_초기화_후_Studio_전층을_적재한다(monkeypatch):
    calls = []

    monkeypatch.setattr("scripts.seed.reset_and_seed.reset_database", lambda: calls.append("reset"))
    monkeypatch.setattr("scripts.seed.reset_and_seed.seed_studio", lambda: calls.append("studio"))

    reset_and_seed_studio()

    assert calls == ["reset", "studio"]
