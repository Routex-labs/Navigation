"""query_search 경량 매칭 로직 단위 테스트.

DB 없이 순수 함수(_normalize_query·_rank·_status)를 transient ORM 객체로 검증한다.
동의어 테스트는 resources/query_synonyms.json 실파일에 의존한다.
"""

import pytest

from app.models import Floor, Store
from app.repositories import query_search


def _store(store_id: str, name: str, *, category=None, subcategory=None, entrance="N-1", facets=None):
    return Store(
        id=store_id,
        floor_id="F1",
        name=name,
        category=category,
        subcategory=subcategory,
        search_facets=facets,
        centroid_x_m=0.0,
        centroid_y_m=0.0,
        entrance_node_id=entrance,
    )


def _floor(name: str = "1F", level: int = 1):
    return Floor(id="F1", building_id="B", name=name, level=level)


# 정규화 — 의문형/조사 꼬리를 최대 1개 제거하고 소문자로 만든다.
def test_정규화는_의문형_꼬리를_제거한다():
    assert query_search._normalize_query("가게A 어디야") == "가게a"
    assert query_search._normalize_query("  화장실 몇 층이야 ") == "화장실"
    assert query_search._normalize_query("MLB") == "mlb"


# 정확 이름 일치(tier 0)가 부분 일치(tier 2)보다 우선한다.
def test_정확한_이름이_부분일치보다_우선한다():
    floor = _floor()
    rows = [(_store("s2", "가게AB"), floor), (_store("s1", "가게A"), floor)]
    scored = query_search._rank(rows, "가게A")
    assert scored[0][3].id == "s1"


# 카테고리로도 매칭된다.
def test_카테고리로_매칭한다():
    rows = [(_store("s1", "MLB", category="편의시설"), _floor())]
    scored = query_search._rank(rows, "편의시설")
    assert scored and scored[0][3].id == "s1"


# intent 태그로도 매칭된다 — 사용자가 치는 말("신발")과 분류 라벨("슈즈")은 어긋나는 게
# 정상이다. 나이키 라이즈는 소분류가 캐주얼·스트리트라 라벨만 보면 영원히 안 잡힌다.
# 값의 출처는 시드가 _intents.json(규칙 + 검수된 예외 145건)에서 구운 search_facets다.
def test_intent_태그로_매칭한다():
    rows = [
        (
            _store("s1", "나이키 라이즈", subcategory="캐주얼·스트리트", facets={"intents": ["신발"]}),
            _floor(),
        )
    ]
    scored = query_search._rank(rows, "신발")

    assert scored and scored[0][3].id == "s1"
    assert scored[0][0] == 1  # 카테고리 일치와 같은 tier


# 태그가 없으면 잡히지 않는다 — "캐주얼·스트리트니까 신발일 것"이라는 추측을 하지 않는다
# (evaluate_query_hybrid.py가 기각한 "원리 없는 완화").
def test_intent_태그가_없으면_소분류로_추측하지_않는다():
    rows = [(_store("s1", "나이키 라이즈", subcategory="캐주얼·스트리트"), _floor())]

    assert query_search._rank(rows, "신발") == []


# 정확한 이름(tier 0)이 intent 일치(tier 1)보다 우선한다 — "신발"이라는 이름의 매장이
# 있다면 그게 먼저다.
def test_정확한_이름이_intent_일치보다_우선한다():
    floor = _floor()
    rows = [
        (_store("s1", "나이키 라이즈", facets={"intents": ["신발"]}), floor),
        (_store("s2", "신발"), floor),
    ]
    scored = query_search._rank(rows, "신발")

    assert scored[0][3].id == "s2"


# 동의어("엠엘비"→"MLB")로 매칭된다.
def test_동의어로_매칭한다():
    rows = [(_store("s1", "MLB"), _floor())]
    scored = query_search._rank(rows, "엠엘비")
    assert scored and scored[0][3].id == "s1"


# 동점은 (level, id) 순으로 항상 같은 결과 — 재현성 보장.
def test_동점은_level_id_순으로_결정적이다():
    rows = [
        (_store("s-2f", "가게A"), _floor("2F", 2)),
        (_store("s-1f", "가게A"), _floor("1F", 1)),
    ]
    scored = query_search._rank(rows, "가게A")
    assert [row[3].id for row in scored] == ["s-1f", "s-2f"]


def test_ai_확정판단은_같은_구두점_후보의_부분일치만_비교한다():
    floor = _floor()
    rows = [
        (_store("s-raw", "My Foo. Shop"), floor),
        (_store("s-stripped", "Foo Market"), floor),
    ]

    raw_scored = query_search._rank_with_candidate(rows, "Foo.")
    stripped_scored = query_search._rank_with_candidate(rows, "Foo")

    # "Foo." — 원문 후보(order 0)에 걸리는 건 "My Foo. Shop" 하나뿐이라 확정.
    assert query_search._is_confident_light_match(raw_scored) is True
    # "Foo" — 두 매장이 같은 후보(order 0)에 걸리지만 정밀도가 갈린다.
    # "Foo Market"은 이름 접두(_NAME_PREFIX), "My Foo. Shop"은 단어 접두(_WORD_PREFIX)라
    # 최상위 그룹에는 "Foo Market" 하나만 남는다 → 확정.
    # 사용자는 이름을 앞에서부터 치므로 접두 일치가 유일하면 그것으로 본다는 규칙이며,
    # 정밀도 축이 그룹 키에 들어가기 전에는 두 매장이 한 그룹이라 확정하지 않았다.
    # 정밀도가 같은데 이름이 다른 경우는 아래 테스트가 지킨다.
    assert query_search._is_confident_light_match(stripped_scored) is True


# 정밀도가 같은 서로 다른 매장은 확정하지 않는다 — AI 경로가 ID순 첫 매장을 임의로
# 고르지 않고 2차 의미 검색에 넘기게 하는 보호막이다.
def test_ai_확정판단은_같은_정밀도의_다른_이름을_확정하지_않는다():
    floor = _floor()
    rows = [
        (_store("s-a", "Foo Market"), floor),
        (_store("s-b", "Foo Bar"), floor),
    ]

    scored = query_search._rank_with_candidate(rows, "Foo")

    # 둘 다 이름이 "Foo"로 시작해 tier·후보 순서·정밀도가 모두 같다.
    assert {row[:3] for row in scored} == {(2, 0, 0)}
    assert query_search._is_confident_light_match(scored) is False


def test_info_층목록은_대표와_이름이_같은_매장만_포함한다():
    exact_floor = _floor("3F", 3)
    partial_floor = _floor("4F", 4)
    rows = [
        (_store("s-partial", "A.P.C 골프"), partial_floor),
        (_store("s-exact", "A.P.C."), exact_floor),
    ]

    scored = query_search._rank(rows, "A.P.C.")
    floors = query_search._floor_names_for_match(scored, scored[0][3].name)

    assert floors == ["3F"]


# 입구 노드가 없으면 ok_no_route로 구분된다.
def test_입구노드_없으면_ok_no_route():
    assert query_search._status(_store("s", "가게A", entrance=None)) == "ok_no_route"
    assert query_search._status(_store("s", "가게A")) == "ok"


# --- tier 2 길이 하한(2글자) 오탐 회귀 ---
# query_morph.normalize가 형태소 분해로 오타·조사를 지우면서 질의가 1글자로 축소되면
# ("샤낼"→"샤", "물 사고싶어"→"물") 그 1글자가 무관한 매장 이름 접두와 우연히 맞아
# 오탐이 났다. tier 2(이름 부분 일치)는 질의가 2글자 이상일 때만 시도한다.
def test_오타_질의는_1글자로_축소되어도_매칭되지_않는다():
    rows = [(_store("s1", "샤브미담"), _floor()), (_store("s2", "샤넬 뷰티"), _floor())]
    scored = query_search._rank(rows, "샤낼")
    assert scored == []


def test_조사_섞인_질의는_1글자로_축소되어도_매칭되지_않는다():
    rows = [(_store("s1", "물품보관함"), _floor())]
    scored = query_search._rank(rows, "물 사고싶어")
    assert scored == []


@pytest.mark.parametrize("query", ["1", "...", "a", "?", ".."])
def test_짧은_잡음_질의는_매칭되지_않는다(query):
    rows = [(_store("s1", "1F 안내데스크"), _floor()), (_store("s2", "A.P.C."), _floor())]
    scored = query_search._rank(rows, query)
    assert scored == []


# 한 글자 매장명 보호 — tier 0(정확 이름 일치)은 길이 하한의 영향을 받지 않는다.
def test_한글자_매장명은_정확_일치로_매칭된다():
    rows = [(_store("s1", "송"), _floor())]
    scored = query_search._rank(rows, "송")
    assert scored and scored[0][3].id == "s1"
    assert scored[0][0] == 0  # tier 0


# 이름이 여러 글자인 매장을 1글자로 찾으려는 부분 일치는 차단된다.
def test_1글자_질의로_여러글자_매장명_부분일치는_차단된다():
    rows = [(_store("s1", "송지오"), _floor())]
    scored = query_search._rank(rows, "송")
    assert scored == []


# 2글자 질의는 여전히 tier 2 부분 일치로 걸린다 — 경계 보존 확인.
def test_2글자_질의는_tier2_부분일치가_유지된다():
    rows = [(_store("s1", "CK 진"), _floor())]
    scored = query_search._rank(rows, "ck")
    assert scored and scored[0][3].id == "s1"
    assert scored[0][0] == 2  # tier 2


# 카테고리(tier 1)는 길이와 무관하게 매칭된다 — 길이 하한은 tier 2에만 적용된다.
def test_1글자_카테고리는_길이_무관하게_매칭된다():
    rows = [(_store("s1", "이름 무관 매장", category="편"), _floor())]
    scored = query_search._rank(rows, "편")
    assert scored and scored[0][3].id == "s1"
    assert scored[0][0] == 1  # tier 1
