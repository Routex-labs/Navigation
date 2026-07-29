"""임베딩 의미 검색 실동작 스모크 (모델 다운로드 필요 — 기본 실행에서 제외).

기본 `pytest`는 오프라인·고속을 유지해야 하므로 이 스모크는 env로만 켠다:
    NAV_TEST_EMBEDDING=1 pytest tests/integration/test_query_semantic_smoke.py

실데이터로 (a) 모델 로드 → (b) 건물 인덱스 빌드 → (c) 자연어 검색까지 실제로 도는지 본다.
매장 수·정확한 매칭 대상은 데이터 편집으로 바뀌므로 단언하지 않고 불변식만 검사한다.
"""

import os

import pytest

from app.repositories import query_search, query_semantic
from tests.conftest import REAL_BUILDING_ID, REAL_FLOOR_NAME

pytestmark = pytest.mark.skipif(
    os.environ.get("NAV_TEST_EMBEDDING") != "1",
    reason="임베딩 스모크는 모델 다운로드가 필요 — NAV_TEST_EMBEDDING=1로 실행",
)


# 자연어 질의가 파이프라인 끝까지 크래시 없이 돌고, 히트하면 계약을 지킨다.
def test_자연어_질의가_파이프라인_끝까지_동작한다(real_db_session):
    query_semantic.reset_indexes()

    hit = query_semantic.semantic_search(real_db_session, REAL_BUILDING_ID, "밥 먹을 곳")

    # 임계값을 넘으면 (score, Store, Floor), 못 넘으면 None — 둘 다 정상.
    if hit is not None:
        score, store, floor = hit
        assert query_semantic.SIMILARITY_THRESHOLD <= score <= 1.0
        assert store.id
        assert floor.building_id == REAL_BUILDING_ID


# 임계값 미달(무의미 문자열)은 None으로 걸러진다 — 엉뚱한 매장 반환 금지.
def test_무의미_질의는_임계값에서_걸러진다(real_db_session):
    query_semantic.reset_indexes()

    hit = query_semantic.semantic_search(real_db_session, REAL_BUILDING_ID, "asdfqwerzxcv")

    assert hit is None


# 회귀: 현재 층에 그 업종이 하나도 없어도 AI 질의는 타 층에서 찾아 준다.
# 클라이언트는 항상 보고 있는 층을 실어 보낸다(map_shell_screen: currentFloorId).
# 1F(식당 0개)에서 "밥집"을 물으면 2차가 층 필터에 전멸해 no_match가 나오던 버그.
def test_현재층에_업종이_없어도_AI질의는_타층에서_찾는다(real_db_session):
    query_semantic.reset_indexes()

    result = query_search.match_ai_destination(
        real_db_session,
        REAL_BUILDING_ID,
        "밥집",
        current_floor_id=REAL_FLOOR_NAME,  # "1F"
    )

    assert result is not None
    assert result["status"] in ("ok", "ok_no_route")
    assert result["match"]["floor_name"]  # 몇 층인지는 데이터에 맡기고 안내 가능만 본다
