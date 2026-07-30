"""실데이터 전 매장 정규화 커버리지 — 12개 층 1531건 전수 검사.

DB를 시드하지 않고 `resources/studio/stores_*.json`에서 **이름만** 읽어 순수 함수를 돌린다.
전수라도 1~2초면 끝나고, Studio 데이터가 바뀌어도 목록이 낡지 않는다.

왜 `_rank`가 아니라 `_query_candidates`를 보는가:
    `_tier`의 정확 이름 일치(tier 0)는 정규화 후보 중 하나가 `_norm(매장명)`이면 성립한다.
    전 매장 × 전 변형을 `_rank`로 돌리면 매 질의가 1531건을 훑어 O(n²)가 되지만,
    후보 포함 여부를 직접 비교하면 같은 것을 증명하면서 선형에 끝난다.
    실제 매칭 경로는 `test_query_morph.py`와 실데이터 스모크 테스트가 따로 덮는다.

이 테스트가 잡아낸 실제 회귀(구현 중):
    사용자 사전에 매장명을 안 넣으면 "리모와" → "리모"("와"를 접속조사로), "생로랑" → "생로",
    "발렌시아가" → "발렌시아" 로 잘렸다. 원문 질의인데도 깨지는 회귀가 1531건 중 35건이었다.
"""

import json

import pytest

from app.core.config import API_ROOT
from app.repositories import query_morph, query_search

_STUDIO = API_ROOT / "resources" / "studio" / "thehyundai-seoul-dabeeo"


def _load_store_names() -> dict[str, list[str]]:
    """층 라벨 → 매장명 목록."""
    by_floor: dict[str, list[str]] = {}
    for path in sorted(_STUDIO.glob("stores_*.json")):
        floor = path.stem.replace("stores_", "").upper()
        raw = json.loads(path.read_text(encoding="utf-8"))
        items = raw if isinstance(raw, list) else raw.get("data") or raw.get("stores") or []
        by_floor[floor] = [str(item["name"]) for item in items if isinstance(item, dict) and item.get("name")]
    return by_floor


_NAMES_BY_FLOOR = _load_store_names()
_ALL_NAMES = [name for names in _NAMES_BY_FLOOR.values() for name in names]


@pytest.fixture(scope="module", autouse=True)
def _register_names():
    """운영에서 `_rank`가 하는 일을 그대로 한다 — 매장명을 형태소 사전에 먼저 등록.

    이 등록이 빠지면 아래 전수 테스트가 35건 실패한다. 등록이 선택이 아니라
    전제 조건이라는 것을 이 픽스처가 드러낸다.
    """
    query_morph.register_words(_ALL_NAMES)


def _has_batchim(word: str) -> bool | None:
    """마지막 글자에 받침이 있는지. 한글로 끝나지 않으면 None(조사 변형 대상 아님).

    "펜디이 어디야"는 비문이다 — 받침 없는 이름엔 "가/는"을, 있는 이름엔 "이/은"을 붙여야
    테스트가 실제 사용자 질의를 흉내 낸다.
    """
    last = word.strip()[-1:]
    if not last or not ("가" <= last <= "힣"):
        return None
    return (ord(last) - 0xAC00) % 28 != 0


# (라벨, 받침 있을 때 접미사, 받침 없을 때 접미사)
_VARIANTS = [
    ("원문", "", ""),
    ("주격+의문", "이 어디야", "가 어디야"),
    ("보조사+층", "은 몇 층이야", "는 몇 층이야"),
    ("도달+희망", "까지 가고 싶어", "까지 가고 싶어"),
    ("공백+어디", " 어디", " 어디"),
    ("공백+위치", " 위치", " 위치"),
    ("공백+알려줘", " 알려줘", " 알려줘"),
]


def _failures(label: str, with_batchim: str, without_batchim: str) -> list[tuple[str, str]]:
    failed = []
    for name in _ALL_NAMES:
        batchim = _has_batchim(name)
        if batchim is None and with_batchim != without_batchim:
            continue  # 영문·숫자로 끝나는 이름엔 조사를 붙이지 않는다
        suffix = with_batchim if batchim else without_batchim
        candidates = query_search._query_candidates(name + suffix)
        if query_search._norm(name) not in candidates:
            failed.append((name, " | ".join(candidates)))
    return failed


# 데이터가 통째로 비면 아래 전수 테스트가 0건을 훑고 통과해 버린다 — 그걸 막는다.
def test_전층_매장_데이터가_적재된다():
    assert len(_NAMES_BY_FLOOR) == 12, f"12개 층이어야 한다: {sorted(_NAMES_BY_FLOOR)}"
    assert len(_ALL_NAMES) > 1000
    assert all(names for names in _NAMES_BY_FLOOR.values())


@pytest.mark.parametrize(("label", "with_batchim", "without_batchim"), _VARIANTS)
def test_전_매장이_조사_변형에도_이름으로_정규화된다(label, with_batchim, without_batchim):
    failed = _failures(label, with_batchim, without_batchim)
    assert failed == [], f"[{label}] 정규화 실패 {len(failed)}건: {failed[:10]}"


# 전 층에 존재하는 수직 이동수단·편의시설. 층 라벨은 매장 목록에서 확인한다.
_FACILITIES = {
    "엘리베이터": 12,  # 전 층
    "에스컬레이터": 12,  # 전 층
    "화장실": 11,  # B5 제외
    "장애인화장실": 7,
}

# 위 _VARIANTS에 자연어 서술형을 하나 더 얹는다("화장실 급해").
_FACILITY_VARIANTS = _VARIANTS + [("서술형", " 급해", " 급해")]


@pytest.mark.parametrize("facility", sorted(_FACILITIES))
@pytest.mark.parametrize(("label", "with_batchim", "without_batchim"), _FACILITY_VARIANTS)
def test_수직이동수단과_편의시설_질의가_정규화된다(facility, label, with_batchim, without_batchim):
    suffix = with_batchim if _has_batchim(facility) else without_batchim
    got = query_search._normalize_query(facility + suffix)
    assert got == facility, f"[{label}] {facility + suffix!r} → {got!r}"


# 이 시설들이 실제로 여러 층에 걸쳐 존재하는지 — 층 목록 응답(match_info)의 전제다.
@pytest.mark.parametrize(("facility", "floor_count"), sorted(_FACILITIES.items()))
def test_편의시설이_여러_층에_존재한다(facility, floor_count):
    floors = [floor for floor, names in _NAMES_BY_FLOOR.items() if facility in names]
    assert len(floors) == floor_count, f"{facility} 존재 층: {sorted(floors)}"


# 데이터에 "물품 보관함"과 "물품보관함"이 함께 있다. 사전 등록 순서에 따라 Kiwi가 띄어쓴 쪽을
# "물품 + 보관 + 하(XSV) + ㅁ(ETN)"으로 쪼갤 수 있다 — 붙임 표기를 먼저 등록하면 그렇게 된다.
# 현재는 파일 순서상 띄어쓴 쪽이 먼저 등록돼 tier 0로 잡히지만, 데이터 순서가 바뀌면 tier 2로
# 내려갈 수 있다. 어느 쪽이든 매칭은 된다는 것을 여기서 고정한다(사용자 영향 없음).
def test_표기가_중복된_이름도_매칭된다():
    from app.models import Floor, Store

    floor = Floor(id="F1", building_id="B", name="1F", level=1)
    store = Store(
        id="s1",
        floor_id="F1",
        name="물품 보관함",
        centroid_x_m=0.0,
        centroid_y_m=0.0,
        entrance_node_id="N-1",
    )
    scored = query_search._rank([(store, floor)], "물품 보관함이 어디야")
    assert scored and scored[0][3].id == "s1"
