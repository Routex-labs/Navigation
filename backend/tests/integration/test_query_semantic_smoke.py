"""임베딩 의미 검색 실동작 스모크 (모델 다운로드 필요 — 기본 실행에서 제외).

기본 `pytest`는 오프라인·고속을 유지해야 하므로 이 스모크는 env로만 켠다:
    NAV_TEST_EMBEDDING=1 pytest tests/integration/test_query_semantic_smoke.py

실데이터로 (a) 모델 로드 → (b) 건물 인덱스 빌드 → (c) 자연어 검색까지 실제로 도는지 본다.
매장 수·정확한 매칭 대상은 데이터 편집으로 바뀌므로 단언하지 않고 불변식만 검사한다.
"""

import os

import pytest

from app.repositories import query_semantic
from tests.conftest import REAL_BUILDING_ID

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
