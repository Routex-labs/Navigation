"""match_ai_destination 하이브리드 오케스트레이션 단위 테스트.

임베딩 계층(query_semantic.semantic_search)은 monkeypatch로 대체해 torch·모델 다운로드
없이 1차/2차 분기·no_match·404·graceful degradation을 검증한다.
실제 임베딩 검색 품질은 test_query_semantic의 스모크(env 게이트)가 본다.
"""

import pytest

from app.models import Store
from app.repositories import query_search, query_semantic
from app.repositories.query_search import _load_stores
from tests.conftest import BUILDING_ID, FLOOR_ID

MAX_MATCHES = query_search.MAX_DISCOVERY_MATCHES
MAX_SHOW_ALL = query_search.MAX_RESULT_MATCHES
CLARIFY_PREVIEW = query_search.CLARIFY_PREVIEW_MATCHES


# 1차 경량이 맞으면 임베딩(2차)을 아예 호출하지 않는다 — 브랜드명은 문자열 일치가 우선.
def test_1차_경량이_맞으면_임베딩을_호출하지_않는다(db_session, monkeypatch):
    calls = {"n": 0}

    def spy(*_args, **_kwargs):
        calls["n"] += 1
        return None

    monkeypatch.setattr(query_semantic, "semantic_search", spy)

    result = query_search.match_ai_destination(db_session, BUILDING_ID, "가게A 어디야?")

    assert result["status"] in ("ok", "ok_no_route")
    assert result["match"]["name"] == "가게A"
    assert calls["n"] == 0  # 1차에서 확정 → 2차 미호출


# 2차는 건물 전체를 본다. 1차가 현재 층에서 이미 실패한 뒤라 층을 또 좁히면
# 현재 층에 대상이 없는 질의(1F에서 "밥집")가 항상 no_match로 끝난다.
def test_서로_다른_부분일치가_여럿이면_현재층없이_원문만_2차에_전달한다(db_session, monkeypatch):
    store, floor = next(
        (store, floor)
        for store, floor in _load_stores(db_session, BUILDING_ID, current_floor_id="1F")
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


def test_부분일치여도_최상위_매장명이_하나면_1차에서_확정한다(db_session, monkeypatch):
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


# --- tier 1(카테고리·소분류 정확 일치) 확정 조건 (Wave 5-a) ---
# "명품"(43건)·"레스토랑"(65건)처럼 소분류와 글자가 같은 질의가 첫 매장으로 임의
# 확정되지 않도록, 서로 다른 매장 이름이 둘 이상이면 확정하지 않고 2차로 넘긴다.
# docs/backend/native/conversational-discovery.md 7-2절, search-qa-fix-wave.md Wave 5-a.


def test_tier1_서로_다른_이름이_2개_이상이면_1차에서_확정하지_않는다(db_session, monkeypatch):
    # 가게A(패션/여성패션)와 같은 subcategory("여성패션")를 갖되 이름이 다른 매장을
    # 추가해, tier 1 후보의 서로 다른 이름이 2개("가게A", "가게C")가 되게 만든다.
    extra = Store(
        id="shop-c-1f-extra",
        floor_id=FLOOR_ID,
        name="가게C",
        category="패션",
        subcategory="여성패션",
        centroid_x_m=50.0,
        centroid_y_m=40.0,
    )
    db_session.add(extra)
    db_session.flush()

    store, floor = _load_stores(db_session, BUILDING_ID)[0]
    calls = {"n": 0}

    def spy(*_args, **_kwargs):
        calls["n"] += 1
        return 0.71, store, floor

    monkeypatch.setattr(query_semantic, "semantic_search", spy)

    result = query_search.match_ai_destination(db_session, BUILDING_ID, "여성패션")

    assert calls["n"] == 1  # 1차가 확정하지 않아 2차로 넘어감
    assert result["match"]["store_id"] == store.id


def test_tier1_후보가_같은_이름_1개뿐이면_층만_달라도_확정한다(db_session, monkeypatch):
    calls = {"n": 0}

    def spy(*_args, **_kwargs):
        calls["n"] += 1
        return None

    monkeypatch.setattr(query_semantic, "semantic_search", spy)

    result = query_search.match_ai_destination(db_session, BUILDING_ID, "여성패션")

    # "여성패션" subcategory는 1F·2F의 "가게A"에만 걸린다 — 층은 다르지만 이름은
    # 하나이므로 1차에서 확정하고 2차(임베딩)를 부르지 않는다.
    assert result["match"]["name"] == "가게A"
    assert calls["n"] == 0


def test_tier0은_여러_층_중복이어도_확정한다(db_session, monkeypatch):
    calls = {"n": 0}

    def spy(*_args, **_kwargs):
        calls["n"] += 1
        return None

    monkeypatch.setattr(query_semantic, "semantic_search", spy)

    # "가게A"는 1F·2F에 동일한 이름으로 존재한다(정확 이름 일치 = tier 0).
    result = query_search.match_ai_destination(db_session, BUILDING_ID, "가게A")

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
    monkeypatch.setattr(query_semantic, "semantic_search", lambda *a, **k: (0.71, store, floor))

    result = query_search.match_ai_destination(db_session, BUILDING_ID, "밥 먹을 데")

    assert result["match"]["store_id"] == store.id
    assert result["status"] in ("ok", "ok_no_route")


# 회귀: 현재 층에 대상이 없어도 2차가 찾은 타 층 매장을 그대로 돌려준다.
# 층 필터가 2차에 걸려 있던 동안은 이 경우가 전부 no_match였다
# (1F에서 "밥집" → 상위 후보가 전부 B1이라 전멸).
def test_현재층에_없는_대상도_2차가_찾은_타층_매장을_반환한다(db_session, monkeypatch):
    other_floor_store = next(
        (store, floor) for store, floor in _load_stores(db_session, BUILDING_ID) if floor.name != "1F"
    )
    store, floor = other_floor_store
    monkeypatch.setattr(query_semantic, "semantic_search", lambda *a, **k: (0.61, store, floor))

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


def test_임계값_미달이면_BELOW_THRESHOLD_사유이고_degraded가_아니다(db_session, monkeypatch):
    _stub_index(db_session, monkeypatch, top_score=query_semantic.SIMILARITY_THRESHOLD - 0.01)

    result = query_semantic.search(db_session, BUILDING_ID, "밥 먹을 데")

    assert result.reason is query_semantic.SemanticReason.BELOW_THRESHOLD
    assert result.hit is None
    assert result.is_degraded is False


def test_임계값_이상이면_OK_사유와_함께_1건을_돌려준다(db_session, monkeypatch):
    store, floor = _stub_index(db_session, monkeypatch, top_score=query_semantic.SIMILARITY_THRESHOLD + 0.2)

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


# ==========================================================================
# 탐색(discover) 판정 로직 — conversational-discovery.md 7·8절, Wave 6
# 임베딩 2차는 monkeypatch로 대체한다(torch·모델 다운로드 없이 모드 분기를 본다).
# ==========================================================================


def _add_store(db_session, store_id, name, *, subcategory, facets=None, floor_id=FLOOR_ID):
    """탐색 후보를 늘리기 위한 임시 매장. db_session 픽스처가 닫히며 롤백된다."""
    store = Store(
        id=store_id,
        floor_id=floor_id,
        name=name,
        category="패션",
        subcategory=subcategory,
        search_facets=facets,
        centroid_x_m=10.0,
        centroid_y_m=10.0,
    )
    db_session.add(store)
    return store


def _seed_fashion_pool(db_session):
    """category="패션" tier 1 후보를 styles가 갈리도록 6건 추가한다.

    "패션"은 category 정확 일치(tier 1)라 경량이 후보 집합을 만들고, styles 값이
    스포츠/캐주얼/명품으로 갈려 clarify 조건(구분력 있는 축)이 성립한다.
    """
    rows = [
        ("sp-1", "스포츠샵1", "스포츠·아웃도어", {"styles": ["스포츠"]}),
        ("sp-2", "스포츠샵2", "스포츠·아웃도어", {"styles": ["스포츠"]}),
        ("cs-1", "캐주얼샵1", "캐주얼·스트리트", {"styles": ["캐주얼"]}),
        ("cs-2", "캐주얼샵2", "캐주얼·스트리트", {"styles": ["캐주얼"]}),
        ("lx-1", "명품샵1", "명품", {"styles": ["명품"]}),
        ("lx-2", "명품샵2", "명품", {"styles": ["명품"]}),
    ]
    for store_id, name, subcategory, facets in rows:
        _add_store(db_session, store_id, name, subcategory=subcategory, facets=facets)
    db_session.flush()


def _no_semantic(monkeypatch):
    """2차 의미 검색이 호출되면 테스트를 실패시킨다(호출 횟수 dict를 돌려준다)."""
    calls = {"n": 0}

    def spy(*_args, **_kwargs):
        calls["n"] += 1
        return query_semantic.SemanticResults(query_semantic.SemanticReason.BELOW_THRESHOLD)

    monkeypatch.setattr(query_semantic, "search_many", spy)
    return calls


def test_discover_정확한_이름은_direct_1건이다(db_session, monkeypatch):
    calls = _no_semantic(monkeypatch)

    result = query_search.discover(db_session, BUILDING_ID, "가게A 어디야?")

    assert result["mode"] == "direct"
    assert [match["name"] for match in result["matches"]] == ["가게A"]
    assert result["question"] is None
    assert result["options"] == []
    assert calls["n"] == 0  # 1차에서 확정 → 2차 미호출


def test_discover_후보가_넓고_구분력_있는_축이_있으면_clarify다(db_session, monkeypatch):
    _no_semantic(monkeypatch)
    _seed_fashion_pool(db_session)

    result = query_search.discover(db_session, BUILDING_ID, "패션")

    assert result["mode"] == "clarify"
    assert result["question"] == "어떤 스타일을 찾으세요?"
    # 실제 후보가 있는 값만 option이 된다. 값별 count는 이름 중복 제거 후 후보 기준.
    assert {option["value"] for option in result["options"]} == {"스포츠", "캐주얼", "명품"}
    assert all(option["facet"] == "styles" for option in result["options"])
    assert all(option["count"] == 2 for option in result["options"])
    # 질문과 함께 보여줄 초기 후보는 3건(12절 확정).
    assert len(result["matches"]) == CLARIFY_PREVIEW


# clarify 화면의 "전체 보기"는 선택 chip을 비운 채 같은 질의를 다시 보낸다.
# show_all 계약이 없으면 selected_facets={}가 선택 없음으로 처리되어 다시 clarify가 된다.
def test_discover_전체_보기는_빈_선택에서도_clarify를_건너뛴다(db_session, monkeypatch):
    _no_semantic(monkeypatch)
    _seed_fashion_pool(db_session)

    result = query_search.discover(
        db_session,
        BUILDING_ID,
        "패션",
        selected_facets={},
        show_all=True,
    )

    assert result["mode"] == "results"
    assert result["question"] is None
    assert result["options"] == []
    # 후보 7건(패션 6 + 기본 매장 1)이 전부 온다. 예전에는 여기가 추천 상한(5)에
    # 걸려 "전체 보기"를 눌러도 5건뿐이었다 — 사용자가 더 있는 줄 아는 자리라
    # 상한을 분리했다. 아래 상한 테스트가 무제한이 아님을 함께 고정한다.
    assert len(result["matches"]) == 7
    assert len(result["matches"]) > MAX_MATCHES


# 전체 보기도 무제한은 아니다. 주차 787건 같은 축이 걸리면 응답이 통째로 커진다.
def test_discover_전체_보기는_show_all_상한까지만_준다(db_session, monkeypatch):
    _no_semantic(monkeypatch)
    # 상한을 넘기도록 tier 1("패션") 후보를 상한 + 5건 만든다.
    for index in range(MAX_SHOW_ALL + 5):
        _add_store(db_session, f"bulk-{index}", f"패션샵{index}", subcategory="컨템포러리")
    db_session.flush()

    result = query_search.discover(db_session, BUILDING_ID, "패션", show_all=True)

    assert result["mode"] == "results"
    assert len(result["matches"]) == MAX_SHOW_ALL


def test_discover_clarify_초기후보는_서로_다른_소분류로_퍼진다(db_session, monkeypatch):
    _no_semantic(monkeypatch)
    _seed_fashion_pool(db_session)

    result = query_search.discover(db_session, BUILDING_ID, "패션")

    subcategories = [match["subcategory"] for match in result["matches"]]
    assert len(set(subcategories)) == len(subcategories)  # 한 소분류에 몰리지 않는다


def test_discover_clarify_후보는_검증된_태그로만_reason을_만든다(db_session, monkeypatch):
    _no_semantic(monkeypatch)
    _seed_fashion_pool(db_session)

    result = query_search.discover(db_session, BUILDING_ID, "패션")

    for match in result["matches"]:
        if match["matched_facets"]:
            assert set(match["matched_facets"]) == {"styles"}
            assert match["reason"] == f"{match['matched_facets']['styles'][0]} 스타일 매장이에요."
        else:
            assert match["reason"] is None  # 태그가 없으면 이유를 만들지 않는다


def test_discover_구분력_있는_축이_없으면_clarify_대신_results다(db_session, monkeypatch):
    _no_semantic(monkeypatch)
    # 후보는 넓지만(6건) styles가 전부 "명품" 하나 — 되물어도 후보가 그대로다.
    for index in range(6):
        _add_store(
            db_session,
            f"lux-{index}",
            f"명품샵{index}",
            subcategory="명품",
            facets={"styles": ["명품"]},
        )
    db_session.flush()

    result = query_search.discover(db_session, BUILDING_ID, "명품")

    assert result["mode"] == "results"
    assert result["question"] is None
    assert result["options"] == []
    # 되물음이 없으면 이 목록이 곧 최종 답이라 추천 상한(5)으로 자르지 않는다.
    # 자르면 6번째 매장으로 갈 방법이 화면에 남지 않는다("전체 보기"는 clarify 전용).
    assert len(result["matches"]) == 6
    assert len(result["matches"]) <= MAX_SHOW_ALL


# **실기기에서 잡았다.** `샤낼 뷰티`를 치니 `향수 (10)` `화장품 (10)` 두 chip이 떴는데
# 어느 쪽을 눌러도 같은 10건이었다. `_intents.json`의 두 intent가 같은 규칙
# (`subcategory: ["화장품·향수"]`)이라 가리키는 매장 집합이 동일했기 때문이다.
# 고르는 행동이 아무것도 바꾸지 못하는 질문은 질문이 아니다.
def test_discover_같은_후보를_가리키는_값들은_질문이_되지_않는다(db_session, monkeypatch):
    _no_semantic(monkeypatch)
    # 6건 모두 두 값을 함께 갖는다 — 값은 2개지만 나누는 힘은 0이다.
    for index in range(6):
        _add_store(
            db_session,
            f"beauty-{index}",
            f"뷰티샵{index}",
            subcategory="화장품·향수",
            facets={"intents": ["화장품", "향수"]},
        )
    db_session.flush()

    result = query_search.discover(db_session, BUILDING_ID, "화장품·향수")

    assert result["mode"] == "results"
    assert result["question"] is None
    assert result["options"] == []


# 겹치되 **완전히 같지는 않은** 값은 여전히 질문이 된다. 위 수정이 정상적인 되물음까지
# 잡아먹으면 clarify가 통째로 죽으므로 경계를 함께 고정한다.
def test_discover_일부만_겹치는_값은_질문으로_남는다(db_session, monkeypatch):
    _no_semantic(monkeypatch)
    # 4건은 두 값을 함께 갖고, 2건은 한쪽만 갖는다 → 고르면 후보가 실제로 줄어든다.
    for index in range(4):
        _add_store(
            db_session,
            f"both-{index}",
            f"둘다샵{index}",
            subcategory="화장품·향수",
            facets={"intents": ["화장품", "향수"]},
        )
    for index in range(2):
        _add_store(
            db_session,
            f"only-{index}",
            f"화장품만샵{index}",
            subcategory="화장품·향수",
            facets={"intents": ["화장품"]},
        )
    db_session.flush()

    result = query_search.discover(db_session, BUILDING_ID, "화장품·향수")

    assert result["mode"] == "clarify"
    assert {option["value"] for option in result["options"]} == {"화장품", "향수"}


def test_discover_태그가_얇은_축은_질문으로_쓰지_않는다(db_session, monkeypatch):
    _no_semantic(monkeypatch)
    # 값은 2개지만(스포츠·캐주얼) 태그가 있는 후보는 8건 중 2건뿐이다. 이 질문에
    # 답하면 태그 없는 6건이 통째로 사라지므로 되묻지 않는다.
    _add_store(db_session, "thin-1", "얇은샵1", subcategory="슈즈", facets={"styles": ["스포츠"]})
    _add_store(db_session, "thin-2", "얇은샵2", subcategory="슈즈", facets={"styles": ["캐주얼"]})
    for index in range(6):
        _add_store(db_session, f"plain-{index}", f"무태그샵{index}", subcategory="잡화")
    db_session.flush()

    result = query_search.discover(db_session, BUILDING_ID, "패션")

    assert result["mode"] == "results"
    assert result["options"] == []


def test_discover_selected_facets가_후보를_좁히면_results다(db_session, monkeypatch):
    _no_semantic(monkeypatch)
    _seed_fashion_pool(db_session)

    result = query_search.discover(
        db_session,
        BUILDING_ID,
        "패션",
        selected_facets={"styles": ["스포츠"]},
    )

    assert result["mode"] == "results"
    assert {match["name"] for match in result["matches"]} == {"스포츠샵1", "스포츠샵2"}
    for match in result["matches"]:
        assert match["matched_facets"] == {"styles": ["스포츠"]}
        assert match["reason"] == "스포츠 스타일 매장이에요."


def test_discover_선택이_후보를_0건으로_만들면_선택을_해제한다(db_session, monkeypatch):
    _no_semantic(monkeypatch)
    _seed_fashion_pool(db_session)

    result = query_search.discover(
        db_session,
        BUILDING_ID,
        "패션",
        selected_facets={"cuisines": ["일식"]},  # 이 후보 집합에 없는 축
    )

    # 막다른 흐름(빈 결과)을 만들지 않는다 — 선택을 해제하고 전체 후보 판정으로 되돌아간다.
    # 이 후보 집합은 넓고 styles가 갈리므로 되돌아간 자리가 clarify다.
    assert result["mode"] == "clarify"
    assert result["matches"]
    assert all(match["matched_facets"].keys() <= {"styles"} for match in result["matches"])


def test_discover_같은_이름_시설은_층만_달라도_한_번만_나온다(db_session, monkeypatch):
    _no_semantic(monkeypatch)

    # "가게"는 1F·2F의 가게A·가게B에 부분 일치한다(총 4행, 이름은 2개).
    result = query_search.discover(db_session, BUILDING_ID, "가게")

    assert result["mode"] == "results"
    names = [match["name"] for match in result["matches"]]
    assert sorted(names) == ["가게A", "가게B"]


def test_discover_이름_중복_제거는_현재_층을_대표로_고른다(db_session, monkeypatch):
    _no_semantic(monkeypatch)

    result = query_search.discover(db_session, BUILDING_ID, "가게", current_floor_id="2F")

    # 후보 제거가 아니라 정렬 보조다 — 후보 수는 그대로고 대표 층만 현재 층이 된다.
    assert {match["name"] for match in result["matches"]} == {"가게A", "가게B"}
    assert all(match["floor_name"] == "2F" for match in result["matches"])


def test_discover_2차도_못_찾으면_no_match다(db_session, monkeypatch):
    monkeypatch.setattr(
        query_semantic,
        "search_many",
        lambda *a, **k: query_semantic.SemanticResults(query_semantic.SemanticReason.BELOW_THRESHOLD),
    )

    result = query_search.discover(db_session, BUILDING_ID, "존재하지않는것")

    assert result["mode"] == "no_match"
    assert result["matches"] == []
    assert result["options"] == []


def test_discover_모델이_없으면_degraded다(db_session, monkeypatch):
    monkeypatch.setattr(
        query_semantic,
        "search_many",
        lambda *a, **k: query_semantic.SemanticResults(query_semantic.SemanticReason.MODEL_UNAVAILABLE),
    )

    result = query_search.discover(db_session, BUILDING_ID, "밥 먹을 데")

    # no_match("다른 말로 다시")와 구분된다 — 질의를 바꿔도 결과가 달라지지 않는 상태.
    assert result["mode"] == "degraded"


def test_discover_경량이_놓치면_2차_상위_N을_후보로_쓴다(db_session, monkeypatch):
    rows = _load_stores(db_session, BUILDING_ID)
    hits = tuple((0.7 - index * 0.01, store, floor) for index, (store, floor) in enumerate(rows))
    monkeypatch.setattr(
        query_semantic,
        "search_many",
        lambda *a, **k: query_semantic.SemanticResults(query_semantic.SemanticReason.OK, hits),
    )

    result = query_search.discover(db_session, BUILDING_ID, "밥 먹을 데")

    assert result["mode"] == "results"
    assert 0 < len(result["matches"]) <= MAX_MATCHES
    names = [match["name"] for match in result["matches"]]
    assert len(names) == len(set(names))  # 다양성 보정: 이름 중복 없음


def test_discover_없는_건물은_None을_반환한다(db_session):
    assert query_search.discover(db_session, "no-such", "가게A") is None


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
    monkeypatch.setattr(query_semantic, "_get_index", lambda *a, **k: (_FakeIndex(), [store.id]))
    monkeypatch.setattr(query_semantic, "_encode", lambda *a, **k: np.zeros((1, 3), dtype="float32"))
    return store, floor
