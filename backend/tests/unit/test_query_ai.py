"""match_ai_destination 하이브리드 오케스트레이션 단위 테스트.

임베딩 계층(query_semantic.semantic_search)은 monkeypatch로 대체해 torch·모델 다운로드
없이 1차/2차 분기·no_match·404·graceful degradation을 검증한다.
실제 임베딩 검색 품질은 test_query_semantic의 스모크(env 게이트)가 본다.
"""

import pytest

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

    result = query_search.match_ai_destination(
        db_session, BUILDING_ID, "가게A 어디야?"
    )

    assert result["status"] in ("ok", "ok_no_route")
    assert result["match"]["name"] == "가게A"
    assert calls["n"] == 0  # 1차에서 확정 → 2차 미호출


# 2차는 건물 전체를 본다. 1차가 현재 층에서 이미 실패한 뒤라 층을 또 좁히면
# 현재 층에 대상이 없는 질의(1F에서 "밥집")가 항상 no_match로 끝난다.
def test_서로_다른_부분일치가_여럿이면_현재층없이_원문만_2차에_전달한다(
    db_session, monkeypatch
):
    store, floor = next(
        (store, floor)
        for store, floor in _load_stores(
            db_session, BUILDING_ID, current_floor_id="1F"
        )
        if store.name == "가게B"
    )
    captured = {}

    def semantic_spy(session, building_id, text, **kwargs):
        captured.update(
            {
                "session": session,
                "building_id": building_id,
                "text": text,
                "kwargs": kwargs,
            }
        )
        return 0.71, store, floor

    monkeypatch.setattr(query_semantic, "semantic_search", semantic_spy)

    result = query_search.match_ai_destination(
        db_session,
        BUILDING_ID,
        "가게",
        current_floor_id="1F",
    )

    assert result["match"]["store_id"] == store.id
    assert captured == {
        "session": db_session,
        "building_id": BUILDING_ID,
        "text": "가게",
        "kwargs": {},  # 층 스코프를 넘기지 않는다 — 2차는 건물 전체
    }


def test_부분일치여도_최상위_매장명이_하나면_1차에서_확정한다(
    db_session, monkeypatch
):
    calls = {"n": 0}

    def spy(*_args, **_kwargs):
        calls["n"] += 1
        return None

    monkeypatch.setattr(query_semantic, "semantic_search", spy)

    result = query_search.match_ai_destination(
        db_session,
        BUILDING_ID,
        "게A",
        current_floor_id="1F",
    )

    assert result["match"]["name"] == "가게A"
    assert calls["n"] == 0


def test_모호한_부분일치에서_2차도_실패하면_no_match다(db_session, monkeypatch):
    monkeypatch.setattr(query_semantic, "semantic_search", lambda *a, **k: None)

    result = query_search.match_ai_destination(db_session, BUILDING_ID, "가게")

    assert result["status"] == "no_match"
    assert result["match"] is None


# 경량이 놓친 자연어는 2차 임베딩 결과로 확정된다.
def test_경량이_놓치면_임베딩_2차로_확정한다(db_session, monkeypatch):
    store, floor = _load_stores(db_session, BUILDING_ID)[0]
    monkeypatch.setattr(
        query_semantic, "semantic_search", lambda *a, **k: (0.71, store, floor)
    )

    result = query_search.match_ai_destination(db_session, BUILDING_ID, "밥 먹을 데")

    assert result["match"]["store_id"] == store.id
    assert result["status"] in ("ok", "ok_no_route")


# 회귀: 현재 층에 대상이 없어도 2차가 찾은 타 층 매장을 그대로 돌려준다.
# 층 필터가 2차에 걸려 있던 동안은 이 경우가 전부 no_match였다
# (1F에서 "밥집" → 상위 후보가 전부 B1이라 전멸).
def test_현재층에_없는_대상도_2차가_찾은_타층_매장을_반환한다(db_session, monkeypatch):
    other_floor_store = next(
        (store, floor)
        for store, floor in _load_stores(db_session, BUILDING_ID)
        if floor.name != "1F"
    )
    store, floor = other_floor_store
    monkeypatch.setattr(
        query_semantic, "semantic_search", lambda *a, **k: (0.61, store, floor)
    )

    result = query_search.match_ai_destination(
        db_session,
        BUILDING_ID,
        "밥집",
        current_floor_id="1F",
    )

    assert result["status"] in ("ok", "ok_no_route")
    assert result["match"]["store_id"] == store.id
    assert result["match"]["floor_name"] == floor.name
    assert result["match"]["floor_name"] != "1F"


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


# --- 실패 사유 구분(conversational-discovery.md 8-4) ---
# 모델·인덱스 미가용은 degraded("지금 의미 검색을 못 쓴다"), 임계값 미달은
# no_match("다른 말로 다시")다. 화면 문구가 달라야 해서 사유를 구분한다.


def test_모델이_없으면_MODEL_UNAVAILABLE_사유로_degraded다(db_session, monkeypatch):
    monkeypatch.setattr(query_semantic, "_get_model", lambda: None)

    result = query_semantic.search(db_session, BUILDING_ID, "밥 먹을 데")

    assert result.reason is query_semantic.SemanticReason.MODEL_UNAVAILABLE
    assert result.hit is None
    assert result.is_degraded is True


def test_인덱스를_못_만들면_INDEX_UNAVAILABLE_사유로_degraded다(db_session, monkeypatch):
    # 모델은 있는데(더미) 인덱스 빌드가 실패하는 상황 — 건물에 매장 0건 등.
    monkeypatch.setattr(query_semantic, "_get_model", lambda: object())
    monkeypatch.setattr(query_semantic, "_get_index", lambda *a, **k: None)

    result = query_semantic.search(db_session, BUILDING_ID, "밥 먹을 데")

    assert result.reason is query_semantic.SemanticReason.INDEX_UNAVAILABLE
    assert result.hit is None
    assert result.is_degraded is True


def test_임계값_미달이면_BELOW_THRESHOLD_사유이고_degraded가_아니다(
    db_session, monkeypatch
):
    _stub_index(db_session, monkeypatch, top_score=query_semantic.SIMILARITY_THRESHOLD - 0.01)

    result = query_semantic.search(db_session, BUILDING_ID, "밥 먹을 데")

    assert result.reason is query_semantic.SemanticReason.BELOW_THRESHOLD
    assert result.hit is None
    assert result.is_degraded is False


def test_임계값_이상이면_OK_사유와_함께_1건을_돌려준다(db_session, monkeypatch):
    store, floor = _stub_index(
        db_session, monkeypatch, top_score=query_semantic.SIMILARITY_THRESHOLD + 0.2
    )

    result = query_semantic.search(db_session, BUILDING_ID, "밥 먹을 데")

    assert result.reason is query_semantic.SemanticReason.OK
    assert result.is_degraded is False
    score, hit_store, hit_floor = result.hit
    assert (hit_store.id, hit_floor.id) == (store.id, floor.id)
    # float32 인덱스 점수를 float로 넓히므로 정확 비교 대신 근사 비교.
    assert score == pytest.approx(query_semantic.SIMILARITY_THRESHOLD + 0.2, rel=1e-6)


# 기존 호출부(match_ai_destination)는 그대로 튜플|None을 본다 — 하위 호환.
def test_semantic_search는_사유와_무관하게_기존_모양을_유지한다(db_session, monkeypatch):
    monkeypatch.setattr(query_semantic, "_get_model", lambda: None)
    assert query_semantic.semantic_search(db_session, BUILDING_ID, "밥집") is None

    _stub_index(db_session, monkeypatch, top_score=query_semantic.SIMILARITY_THRESHOLD - 0.01)
    assert query_semantic.semantic_search(db_session, BUILDING_ID, "밥집") is None

    store, floor = _stub_index(db_session, monkeypatch, top_score=0.71)
    hit = query_semantic.semantic_search(db_session, BUILDING_ID, "밥집")
    assert hit is not None
    score, hit_store, hit_floor = hit
    assert (hit_store.id, hit_floor.id) == (store.id, floor.id)
    assert score == pytest.approx(0.71, rel=1e-6)


def _stub_index(db_session, monkeypatch, *, top_score):
    """실제 임베딩·faiss 없이 '최상위 1건이 top_score'인 인덱스를 흉내 낸다.

    torch·모델 다운로드를 피하려고 _get_model/_get_index/_encode와 index.search만
    가짜로 바꾼다. 반환한 (store, floor)가 최상위 후보다.
    """
    import numpy as np

    store, floor = _load_stores(db_session, BUILDING_ID)[0]

    class _FakeIndex:
        ntotal = 1

        def search(self, _vec, k):
            return np.array([[top_score]], dtype="float32"), np.array([[0]])

    monkeypatch.setattr(query_semantic, "_get_model", lambda: object())
    monkeypatch.setattr(
        query_semantic, "_get_index", lambda *a, **k: (_FakeIndex(), [store.id])
    )
    monkeypatch.setattr(
        query_semantic, "_encode", lambda *a, **k: np.zeros((1, 3), dtype="float32")
    )
    return store, floor
