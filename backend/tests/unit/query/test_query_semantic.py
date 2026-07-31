"""query_semantic 인덱스 캐시 무효화(지문 기반) 단위 테스트.

모델 로드 없이 검증한다 — `_build_index`를 monkeypatch로 대체해 실제 임베딩·faiss를
호출하지 않는다. 실제 임베딩 검색 품질은 test_query_semantic_smoke(env 게이트)가 본다.

배경: docs/backend/native/search-qa-fix-wave.md Wave 5-b, conversational-discovery.md 6-1절.
서버를 띄운 채 별도 프로세스(reset_and_seed)로 재시딩하면 서버의 `_indexes` 캐시는
비워지지 않는다. `_get_index`가 매 호출마다 매장 수 + max(store.id) 지문을 값싼 SQL로
재계산해, 지문이 바뀌었을 때만 재빌드하도록 고쳤다.
"""

from app.models import Store
from app.repositories import query_semantic
from tests.conftest import BUILDING_ID, FLOOR_ID


def _build_spy(monkeypatch):
    """`_build_index` 호출 횟수를 세는 스텁으로 교체한다. 모델·faiss 미사용."""
    calls: list[int] = []

    def fake_build_index(session, building_id):
        calls.append(1)
        return object(), ["stub-store-id"]

    monkeypatch.setattr(query_semantic, "_build_index", fake_build_index)
    return calls


def test_같은_데이터면_인덱스가_재빌드되지_않는다(db_session, monkeypatch):
    query_semantic.reset_indexes()
    calls = _build_spy(monkeypatch)

    first = query_semantic._get_index(db_session, BUILDING_ID)
    second = query_semantic._get_index(db_session, BUILDING_ID)

    assert first is not None
    assert first == second
    assert len(calls) == 1  # 두 번째 호출은 지문이 같아 캐시를 그대로 재사용


def test_매장_수가_바뀌면_인덱스가_재빌드된다(db_session, monkeypatch):
    query_semantic.reset_indexes()
    calls = _build_spy(monkeypatch)

    query_semantic._get_index(db_session, BUILDING_ID)
    assert len(calls) == 1

    # 재시딩을 흉내낸다: 매장 하나를 추가해 count(*) 지문을 바꾼다.
    # commit하지 않아 다른 테스트로 새지 않는다(db_session fixture가 종료 시 rollback).
    db_session.add(
        Store(
            id="test-fingerprint-store",
            floor_id=FLOOR_ID,
            name="지문 테스트 매장",
            centroid_x_m=0.0,
            centroid_y_m=0.0,
        )
    )
    db_session.flush()

    query_semantic._get_index(db_session, BUILDING_ID)

    assert len(calls) == 2  # 지문이 달라져 재빌드됐다


def test_지문_계산은_매장_수와_최대_id를_반영한다(db_session, monkeypatch):
    query_semantic.reset_indexes()

    before = query_semantic._compute_fingerprint(db_session, BUILDING_ID)

    db_session.add(
        Store(
            id="test-fingerprint-store-2",
            floor_id=FLOOR_ID,
            name="지문 테스트 매장 2",
            centroid_x_m=0.0,
            centroid_y_m=0.0,
        )
    )
    db_session.flush()

    after = query_semantic._compute_fingerprint(db_session, BUILDING_ID)

    assert after[0] == before[0] + 1  # count(*) 증가
    assert after != before


# ── 문서 텍스트 — 임베딩 인덱스가 매장을 어떤 글자로 표현하는가 ──────────────


def test_문서_텍스트는_intents를_포함한다():
    """intents가 문서에 들어가야 "운동화 사고 싶다"가 나이키 라이즈에 닿을 근거가 생긴다.

    나이키 라이즈의 분류 라벨은 캐주얼·스트리트뿐이라, 검수된 intents 태그가 문서에
    없으면 신발 관련 질의가 의미상 가까워질 글자가 문서 어디에도 없다. 축 순서는
    (intents, styles, cuisines)로 고정이다 — 흔들리면 같은 매장이 실행마다 다른
    문서 텍스트를 만들어 재현성이 깨진다.
    """
    store = Store(
        id="doc-1",
        floor_id=FLOOR_ID,
        name="나이키 라이즈",
        category="패션",
        subcategory="캐주얼·스트리트",
        search_facets={"styles": ["캐주얼"], "intents": ["신발"]},
        centroid_x_m=0.0,
        centroid_y_m=0.0,
    )

    assert query_semantic._document_text(store) == "나이키 라이즈 패션 캐주얼·스트리트 신발 캐주얼"


def test_문서_텍스트는_태그가_없으면_기존과_같다():
    """미태깅 매장(대다수)의 문서는 이름+카테고리 그대로다 — 임계값 분포가 흔들리지 않는다."""
    store = Store(
        id="doc-2",
        floor_id=FLOOR_ID,
        name="가게A",
        category="편의시설",
        subcategory=None,
        search_facets=None,
        centroid_x_m=0.0,
        centroid_y_m=0.0,
    )

    assert query_semantic._document_text(store) == "가게A 편의시설"
