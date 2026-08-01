"""실제 Studio 데이터(resources/studio)를 시드했을 때의 불변식 스모크 테스트.

매장 수·노드 수 같은 값은 Studio에서 편집할 때마다 바뀌므로 단언하지 않는다.
대신 편집으로는 깨지면 안 되는 성질만 검증한다. 응답 값 자체의 정확성은
합성 픽스처 테스트(test-tower)가 담당한다.
"""

import json

import pytest
from sqlalchemy import select

from app.core.config import API_ROOT
from app.models import Building, Edge, Floor, Node, Store
from app.repositories import query_search, query_semantic
from tests.conftest import REAL_BUILDING_ID, REAL_FLOOR_NAME


# 모든 층이 적재되고 기준층이 포함되는지 확인한다.
def test_모든_층이_적재된다(real_db_session):
    floors = real_db_session.scalars(select(Floor).where(Floor.building_id == REAL_BUILDING_ID)).all()

    assert len(floors) >= 2, "다층 적재를 검증하려면 최소 2개 층이 필요하다"
    assert REAL_FLOOR_NAME in {floor.name for floor in floors}
    # 층 level은 층마다 유일해야 층 정렬이 안정적이다.
    levels = [floor.level for floor in floors]
    assert len(levels) == len(set(levels))


# 간선이 실존하는 노드만 참조하는지(참조 무결성) 확인한다.
def test_간선은_실존하는_노드만_참조한다(real_db_session):
    node_ids = set(real_db_session.scalars(select(Node.id)).all())
    edges = real_db_session.scalars(select(Edge)).all()

    assert edges
    dangling = [edge.id for edge in edges if edge.from_node_id not in node_ids or edge.to_node_id not in node_ids]
    assert dangling == []


# 매장 입구가 실존 노드를 가리키는지 확인한다.
def test_매장_입구는_실존하는_노드를_가리킨다(real_db_session):
    node_ids = set(real_db_session.scalars(select(Node.id)).all())
    stores = real_db_session.scalars(select(Store)).all()

    assert stores
    dangling = [
        store.id for store in stores if store.entrance_node_id is not None and store.entrance_node_id not in node_ids
    ]
    assert dangling == []


# 다베오 원본은 식음료 매장도 "시설 속성"(OB-RESTAURANT/OB-CAFE)으로 태깅하는 탓에
# 변환기가 전부 편의시설로 뭉갤 수 있다. 층·소분류가 서로 다른 대표 매장 몇 곳만
# 골라 대분류가 식음료로 유지되는지 확인한다. 개수는 데이터 편집마다 바뀌므로
# 단언하지 않고, 소분류도 재조정 여지가 있어 대분류만 고정한다.
@pytest.mark.parametrize(
    "store_name",
    ["스타벅스 리저브", "런던베이글 뮤지엄", "파이브 가이즈", "정돈 프리미엄", "카페 H"],
)
def test_대표_식음료_매장은_편의시설로_분류되지_않는다(real_db_session, store_name):
    stores = real_db_session.scalars(select(Store).where(Store.name == store_name)).all()

    assert stores, f"{store_name!r}가 실데이터에 없다"
    for store in stores:
        assert store.category == "식음료", f"{store_name} -> {store.category}"


# 층을 잇는 수직 전이 간선이 생성되고, 서로 다른 층을 잇는지 확인한다.
def test_수직_전이_간선이_층을_잇는다(real_db_session):
    node_floor = dict(real_db_session.execute(select(Node.id, Node.floor_id)).all())
    transfers = real_db_session.scalars(select(Edge).where(Edge.transfer_mode.is_not(None))).all()

    assert transfers, "층 간 이동 경로를 만들려면 전이 간선이 있어야 한다"
    for edge in transfers:
        # 전이 간선은 특정 층에 속하지 않는다(단일 층 조회에서 제외되어야 하므로).
        assert edge.floor_id is None
        assert node_floor[edge.from_node_id] != node_floor[edge.to_node_id]


# 모든 층 노드가 건물 공통 프레임으로 정규화됐는지 확인한다.
def test_모든_층_노드가_같은_좌표_프레임에_있다(real_db_session):
    floors = real_db_session.scalars(select(Floor).where(Floor.building_id == REAL_BUILDING_ID)).all()
    building = real_db_session.get(Building, REAL_BUILDING_ID)
    assert building.footprint_local_m, "건물 외곽이 있어야 정규화 범위를 검증할 수 있다"

    # 각 층의 노드는 그 층 외곽 bbox에 여유를 둔 범위 안에 들어와야 한다.
    # (층 프레임이 정규화되지 않으면 스케일이 달라 크게 벗어난다.)
    #
    # 층마다 자기 외곽선으로 재는 것이 핵심이다. 지하 주차장은 지상 타워보다
    # 훨씬 넓어(B3 295x148m 대 1F 167x98m) 기준층 외곽에 마진을 더하는 방식으로는
    # 검증이 성립하지 않는다.
    above_ground_margin = 15.0
    basement_margin = 30.0

    for floor in floors:
        footprint = floor.footprint_local_m or building.footprint_local_m
        assert footprint, f"{floor.name} 외곽선이 없다"
        margin = basement_margin if floor.level < 0 else above_ground_margin
        min_x = min(point["x"] for point in footprint) - margin
        max_x = max(point["x"] for point in footprint) + margin
        min_y = min(point["y"] for point in footprint) - margin
        max_y = max(point["y"] for point in footprint) + margin

        nodes = real_db_session.scalars(select(Node).where(Node.floor_id == floor.id)).all()
        assert nodes
        outside = [node.id for node in nodes if not (min_x <= node.x_m <= max_x and min_y <= node.y_m <= max_y)]
        assert outside == [], f"{floor.name} 노드가 건물 범위를 벗어남: {outside[:3]}"


# 모든 노드가 wgs84를 갖는지 확인한다(지오레퍼런스 피팅의 앵커가 된다).
def test_모든_노드가_wgs84를_갖는다(real_db_session):
    nodes = real_db_session.scalars(select(Node)).all()

    assert nodes
    assert [node.id for node in nodes if node.lat is None or node.lng is None] == []


# 선언된 동의어가 모두 실존 장소로 매칭되는지 확인한다(죽은 항목 방지).
# 브랜드가 데이터에서 사라지면 이 테스트가 그 동의어를 잡아낸다.
#
# 판정 기준은 `match`가 있는지가 아니라 status가 `no_match`가 **아닌지**다.
# 표준형이 intent를 가리키는 동의어("커피"→"카페", "옷"→"의류")는 수십 건에 걸리므로
# `match_destination`이 의도적으로 `ambiguous`(match=null)를 준다 — 확정할 수 없는
# 질의를 임의의 1건으로 고정하지 않는다는 규칙이다. 이걸 죽은 항목으로 세면 테스트가
# 그 규칙과 정반대를 요구하게 된다. 죽은 동의어는 후보가 0건인 `no_match`뿐이다.
def test_동의어_사전은_실존_장소로_매칭된다(real_db_session):
    synonyms = json.loads((API_ROOT / "resources" / "query_synonyms.json").read_text(encoding="utf-8"))

    assert synonyms, "동의어 사전이 비어 있다"
    dead = [
        alias
        for alias in synonyms
        if (query_search.match_destination(real_db_session, REAL_BUILDING_ID, alias) or {}).get("status")
        in (None, "no_match")
    ]
    assert dead == [], f"매칭되지 않는 동의어(죽은 항목): {dead}"


# 전 층에 깔린 편의시설이 조사·의문형이 붙은 질의로도 DB 경로에서 잡히는지 확인한다.
# 정규화 자체의 전수 검사는 tests/unit/test_query_coverage.py가 하고, 여기서는
# 실제 세션·조인·층 목록까지 이어지는지만 본다.
@pytest.mark.parametrize(
    ("facility", "min_floors"),
    [("엘리베이터", 12), ("에스컬레이터", 12), ("화장실", 11)],
)
@pytest.mark.parametrize("suffix", ["", " 어디야", "까지 가고 싶어", " 몇 층이야"])
def test_편의시설은_조사가_붙어도_여러_층에서_매칭된다(real_db_session, facility, min_floors, suffix):
    result = query_search.match_info(real_db_session, REAL_BUILDING_ID, facility + suffix)

    assert result is not None
    assert result["status"] == "ok", f"{facility + suffix!r} 매칭 실패"
    assert result["match"]["name"] == facility
    # "화장실"은 부분 일치로 "장애인화장실"의 층까지 모으므로 하한만 본다.
    assert len(result["floors"]) >= min_floors, f"{facility} 층 목록: {result['floors']}"


# 오탐 회귀 가드 — query_morph.normalize가 형태소 분해로 오타·조사를 지우면서
# 질의가 1글자로 축소되면("샤낼"→"샤", "물 사고싶어"→"물") 그 1글자가 무관한 매장
# 이름 접두와 우연히 맞아 지하층 매장(B1 샤브미담, B4 물품보관함, B6 1C 등)을 오탐으로
# 뽑던 문제. tier 2(이름 부분 일치)에 질의 길이 2 이상 하한을 걸어 막는다.
@pytest.mark.parametrize("query", ["샤낼", "물 사고싶어", "1", "a", "..."])
def test_짧게_축소되는_질의는_오탐없이_no_match다(real_db_session, query):
    result = query_search.match_destination(real_db_session, REAL_BUILDING_ID, query)

    assert result is not None
    assert result["status"] == "no_match", f"{query!r} -> {result['match']}"


# 실데이터로 층 지도 API가 그래프와 매장 폴리곤을 함께 응답하는지 확인한다.
def test_층지도는_그래프와_매장_폴리곤을_함께_응답한다(real_api_client):
    response = real_api_client.get(f"/buildings/{REAL_BUILDING_ID}/floors/{REAL_FLOOR_NAME}")

    assert response.status_code == 200
    body = response.json()
    assert body["navigation_graph"]["nodes"] and body["navigation_graph"]["edges"]
    assert body["stores"]
    # 다베오 POI 중 연결된 도형 객체가 없는 것(호텔·설치 작품 같은 랜드마크)은
    # 점으로만 존재한다. 폴리곤이 있는 매장은 wgs84 폴리곤도 함께 와야 한다.
    with_polygon = [store for store in body["stores"] if store["polygon_local_m"]]
    assert with_polygon
    assert all(store["polygon_wgs84"] for store in with_polygon)


def test_elevator_typo_resolves_on_b2_without_semantic_fallback(real_db_session, monkeypatch):
    """A known typo must remain in the current-floor light matching path."""
    calls = {"count": 0}

    def semantic_spy(*_args, **_kwargs):
        calls["count"] += 1
        return query_semantic.SemanticResults(query_semantic.SemanticReason.BELOW_THRESHOLD)

    monkeypatch.setattr(query_semantic, "search_many", semantic_spy)

    direct = query_search.match_destination(
        real_db_session,
        REAL_BUILDING_ID,
        "엘레베이터",
        current_floor_id="B2",
    )
    discovery = query_search.discover(
        real_db_session,
        REAL_BUILDING_ID,
        "엘레베이터",
        current_floor_id="B2",
    )

    assert direct["match"]["name"] == "엘리베이터"
    assert direct["match"]["floor_name"] == "B2"
    assert discovery["mode"] == "direct"
    assert [match["floor_name"] for match in discovery["matches"]] == ["B2"]
    assert calls["count"] == 0


def test_current_floor_multiple_exits_are_returned_as_physical_choices(
    real_db_session,
):
    """Same-name exits are distinct physical choices, not duplicate stores."""
    rows = [
        (store, floor)
        for store, floor in query_search._load_stores(
            real_db_session,
            REAL_BUILDING_ID,
            current_floor_id="1F",
        )
        if store.name == "출구"
    ]
    assert len(rows) >= 2

    direct = query_search.match_destination(
        real_db_session,
        REAL_BUILDING_ID,
        "출구",
        current_floor_id="1F",
    )
    discovery = query_search.discover(
        real_db_session,
        REAL_BUILDING_ID,
        "출구",
        current_floor_id="1F",
    )

    assert direct["status"] == "ambiguous"
    assert direct["match"] is None

    # 현재 층 정보가 없어도 물리적으로 다른 출구 하나를 ID 정렬 순서로 임의
    # 확정하지 않는다. 빈 경량 결과가 discovery 목록으로 이어진다.
    unscoped_direct = query_search.match_destination(
        real_db_session,
        REAL_BUILDING_ID,
        "출구",
    )
    assert unscoped_direct["status"] == "ambiguous"
    assert unscoped_direct["match"] is None

    assert discovery["mode"] == "results"
    assert {match["store_id"] for match in discovery["matches"]} == {store.id for store, _floor in rows}
    assert {match["floor_name"] for match in discovery["matches"]} == {"1F"}


# ── intent 태깅 확장(W9) 실데이터 회귀 가드 ─────────────────────────────────


# 복합 라벨("카페·베이커리")은 tier 1 정확 일치가 못 잡아, 예전에는 "커피"가 상호에
# 그 글자가 든 1건으로만 확정됐다. intent "카페" + 동의어 "커피"→"카페"로 메운 지점이다.
def test_커피_질의가_카페_매장들을_후보로_준다(real_db_session):
    discovery = query_search.discover(real_db_session, REAL_BUILDING_ID, "커피")

    assert discovery["mode"] in ("clarify", "results")
    matches = discovery["matches"]
    assert len(matches) >= 3, f"후보가 너무 적다: {[m['name'] for m in matches]}"
    # 후보가 실제로 카페 계열이어야 한다 — 이름에 '커피'가 든 매장 긁어오기가 아니다.
    assert all(match["subcategory"] == "카페·베이커리" for match in matches), [
        (match["name"], match["subcategory"]) for match in matches
    ]


# 지하철 출입구는 소분류가 교통/facility로 갈려 있어 라벨만으로는 한쪽이 누락됐다.
def test_출구_질의가_지하철_출입구까지_포함한다(real_db_session):
    discovery = query_search.discover(real_db_session, REAL_BUILDING_ID, "출구")

    names = [match["name"] for match in discovery["matches"]]
    assert any("지하철" in name for name in names), names


# 추천 이유가 사용자가 친 말과 이어지는지. 질문 축(styles)만 basis에 담기던 시절에는
# "신발"을 물어도 "명품 스타일 매장이에요"만 나와 신발 근거가 사라졌다.
def test_신발_질의의_추천_이유가_신발을_말한다(real_db_session):
    discovery = query_search.discover(real_db_session, REAL_BUILDING_ID, "신발")

    reasons = [match["reason"] for match in discovery["matches"]]
    assert reasons, "후보가 없다"
    assert all(reason and "신발" in reason for reason in reasons), reasons


# 사용자가 방금 친 말을 선택지로 되돌려주지 않는다. 한 매장이 신발·의류를 함께 가지므로
# 이 가드가 없으면 "신발"에 "신발/의류 중 무엇을 찾으세요?"라는 메아리 질문이 선다.
def test_신발_질의는_신발을_선택지로_되묻지_않는다(real_db_session):
    discovery = query_search.discover(real_db_session, REAL_BUILDING_ID, "신발")

    values = [option["value"] for option in discovery["options"]]
    assert "신발" not in values, values
