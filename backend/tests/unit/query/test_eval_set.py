"""평가 질의 세트(`scripts/eval/query_eval_set.json`)의 무결성.

이 테스트가 지키는 것은 **세트를 손으로 늘리다 생기는 사고**다. 세트는 사람이 계속
추가하는 파일이고, id 중복이나 정규식 오타가 들어가도 평가는 그냥 돌아버린다. 그러면
조용히 틀린 점수가 나오고, 그 점수로 임계값 같은 결정을 한다.

정답이 실제로 존재하는지(DB 대조)는 여기서 하지 않는다 — 시드된 DB가 필요해서
`evaluate_query_hybrid.validate_set()`이 담당한다. 여기는 DB·모델 없이 도는 검사만 둔다.

세트 설계와 클래스 정의는 docs/backend/native/search-eval-set.md.
"""

from __future__ import annotations

import pytest

from scripts.evaluate_query_hybrid import DEFAULT_SET_PATH, load_queries

# 기존 29개 기준선(FAISS.md 11절)에서 옮겨 온 질의 수. 이 부분집합의 문구·기대 패턴이
# 바뀌면 W7~W9 기록과 더 이상 비교할 수 없게 된다.
W9_BASELINE_COUNT = 29


@pytest.fixture(scope="module")
def queries():
    items, _meta = load_queries(DEFAULT_SET_PATH)
    return items


def test_세트를_읽고_중복_없이_파싱한다(queries):
    # Given/When: load_queries가 id·질의 중복과 정규식 오타에서 예외를 던진다.
    # Then: 예외 없이 읽혔다면 그 세 가지는 이미 통과한 것이다.
    assert len(queries) > 100, "세트가 100건 미만이면 클래스별 표본이 너무 얇다"


def test_기준선_29건이_그대로_남아_있다(queries):
    baseline = [item for item in queries if item.origin == "w9"]
    assert len(baseline) == W9_BASELINE_COUNT


def test_부정_질의는_기대_패턴이_없다(queries):
    for item in queries:
        if item.cls == "negative":
            assert item.expect is None, f"{item.id}: 부정 질의에 기대 패턴이 붙어 있다"
        else:
            assert item.expect, f"{item.id}: 긍정 질의에 기대 패턴이 없다"


def test_부정_질의가_충분히_많다(queries):
    # 부정이 적으면 "무의미 질의를 거른다"는 주장을 검증할 수 없다. 옛 세트는 부정이
    # 4건뿐이었고 전부 키보드 난타라, 임계값 0.50이 실재 업종명 부정("수영장")을
    # 통과시키고 있다는 사실을 못 보고 있었다.
    negatives = [item for item in queries if item.cls == "negative"]
    assert len(negatives) >= 20


def test_모든_질의에_알려진_클래스가_붙어_있다(queries):
    known = {
        "concept",
        "product",
        "facility",
        "situational",
        "exact",
        "typo",
        "english",
        "negative",
    }
    for item in queries:
        assert item.cls in known, f"{item.id}: 모르는 클래스 {item.cls}"


def test_질의_문구가_길이_제한_안에_있다(queries):
    # `/query` 엔드포인트는 빈 문자열과 200자 초과를 422로 막는다(FAISS.md 8절).
    # 세트에 그런 질의가 있으면 평가와 실제 API가 다른 것을 재게 된다.
    for item in queries:
        assert item.query.strip(), f"{item.id}: 빈 질의"
        assert len(item.query) <= 200, f"{item.id}: 200자 초과"
