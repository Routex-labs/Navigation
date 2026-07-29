"""query_search 경량 매칭 로직 단위 테스트.

DB 없이 순수 함수(_normalize_query·_rank·_status)를 transient ORM 객체로 검증한다.
동의어 테스트는 resources/query_synonyms.json 실파일에 의존한다.
"""

from app.models import Floor, Store
from app.repositories import query_search


def _store(store_id: str, name: str, *, category=None, subcategory=None, entrance="N-1"):
    return Store(
        id=store_id,
        floor_id="F1",
        name=name,
        category=category,
        subcategory=subcategory,
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
