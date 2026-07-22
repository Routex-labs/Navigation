"""match_ai_destination 하이브리드 오케스트레이션 단위 테스트.

임베딩 계층(query_semantic.semantic_search)은 monkeypatch로 대체해 torch·모델 다운로드
없이 1차/2차 분기·no_match·404·graceful degradation을 검증한다.
실제 임베딩 검색 품질은 test_query_semantic의 스모크(env 게이트)가 본다.
"""

from app.repositories import query_search, query_semantic
from app.repositories.query_search import _load_stores
from tests.conftest import BUILDING_ID


# 1차 경량이 맞으면 임베딩(2차)을 아예 호출하지 않는다 — 브랜드명은 문자열 일치가 우선.
def test_1차_경량이_맞으면_임베딩을_호출하지_않는다(db_session, monkeypatch):
    calls = {"n": 0}

    def spy(*_args, **_kwargs):
        calls["n"] += 1
        return None

    monkeypatch.setattr(query_semantic, "semantic_search", spy)

    result = query_search.match_ai_destination(db_session, BUILDING_ID, "가게A")

    assert result["status"] in ("ok", "ok_no_route")
    assert result["match"]["name"] == "가게A"
    assert calls["n"] == 0  # 1차에서 확정 → 2차 미호출


# 경량이 놓친 자연어는 2차 임베딩 결과로 확정된다.
def test_경량이_놓치면_임베딩_2차로_확정한다(db_session, monkeypatch):
    store, floor = _load_stores(db_session, BUILDING_ID)[0]
    monkeypatch.setattr(
        query_semantic, "semantic_search", lambda *a, **k: (0.71, store, floor)
    )

    result = query_search.match_ai_destination(db_session, BUILDING_ID, "밥 먹을 데")

    assert result["match"]["store_id"] == store.id
    assert result["status"] in ("ok", "ok_no_route")


# 1차·2차 모두 실패하면 예외가 아니라 no_match.
def test_둘다_실패하면_no_match(db_session, monkeypatch):
    monkeypatch.setattr(query_semantic, "semantic_search", lambda *a, **k: None)

    result = query_search.match_ai_destination(db_session, BUILDING_ID, "밥 먹을 데")

    assert result["status"] == "no_match"
    assert result["match"] is None


# 없는 건물은 None(→ 라우터가 404).
def test_없는_건물은_None을_반환한다(db_session):
    assert query_search.match_ai_destination(db_session, "no-such", "가게A") is None


# 모델 로드가 실패해도(semantic이 None) 경량 경로는 죽지 않는다 — graceful degradation.
def test_모델_없어도_semantic_search는_None으로_degrade(db_session, monkeypatch):
    monkeypatch.setattr(query_semantic, "_get_model", lambda: None)

    assert query_semantic.semantic_search(db_session, BUILDING_ID, "밥 먹을 데") is None
