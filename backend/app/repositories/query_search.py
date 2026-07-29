# 자연어 질의 매칭.
# 매장 이름·카테고리·동의어를 텍스트로 매칭해 최적 1건을 고른다(경량, 임베딩 없음).
# 질의는 꼬리 제거 + 형태소 정규화(query_morph)를 거쳐 조사·어미가 붙어도 매칭된다.
# - match_destination:    최적 매장 1건 + 입구 노드(온디바이스 경로용).
# - match_info:           최적 1건 + 대상이 존재하는 층 목록.
# - match_ai_destination: 하이브리드 — 1차 경량 확정, 미스·모호한 부분 일치는 2차 의미 검색.
# Building이 없으면 None(→ Router가 404). 매칭 0건은 status="no_match"로 정상 응답.
# floor_name은 여기서 Floor를 조인해 얻는다(공유 _to_store_dict는 건드리지 않음).

from __future__ import annotations

import json
from functools import lru_cache
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import API_ROOT
from app.geo.georeference import GeoTransform
from app.models import Building, Floor, Store
from app.repositories import query_morph
from app.repositories.geo_transform import fit_building_geo_transform

_SYNONYMS_PATH = API_ROOT / "resources" / "query_synonyms.json"
MAX_QUERY_LENGTH = 200

# 질의 꼬리(조사·의문형) — 정규화 때 최대 1개 제거. 긴 것부터 검사한다.
_TAILS = tuple(
    sorted(("몇 층이야", "몇층이야", "몇 층", "몇층", "어디야", "어디", "위치", "알려줘"),
           key=len, reverse=True)
)

# 문장 끝에서 후보로 벗겨 볼 구두점. 원문 후보도 항상 남기므로 "A.P.C."처럼
# 구두점이 실제 이름 일부인 매장은 정확 일치가 우선한다. 내부 구두점("We,pet")은 건드리지 않는다.
_SENTENCE_PUNCTUATION = frozenset("?!.,，。！？…")


def _norm(text: str) -> str:
    return text.strip().lower()


@lru_cache(maxsize=1)
def _synonyms() -> dict[str, str]:
    # 별칭 → 표준어 사전. 파일이 없어도 빈 사전으로 동작한다(장애 없이 매칭만 약해짐).
    try:
        raw = json.loads(_SYNONYMS_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    return {_norm(k): _norm(v) for k, v in raw.items()}


# 정규화. 꼬리 제거 → 형태소 정규화.
# 꼬리 제거를 먼저 하는 이유: "몇 층이야"의 "층"은 Kiwi가 일반명사(NNG)로 보기 때문에
# 형태소만으로는 "화장실 몇 층이야" → "화장실 층"이 되어 이름 일치가 깨진다.
# 형태소는 그다음 남은 조사·어미를 뗀다("화장실이" → "화장실"). Kiwi가 없으면 꼬리 제거
# 결과만 쓴다.
def _normalize_variant(text: str) -> str:
    t = _strip_tail(text)
    return query_morph.normalize(t) or t


def _query_candidates(text: str) -> tuple[str, ...]:
    """원문과 문장 끝 구두점을 한 글자씩 벗긴 정규화 후보를 만든다.

    원문 후보를 먼저 둬서 "A.P.C." 같은 실제 상호를 보존하고, 뒤 후보로
    "화장실이 어디야?" 같은 문장부호 입력을 받는다. 빈 후보는 category가 null인
    임의 매장과 일치할 수 있으므로 제외한다.
    """
    current = _norm(text)
    if len(current) > MAX_QUERY_LENGTH:
        return ()

    variants = [current]
    while current and current[-1] in _SENTENCE_PUNCTUATION:
        current = current[:-1].rstrip()
        variants.append(current)

    candidates: list[str] = []
    for variant in variants:
        normalized = _normalize_variant(variant)
        if normalized and normalized not in candidates:
            candidates.append(normalized)
    return tuple(candidates)


def _normalize_query(text: str) -> str:
    """단일 정규화 결과가 필요한 검사 호환용. 매칭은 모든 후보를 직접 평가한다."""
    candidates = _query_candidates(text)
    return candidates[-1] if candidates else ""


def _strip_tail(t: str) -> str:
    for tail in _TAILS:
        if t.endswith(tail):
            return t[: -len(tail)].strip()
    return t


# tier 2(이름 부분 일치) 안의 정밀도. 낮을수록 우선.
# 사용자는 이름 앞에서부터 친다 — "레이어드"는 "카페 레이어드"를 찾는 것이지 다른 이름의
# 중간 어딘가를 찾는 게 아니다. 이 순위가 없으면 둘 다 같은 tier 2라 층·ID순으로 갈려,
# 몇 글자를 친 순간 엉뚱한 시설이 먼저 뜬다(KIWI.md 9절이 예고한 한 글자 과매칭).
_NAME_PREFIX = 0   # 이름이 질의로 시작 — "이솝화" → "이솝 화장품"(2글자부터, 아래 참고)
_WORD_PREFIX = 1   # 이름 속 단어가 질의로 시작 — "레이어드" → "카페 레이어드"
_CONTAINS = 2      # 그 밖의 중간 포함 — "이솝" → "엘리베이터솝"(가상의 예)

# tier 2(이름 부분 일치)에 들어가려면 질의가 최소 2글자여야 한다. query_morph.normalize가
# 형태소 분해로 오타·조사를 지우면서 질의가 1글자로 축소되는 경우가 있다("샤낼"→"샤",
# "물 사고싶어"→"물"). 그 1글자가 무관한 매장 이름 접두와 우연히 맞아 오탐이 난다.
# tier 0(정확 이름 일치)·tier 1(카테고리 일치)은 이 하한의 영향을 받지 않는다 — "송"·"온"
# 같은 한 글자 매장명은 정확 일치로 계속 잡혀야 한다.
_MIN_NAME_PARTIAL_MATCH_LEN = 2


def _name_match_rank(name: str, q: str) -> int | None:
    if not q or len(q) < _MIN_NAME_PARTIAL_MATCH_LEN or q not in name:
        return None
    if name.startswith(q):
        return _NAME_PREFIX
    if any(token.startswith(q) for token in name.split()):
        return _WORD_PREFIX
    return _CONTAINS


# 매칭 우선순위 (tier, tier 2 정밀도). 낮을수록 우선. 안 걸리면 None.
def _tier(store: Store, q: str, canon: str) -> tuple[int, int] | None:
    name = _norm(store.name or "")
    cat = _norm(store.category or "")
    sub = _norm(store.subcategory or "")
    if name in (q, canon):
        return 0, 0  # 정확 이름 일치
    if q in (cat, sub) or canon in (cat, sub):
        return 1, 0  # 카테고리/서브카테고리 일치
    # 질의 원문과 동의어 표준형 중 더 정밀하게 걸린 쪽을 쓴다.
    ranks = [
        rank
        for rank in (_name_match_rank(name, q), _name_match_rank(name, canon))
        if rank is not None
    ]
    if ranks:
        return 2, min(ranks)  # 이름 부분 일치
    return None


# (tier, 구두점 후보 순서, tier 2 정밀도, floor.level, store.id) 오름차순 정렬 — 결정적.
# 정밀도를 후보 순서 뒤에 두는 이유: 후보 순서는 "원문에 가까운 정규화"를 뜻하고,
# 정밀도는 그 후보가 이름 어디에 걸렸는지를 뜻한다. 원문 우선을 먼저 지킨 뒤
# 같은 후보 안에서 접두를 앞세워야 "A.P.C." 같은 기존 동작이 그대로 남는다.
def _rank_with_candidate(
    rows: list[tuple[Store, Floor]],
    text: str,
) -> list[tuple[int, int, int, int, str, Store, Floor]]:
    # 매장명을 형태소 사전에 먼저 등록한다 — 안 하면 미등록 브랜드명이 조사로 오해돼
    # 잘려 나간다("리모와" → "리모"). 이미 등록된 단어는 건너뛰므로 두 번째 요청부터는 사실상 무료.
    query_morph.register_words(store.name for store, _floor in rows)

    candidates = _query_candidates(text)
    synonyms = _synonyms()

    # 걸리는 매장마다 최선의 (tier, 후보 순서, 정밀도)를 고른다. tier가 같으면 원문에
    # 가까운 후보가 먼저라 "A.P.C."가 "A.P.C 골프"의 부분 일치보다 우선한다.
    scored_with_candidate = []
    for store, floor in rows:
        best: tuple[int, int, int] | None = None
        for candidate_order, q in enumerate(candidates):
            canon = synonyms.get(q, q)
            matched = _tier(store, q, canon)
            if matched is None:
                continue
            tier, precision = matched
            key = (tier, candidate_order, precision)
            if best is None or key < best:
                best = key
        if best is not None:
            tier, candidate_order, precision = best
            scored_with_candidate.append(
                (tier, candidate_order, precision, floor.level, store.id, store, floor)
            )

    scored_with_candidate.sort(key=lambda row: (row[0], row[1], row[2], row[3], row[4]))
    return scored_with_candidate


def _rank(
    rows: list[tuple[Store, Floor]],
    text: str,
) -> list[tuple[int, int, str, Store, Floor]]:
    """외부 매칭용 순위. 내부 후보 순서·정밀도는 정렬에만 쓰고 반환에서는 감춘다."""
    return [
        (tier, level, store_id, store, floor)
        for (
            tier,
            _candidate_order,
            _precision,
            level,
            store_id,
            store,
            floor,
        ) in _rank_with_candidate(rows, text)
    ]


def _is_confident_light_match(
    scored: list[tuple[int, int, int, int, str, Store, Floor]],
) -> bool:
    """AI 경로에서 경량 결과를 바로 확정해도 되는지 판단한다.

    tier 0(정확 이름)·tier 1(카테고리·소분류 정확 일치)·tier 2(이름 부분 일치) 모두
    같은 기준으로 판단한다 — 최상위 (tier, 후보 순서, 정밀도) 그룹 안에서 서로 다른
    매장명이 하나일 때만 확정한다. 같은 시설이 여러 층에 있는 경우는 이름이 같으므로
    하나의 대상으로 본다.

    tier 0은 정의상(질의 원문과 이름이 정확히 같음) 그룹 안 이름이 항상 하나뿐이라
    이 통합으로 기존 동작(무조건 확정)이 그대로 유지된다. tier 1은 "명품"(43건)·
    "레스토랑"(65건)처럼 서로 다른 매장 이름이 여럿이면 확정하지 않고 2차 의미 검색으로
    넘긴다(docs/backend/native/conversational-discovery.md 7-2절).

    같은 tier 2라도 정밀도가 다르면 다른 그룹으로 본다 — "이"의 접두 일치("이솝")가
    유일하면, 중간 포함이 수십 건 있어도 그 하나로 확정한다.
    """
    if not scored:
        return False
    best_group = scored[0][:3]  # (tier, 후보 순서, 정밀도)
    best_names = {
        _norm(store.name or "")
        for tier, order, precision, _level, _store_id, store, _floor in scored
        if (tier, order, precision) == best_group
    }
    return len(best_names) == 1


def _floor_names_for_match(
    scored: list[tuple[int, int, str, Store, Floor]],
    selected_name: str,
) -> list[str]:
    """대표 매장과 이름이 같은 후보가 존재하는 층만 level 순으로 돌려준다."""
    normalized_name = _norm(selected_name)
    by_level: dict[str, int] = {}
    for _, level, _store_id, store, floor in scored:
        if _norm(store.name or "") == normalized_name:
            by_level.setdefault(floor.name, level)
    return [name for name, _ in sorted(by_level.items(), key=lambda item: item[1])]


def _to_match(
    store: Store,
    floor: Floor,
    transform: GeoTransform | None,
) -> dict[str, Any]:
    # wgs84는 지도 표시용. 건물에 실좌표 앵커가 없으면 transform이 없어 null이 된다.
    centroid_wgs84 = None
    if transform is not None:
        lat, lng = transform.apply(store.centroid_x_m, store.centroid_y_m)
        centroid_wgs84 = {"lat": lat, "lng": lng}

    return {
        "store_id": store.id,
        "name": store.name,
        "category": store.category,
        "subcategory": store.subcategory,
        "floor_id": store.floor_id,
        "floor_name": floor.name,
        "entrance_node_id": store.entrance_node_id,
        "centroid_local_m": {"x": store.centroid_x_m, "y": store.centroid_y_m},
        "centroid_wgs84": centroid_wgs84,
    }


# 입구 노드가 없으면 클라이언트가 경로를 못 만든다 — ok와 구분해 알린다.
def _status(store: Store) -> str:
    return "ok" if store.entrance_node_id else "ok_no_route"


# current_floor_id는 층 라벨("B2")과 내부 id("FL-...")를 모두 받는다. 클라이언트는
# 사용자가 보는 라벨만 들고 있고, building_id로 스코프가 잡혀 있어 uq_floors_building_name이
# 건물 안에서 라벨의 유일성을 보장한다. id도 받는 건 기존 호출부 호환용.
def _load_stores(
    session: Session,
    building_id: str,
    *,
    current_floor_id: str | None = None,
) -> list[tuple[Store, Floor]]:
    statement = (
        select(Store, Floor)
        .join(Floor, Store.floor_id == Floor.id)
        .where(Floor.building_id == building_id)
    )

    if current_floor_id is not None:
        statement = statement.where(
            (Floor.name == current_floor_id) | (Floor.id == current_floor_id)
        )
    return session.execute(statement).all()


# 목적지 질의. Building 없으면 None(→404). 매칭 최적 1건을 입구 노드와 함께 반환.
def match_destination(
    session: Session,
    building_id: str,
    text: str,
    *,
    current_floor_id: str | None = None,
) -> dict[str, Any] | None:
    if session.get(Building, building_id) is None:
        return None

    scored = _rank(
        _load_stores(session, building_id, current_floor_id=current_floor_id),
        text,
    )
    if not scored:
        return {"status": "no_match", "query": text, "match": None}

    # 정렬이 결정적이라 [0]이 곧 최적 1건.
    _, _, _, store, floor = scored[0]
    transform = fit_building_geo_transform(session, building_id)

    return {"status": _status(store), "query": text, "match": _to_match(store, floor, transform)}


# AI 자연어 질의(하이브리드) — 단일 목적지 1건 계약.
# **/query/ai는 더 이상 이 함수를 쓰지 않는다**(Wave 6에서 discover()의 탐색 계약으로
# 전환). 남겨 둔 이유는 "질의 하나 → 최적 1건"이 그대로 필요한 곳이 있기 때문이다:
# scripts/evaluate_query_hybrid.py의 기준선 측정(23/29)과 의미 검색 스모크 테스트.
# 1차 경량 확정 → 미스·모호한 부분 일치 시 2차 의미 검색.
# 검색 범위가 단계별로 다르다: 1차는 현재 층 한정(가까운 시설 우선), 2차는 건물 전체
# (사용자가 층을 모르는 자연어 질의). destination과 같은 응답 계약(status/query/match)을 쓴다.
# 설계: docs/backend/native/FAISS.md
def match_ai_destination(
    session: Session,
    building_id: str,
    text: str,
    *,
    current_floor_id: str | None = None,
) -> dict[str, Any] | None:
    if session.get(Building, building_id) is None:
        return None

    # 1차: 정확 이름·동의어와 단일 대상 부분 일치. 서로 다른 이름이 여럿 걸린 부분
    # 일치는 ID순으로 임의 확정하지 않고 2차가 의미로 판별하게 한다.
    scored = _rank_with_candidate(
        _load_stores(session, building_id, current_floor_id=current_floor_id),
        text,
    )
    if _is_confident_light_match(scored):
        *_, store, floor = scored[0]
        transform = fit_building_geo_transform(session, building_id)
        return {"status": _status(store), "query": text, "match": _to_match(store, floor, transform)}

    # 2차: 경량이 놓쳤거나 모호한 자연어를 임베딩 의미 검색으로.
    # import는 여기서 지연 — AI 경로가 2차를 쓸 때만 torch를 로드한다.
    #
    # current_floor_id를 넘기지 않는다 — 2차는 건물 전체를 본다.
    # 1차(현재 층 한정)가 이미 실패한 뒤라 층을 또 좁히면 남는 게 없다. 실제로 1F에서
    # "밥집"은 1F에 식당이 0개라 무조건 no_match였다. 현재 층 시설("화장실")은 1차가
    # 층 스코프로 잡아 확정하므로, 층 우선순위는 여기서가 아니라 1차에서 지켜진다.
    from app.repositories import query_semantic

    hit = query_semantic.semantic_search(session, building_id, text)
    if hit is None:
        return {"status": "no_match", "query": text, "match": None}

    _score, store, floor = hit
    transform = fit_building_geo_transform(session, building_id)

    return {"status": _status(store), "query": text, "match": _to_match(store, floor, transform)}


# --------------------------------------------------------------------------
# 탐색(Discovery) — POST /query/ai
# 설계: docs/backend/native/conversational-discovery.md 7·8절.
# 단일 목적지(match_destination)와 달리 "여러 후보 + 되물음"을 만든다.
# --------------------------------------------------------------------------

MAX_DISCOVERY_MATCHES = 5      # 최종 추천 상한(12절 확정)
CLARIFY_PREVIEW_MATCHES = 3    # 질문과 함께 보여줄 초기 후보 수(12절 확정)

# 되물을 축의 우선순위. 한 번에 한 축만 묻는다(2절). 앞에 있는 축부터 구분력을 본다.
_QUESTION_AXIS_ORDER = ("intents", "cuisines", "styles", "menus", "occasions", "audiences")

# 7-3절 질문 템플릿. 문장을 생성하지 않고 축별로 고정한다.
_QUESTION_TEMPLATES = {
    "intents": "무엇을 찾으세요?",
    "cuisines": "어떤 종류가 좋으세요?",
    "styles": "어떤 스타일을 찾으세요?",
    "menus": "무엇을 드시고 싶으세요?",
    "occasions": "어떤 상황에 맞는 곳을 찾으세요?",
    "audiences": "누구를 위한 곳인가요?",
}

# 추천 이유 템플릿. 검증된 태그(matched_facets)에서만 조립한다 — 이름·카테고리로
# 음식 종류나 취급 품목을 추측하지 않는다(2절 실패 조건).
_REASON_TEMPLATES = {
    "intents": "{values} 관련 매장이에요.",
    "cuisines": "{values} 음식점이에요.",
    "styles": "{values} 스타일 매장이에요.",
    "menus": "{values} 메뉴가 있어요.",
    "occasions": "{values}에 어울려요.",
    "audiences": "{values}를 위한 곳이에요.",
}


def _facets(store: Store) -> dict[str, list[str]]:
    """Store.search_facets를 방어적으로 읽는다. 미태깅 매장이 대다수라 빈 dict가 정상."""
    raw = store.search_facets
    if not isinstance(raw, dict):
        return {}
    return {
        axis: [value for value in values if isinstance(value, str)]
        for axis, values in raw.items()
        if isinstance(values, list) and values
    }


def _matches_selection(store: Store, selection: dict[str, list[str]]) -> bool:
    """축 사이는 AND, 축 안의 값들은 OR. 태그가 없는 매장은 선택된 축에서 탈락한다."""
    facets = _facets(store)
    for axis, wanted in selection.items():
        if not set(facets.get(axis, ())) & set(wanted):
            return False
    return True


def _facet_options(
    candidates: list[tuple[Store, Floor]],
    axis: str,
) -> list[dict[str, Any]]:
    """축의 값별 후보 수. 실제 후보가 있는 값만 만든다(빈 chip 금지, 4-3절)."""
    counts: dict[str, int] = {}
    for store, _floor in candidates:
        for value in _facets(store).get(axis, ()):
            counts[value] = counts.get(value, 0) + 1
    return [
        {"facet": axis, "value": value, "label": value, "count": count}
        for value, count in sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    ]


def _pick_question(
    candidates: list[tuple[Store, Floor]],
) -> tuple[str | None, list[dict[str, Any]]]:
    """현재 후보를 실제로 둘 이상으로 나누는 축을 고른다. 없으면 (None, []).

    두 가지를 모두 만족해야 질문이 된다(7-3절 "현재 후보를 실제로 나누지 못하는
    facet은 질문으로 선택하지 않는다").

    1. 서로 다른 값이 둘 이상 — "명품" 질의의 후보 43건은 전부 styles=["명품"]이라
       스타일을 다시 물어도 후보가 그대로다.
    2. 그 축을 가진 후보가 절반 이상 — 태깅이 아직 얇은 지금 데이터에서는, 상위 10건 중
       2건만 태그가 있어도 "값이 2개"라는 조건은 통과해 버린다. 그 질문에 답하면
       태그 없는 8건이 통째로 사라진다(2절 "미표기 매장이 통째로 사라진다").
    """
    for axis in _QUESTION_AXIS_ORDER:
        options = _facet_options(candidates, axis)
        if len(options) < 2:
            continue
        covered = sum(1 for store, _floor in candidates if _facets(store).get(axis))
        if covered * 2 >= len(candidates):
            return axis, options
    return None, []


def _matched_facets(
    store: Store,
    basis: dict[str, list[str]],
) -> dict[str, list[str]]:
    """이번 질문·선택(basis)과 실제로 겹친 태그만 남긴다. 원본 facet 전체를 내보내지 않는다."""
    facets = _facets(store)
    matched: dict[str, list[str]] = {}
    for axis, wanted in basis.items():
        allowed = set(wanted)
        hit = [value for value in facets.get(axis, ()) if value in allowed]
        if hit:
            matched[axis] = hit
    return matched


def _reason(matched: dict[str, list[str]]) -> str | None:
    """검증된 태그에서만 문장을 조립한다. 태그가 없으면 이유를 생략한다(2절)."""
    parts = [
        _REASON_TEMPLATES[axis].format(values="·".join(matched[axis]))
        for axis in _QUESTION_AXIS_ORDER
        if matched.get(axis) and axis in _REASON_TEMPLATES
    ]
    return " ".join(parts) or None


def _is_current_floor(floor: Floor, current_floor_id: str | None) -> bool:
    return current_floor_id is not None and current_floor_id in (floor.name, floor.id)


def _dedupe_by_name(
    rows: list[tuple[Store, Floor]],
    current_floor_id: str | None,
) -> list[tuple[Store, Floor]]:
    """같은 이름은 한 건만 남긴다 — 다양성 보정의 1순위(1-6절).

    코퍼스의 67%가 편의시설이고 엘리베이터·에스컬레이터는 12개 층에 같은 이름으로
    존재한다. 이름 축을 빼면 상위 N이 같은 시설의 층 목록으로 채워진다.

    대표로 남길 층은 관련도 1순위를 쓰되, 같은 이름이 현재 층에도 있으면 그쪽을
    고른다 — `current_floor_id`를 후보 제거가 아니라 정렬 보조로 쓰는 지점이다(8-2절 A안).
    """
    order: list[str] = []
    picked: dict[str, tuple[Store, Floor]] = {}
    for store, floor in rows:
        key = _norm(store.name or "") or store.id
        if key not in picked:
            picked[key] = (store, floor)
            order.append(key)
        elif _is_current_floor(floor, current_floor_id) and not _is_current_floor(
            picked[key][1], current_floor_id
        ):
            picked[key] = (store, floor)
    return [picked[key] for key in order]


def _diversify(
    rows: list[tuple[Store, Floor]],
    limit: int,
    *,
    axis: str | None = None,
) -> list[tuple[Store, Floor]]:
    """같은 소분류·같은 층 쏠림을 라운드로빈으로 완화한다(7-2절 7단계).

    이름 중복 제거(_dedupe_by_name)를 먼저 거친 목록을 받는다. 버킷 순서는 관련도
    순서(각 버킷의 첫 등장 순)를 그대로 따르므로, 1순위 후보는 항상 1순위로 남는다.

    `axis`를 주면 소분류 대신 그 축의 값으로 버킷을 나눈다. clarify의 초기 후보를
    "서로 다른 성격"으로 보여주기 위해서다(4-2절) — 스타일을 되묻는 화면의 미리보기가
    전부 같은 스타일이면 질문의 근거가 보이지 않는다.
    """
    buckets: dict[tuple[str, str], list[tuple[Store, Floor]]] = {}
    for store, floor in rows:
        if axis is None:
            group = _norm(store.subcategory or "")
        else:
            values = _facets(store).get(axis, ())
            group = values[0] if values else ""
        buckets.setdefault((group, floor.name), []).append((store, floor))

    picked: list[tuple[Store, Floor]] = []
    while len(picked) < limit:
        progressed = False
        for bucket in buckets.values():
            if not bucket:
                continue
            picked.append(bucket.pop(0))
            progressed = True
            if len(picked) >= limit:
                break
        if not progressed:
            break
    return picked


def _to_discovery_match(
    store: Store,
    floor: Floor,
    transform: GeoTransform | None,
    basis: dict[str, list[str]],
) -> dict[str, Any]:
    matched = _matched_facets(store, basis) if basis else {}
    return {**_to_match(store, floor, transform), "matched_facets": matched, "reason": _reason(matched)}


def _discovery_matches(
    candidates: list[tuple[Store, Floor]],
    limit: int,
    basis: dict[str, list[str]],
    transform: GeoTransform | None,
    axis: str | None = None,
) -> list[dict[str, Any]]:
    return [
        _to_discovery_match(store, floor, transform, basis)
        for store, floor in _diversify(candidates, limit, axis=axis)
    ]


def _discovery(
    text: str,
    mode: str,
    *,
    question: str | None = None,
    options: list[dict[str, Any]] | None = None,
    matches: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    return {
        "mode": mode,
        "query": text,
        "question": question,
        "options": options or [],
        "matches": matches or [],
    }


def discover(
    session: Session,
    building_id: str,
    text: str,
    *,
    current_floor_id: str | None = None,
    selected_facets: dict[str, list[str]] | None = None,
    show_all: bool = False,
) -> dict[str, Any] | None:
    """탐색 질의. 명확하면 바로 안내하고, 넓으면 되묻거나 여러 후보를 추천한다.

    stateless다 — 서버 세션이 없고, 클라이언트가 매 요청에 원문과 현재 선택을 다시 보낸다.

    판정 순서(7-2절):
      1. 경량 1차가 단일 대상으로 확정되면 `direct`. 선택(facet)이 이미 있으면 건너뛴다.
      2. 확정 실패면 후보 집합을 만든다. 경량 후보가 있으면 그것을, 없으면 2차 의미 검색 상위 N을.
      3. `selected_facets`로 좁힌다. 좁힌 결과가 0건이면 선택을 해제하고 전체 후보 판정으로
         되돌아간다(→ 대개 clarify로 복귀) — 막다른 흐름을 만들지 않기 위해서다
         (2절 "결과가 없는데 계속 세분화 질문"). option은 항상 실제 후보가 있는 값만
         만들므로, 이 되돌림은 화면에 없던 축을 클라이언트가 보냈을 때만 일어난다.
      4. 이름 중복 제거 → 후보가 넓고 구분력 있는 축이 있으면 `clarify`, 아니면 `results`.
         `show_all=True`이면 후보·선택 계산은 그대로 두고 clarify만 건너뛰어 `results`를 준다.

    `current_floor_id`는 8-2절 A안이다. 1차 경량(tier 0·1 시설 질의)은 층 스코프를 유지해
    "화장실"이 현재 층에서 확정되게 하고, 탐색 후보 집합은 건물 전체를 보되 같은 이름이
    현재 층에도 있으면 그 층을 대표로 고르는 정렬 보조로만 쓴다.
    """
    if session.get(Building, building_id) is None:
        return None

    selection = {
        axis: list(values)
        for axis, values in (selected_facets or {}).items()
        if values
    }
    transform = fit_building_geo_transform(session, building_id)

    building_rows = _load_stores(session, building_id)
    building_scored = _rank_with_candidate(building_rows, text)

    if not selection:
        # 층 스코프 1차가 우선 — 현재 층에 있는 시설을 그 층에서 확정한다.
        floor_scoped = (
            _rank_with_candidate(
                _load_stores(session, building_id, current_floor_id=current_floor_id),
                text,
            )
            if current_floor_id is not None
            else building_scored
        )
        for scored in (floor_scoped, building_scored):
            if _is_confident_light_match(scored):
                *_, store, floor = scored[0]
                return _discovery(
                    text,
                    "direct",
                    matches=[_to_discovery_match(store, floor, transform, {})],
                )

    # 탐색 후보 집합. 경량이 잡은 게 있으면(카테고리·소분류 정확 일치 등) 그것이
    # 의미 검색보다 정밀하므로 먼저 쓴다.
    pool = [(store, floor) for *_rank, store, floor in building_scored]

    degraded = False
    if not pool:
        # import는 여기서 지연 — 2차를 실제로 쓸 때만 torch를 로드한다.
        from app.repositories import query_semantic

        results = query_semantic.search_many(session, building_id, text)
        degraded = results.is_degraded
        pool = [(store, floor) for _score, store, floor in results.hits]

    if selection:
        narrowed = [row for row in pool if _matches_selection(row[0], selection)]
        if narrowed:
            pool = narrowed
        else:
            selection = {}  # 선택을 해제하고 전체 후보를 보여준다(막다른 흐름 방지)

    candidates = _dedupe_by_name(pool, current_floor_id)

    if not candidates:
        return _discovery(text, "degraded" if degraded else "no_match")

    if degraded:
        # 의미 검색 기능 자체를 못 쓰는 상태. 경량·태그로 얻은 결과라도 담아 준다(8-3절).
        # 지금 구조에서는 경량 후보가 하나라도 있으면 2차를 아예 부르지 않으므로
        # (degraded 판정 자체가 서지 않는다) 이 가지의 matches는 사실상 비어 있다.
        # 계약을 맞춰 두는 이유는 나중에 경량 후보를 2차로 넓히게 되면 이 자리가
        # 그대로 "경량 결과 + 제한 안내"가 되기 때문이다.
        return _discovery(
            text,
            "degraded",
            matches=_discovery_matches(candidates, MAX_DISCOVERY_MATCHES, {}, transform),
        )

    if selection or show_all:
        return _discovery(
            text,
            "results",
            matches=_discovery_matches(
                candidates, MAX_DISCOVERY_MATCHES, selection, transform
            ),
        )

    if len(candidates) > MAX_DISCOVERY_MATCHES:
        axis, options = _pick_question(candidates)
        if axis is not None:
            basis = {axis: [option["value"] for option in options]}
            # 초기 후보는 그 축의 태그가 있는 매장에서 고른다 — 미태깅 매장이 섞이면
            # 질문의 근거(reason)가 비어 보인다. 태그된 후보가 없으면 전체에서 고른다.
            preview = [row for row in candidates if _facets(row[0]).get(axis)]
            return _discovery(
                text,
                "clarify",
                question=_QUESTION_TEMPLATES[axis],
                options=options,
                matches=_discovery_matches(
                    preview or candidates,
                    CLARIFY_PREVIEW_MATCHES,
                    basis,
                    transform,
                    axis=axis,
                ),
            )

    # 구분력 있는 축이 없으면 억지로 되묻지 않는다 — 다양성 보정된 상위 N을 그대로 준다.
    return _discovery(
        text,
        "results",
        matches=_discovery_matches(candidates, MAX_DISCOVERY_MATCHES, {}, transform),
    )


# 정보 질의. 최적 1건 + 대상이 존재하는 층 목록(level 오름차순)을 반환.
def match_info(
    session: Session,
    building_id: str,
    text: str,
    *,
    current_floor_id: str | None = None,
) -> dict[str, Any] | None:
    if session.get(Building, building_id) is None:
        return None

    scored = _rank(
        _load_stores(session, building_id, current_floor_id=current_floor_id),
        text,
    )
    if not scored:
        return {"status": "no_match", "query": text, "match": None, "floors": []}

    _, _, _, store, floor = scored[0]
    transform = fit_building_geo_transform(session, building_id)

    # 같은 이름이 여러 층에 있으면 그 이름의 층만 모은다. 낮은 tier의 다른 부분
    # 일치 매장까지 섞으면 "A.P.C." 응답에 "A.P.C 골프" 층이 붙을 수 있다.
    floors = _floor_names_for_match(scored, store.name or "")

    return {
        "status": "ok",
        "query": text,
        "match": _to_match(store, floor, transform),
        "floors": floors,
    }
