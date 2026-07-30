"""형태소 정규화(query_morph)와 그것을 쓰는 query_search._normalize_query 단위 테스트.

검증 기준(docs/backend/native/KIWI.md 6절):
  - 개선: 조사·어미가 붙은 질의가 1차 경량 매칭에서 잡힌다.
  - 보존: 지금 되는 질의(브랜드·영문·숫자·동의어)가 그대로 된다.
  - 폴백: Kiwi가 없어도 보존 케이스가 통과한다.
"""

import pytest

from app.repositories import query_morph, query_search


@pytest.fixture
def kiwi_unavailable(monkeypatch):
    """Kiwi 로드 실패를 주입한다 — 미설치 환경 재현.

    monkeypatch가 테스트 종료 시 원래 싱글턴을 되돌려 주므로 따로 초기화하지 않는다.
    직접 `_kiwi = None`으로 리셋하면 다음 테스트마다 Kiwi를 재로드해(약 2초) 스위트가 느려진다.
    """
    monkeypatch.setattr(query_morph, "_kiwi", None)
    monkeypatch.setattr(query_morph, "_load_failed", True)


# --- 개선: 조사·어미가 붙어도 매장명만 남는다 ---
@pytest.mark.parametrize(
    ("query", "expected"),
    [
        ("화장실이 어디야", "화장실"),
        ("화장실이 어디야?", "화장실"),
        ("화장실이 어디야!", "화장실"),
        ("화장실이 어디야.", "화장실"),
        ("화장실이 어디야,", "화장실"),
        ("화장실이 어디야?????", "화장실"),
        ("스타벅스는 몇 층이야", "스타벅스"),
        ("스타벅스는 몇 층이야?", "스타벅스"),
        ("엘리베이터까지 가고 싶어", "엘리베이터"),
        ("엘리베이터까지 가고 싶어.", "엘리베이터"),
        ("화장실 급해", "화장실"),
        ("MLB는", "mlb"),
    ],
)
def test_조사와_어미가_붙어도_정규화된다(query, expected):
    assert query_search._normalize_query(query) == expected


# --- 보존: 기존에 되던 질의가 그대로 ---
@pytest.mark.parametrize(
    ("query", "expected"),
    [
        ("MLB", "mlb"),
        ("TAX REFUND", "tax refund"),  # 영문 다중 토큰 — 공백이 보존돼야 한다
        ("B1 주차", "b1 주차"),  # 숫자 + 의존명사 태그
        ("스벅", "스벅"),  # 동의어 키
        ("화장실", "화장실"),
        ("가게A 어디야", "가게a"),  # 한글+영문 붙은 이름 — 공백이 끼면 안 된다
        ("A.P.C. 어디야?", "a.p.c."),
        ("We,pet", "we,pet"),  # 내부 쉼표는 실제 매장명의 일부
        ("  화장실 몇 층이야 ", "화장실"),
        ("여자 화장실", "여자 화장실"),
    ],
)
def test_기존_질의는_그대로_유지된다(query, expected):
    assert query_search._normalize_query(query) == expected


# --- 폴백: Kiwi 없이도 기존 규칙으로 동작 ---
@pytest.mark.parametrize(
    ("query", "expected"),
    [
        ("MLB", "mlb"),
        ("TAX REFUND", "tax refund"),
        ("TAX REFUND.", "tax refund"),
        ("가게A 어디야", "가게a"),
        ("가게A 어디야?", "가게a"),
        ("  화장실 몇 층이야 ", "화장실"),
    ],
)
def test_kiwi가_없어도_기존_꼬리제거로_동작한다(kiwi_unavailable, query, expected):
    assert query_morph.normalize(query) is None
    assert query_search._normalize_query(query) == expected


# 분석 결과가 비면(전부 조사·용언) 폴백 — 1단계 결과를 그대로 쓴다.
def test_남는_형태소가_없으면_폴백한다():
    assert query_morph.normalize("가고 싶어") is None


# 브랜드 신조어가 사용자 사전으로 통째 보존된다("마" + "뗑킴"으로 쪼개지지 않음).
def test_브랜드_신조어가_쪼개지지_않는다():
    assert query_search._normalize_query("마뗑킴 어디야") == "마뗑킴"


# uvicorn은 요청을 스레드풀에서 처리하므로, 첫 요청들이 겹치면 사전 추가와 분석이 동시에 일어난다.
#
# 이 테스트가 증명하는 것: 락이 데드락을 만들지 않고, 사전이 바뀌는 도중에도 결과가 흔들리지 않는다.
# 증명하지 못하는 것: 락이 실제로 **필요한지**. 락을 무력화한 음성 대조군에서도 실패가
# 재현되지 않았다(kiwipiepy는 스레드 안전성을 문서화하지 않는다). query_morph._lock 주석 참고.
def test_사전_추가와_분석이_동시에_일어나도_안전하다():
    from concurrent.futures import ThreadPoolExecutor

    # 실데이터와 겹치지 않는 이름 — 다른 테스트의 매칭에 영향을 주지 않는다.
    batches = [[f"동시성시험매장{group}_{i}" for i in range(100)] for group in range(4)]

    def add(group: int) -> None:
        query_morph.register_words(batches[group])

    def normalize_repeatedly(_: int) -> set[str]:
        return {query_search._normalize_query("화장실이 어디야") for _ in range(200)}

    with ThreadPoolExecutor(max_workers=8) as pool:
        writers = [pool.submit(add, group) for group in range(4)]
        readers = [pool.submit(normalize_repeatedly, i) for i in range(4)]
        for future in writers:
            future.result()  # 예외가 났으면 여기서 터진다
        results = [future.result() for future in readers]

    # 사전이 바뀌는 도중에도 분석 결과가 흔들리지 않아야 한다.
    assert results == [{"화장실"}] * 4


# 실제 매칭까지 연결되는지 — 조사가 붙은 질의로 매장이 잡힌다.
def test_조사가_붙은_질의로_매장이_매칭된다():
    from app.models import Floor, Store

    floor = Floor(id="F1", building_id="B", name="1F", level=1)
    store = Store(
        id="s1",
        floor_id="F1",
        name="화장실",
        centroid_x_m=0.0,
        centroid_y_m=0.0,
        entrance_node_id="N-1",
    )
    scored = query_search._rank([(store, floor)], "화장실이 어디야")
    assert scored and scored[0][3].id == "s1"


def test_마침표가_상호의_일부면_원문_정확일치가_우선한다():
    from app.models import Floor, Store

    floor = Floor(id="F1", building_id="B", name="1F", level=1)
    exact = Store(
        id="s-exact",
        floor_id="F1",
        name="A.P.C.",
        centroid_x_m=0.0,
        centroid_y_m=0.0,
        entrance_node_id="N-1",
    )
    partial = Store(
        id="s-partial",
        floor_id="F1",
        name="A.P.C 골프",
        centroid_x_m=1.0,
        centroid_y_m=1.0,
        entrance_node_id="N-2",
    )

    for query in ("A.P.C.", "A.P.C.?"):
        scored = query_search._rank([(partial, floor), (exact, floor)], query)
        assert scored[0][0] == 0
        assert scored[0][3].id == "s-exact"


def test_구두점뿐인_질의는_빈_카테고리와_일치하지_않는다():
    from app.models import Floor, Store

    floor = Floor(id="F1", building_id="B", name="1F", level=1)
    store = Store(
        id="s1",
        floor_id="F1",
        name="가게",
        category=None,
        subcategory=None,
        centroid_x_m=0.0,
        centroid_y_m=0.0,
        entrance_node_id="N-1",
    )

    assert query_search._rank([(store, floor)], "?") == []


def test_저장소를_직접_호출해도_질의_길이_상한을_지킨다():
    assert query_search._query_candidates("?" * 201) == ()


# --- 공백 포함 매장명 회귀 (리눅스 CI 실패 재현) ---
# `add_user_word`는 공백이 든 이름을 한 형태소로 인정하지 않을 수 있다. 실제로
# "물품 보관함은 몇 층이야"가 리눅스 CI에서 "물품 보관"으로 잘렸는데, 같은
# kiwipiepy 0.23.2·같은 모델인 Windows에서는 재현되지 않았다. 그래서 등록 실패를
# 강제해 플랫폼과 무관하게 이 회귀를 잡는다.
@pytest.fixture
def 사전등록_실패(monkeypatch):
    """공백이 든 단어의 `add_user_word`만 실패시킨다."""
    kiwi = query_morph._get_kiwi()
    if kiwi is None:
        pytest.skip("kiwipiepy 미설치 — 폴백 경로라 검증 대상이 아니다")

    original = kiwi.add_user_word

    def 거부(word, tag="NNP", *args, **kwargs):
        if " " in word:
            raise ValueError("공백 포함 단어 거부")
        return original(word, tag, *args, **kwargs)

    monkeypatch.setattr(kiwi, "add_user_word", 거부)
    monkeypatch.setattr(query_morph, "_registered", set())
    monkeypatch.setattr(query_morph, "_registered_lower", set())
    query_morph.register_words(["물품 보관함", "스타벅스", "타임", "타임옴므"])


@pytest.mark.parametrize(
    ("query", "expected"),
    [
        ("물품 보관함", "물품 보관함"),          # 원문 그대로
        ("물품 보관함은", "물품 보관함"),        # 보조사
        ("물품 보관함 어디", "물품 보관함"),     # 공백 + 꼬리
        ("스타벅스에서", "스타벅스"),            # 공백 없는 이름은 기존 경로 유지
        ("타임옴므", "타임옴므"),                # 더 긴 이름이 짧은 이름으로 축소되지 않는다
    ],
)
def test_공백_포함_매장명은_사전등록이_실패해도_잘리지_않는다(사전등록_실패, query, expected):
    assert query_morph.normalize(query) == expected
