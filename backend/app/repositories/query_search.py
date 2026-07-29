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
# 사용자는 이름 앞에서부터 친다 — "이"는 "이솝"을 찾는 것이지 "엘리베이터"의 세 번째
# 글자를 찾는 게 아니다. 이 순위가 없으면 둘 다 같은 tier 2라 층·ID순으로 갈려,
# 한두 글자를 친 순간 엉뚱한 시설이 먼저 뜬다(KIWI.md 9절이 예고한 한 글자 과매칭).
_NAME_PREFIX = 0   # 이름이 질의로 시작 — "이" → "이솝"
_WORD_PREFIX = 1   # 이름 속 단어가 질의로 시작 — "레이어드" → "카페 레이어드"
_CONTAINS = 2      # 그 밖의 중간 포함 — "이" → "엘리베이터"


def _name_match_rank(name: str, q: str) -> int | None:
    if not q or q not in name:
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

    정확 이름·카테고리는 기존처럼 확정한다. 이름 부분 일치(tier 2)는 최상위 후보가
    같은 매장명 하나일 때만 확정해, 여러 브랜드 중 ID순 첫 매장을 고르는 일을 막는다.
    같은 시설이 여러 층에 있는 경우는 이름이 같으므로 하나의 대상으로 본다.

    같은 tier 2라도 정밀도가 다르면 다른 그룹으로 본다 — "이"의 접두 일치("이솝")가
    유일하면, 중간 포함이 수십 건 있어도 그 하나로 확정한다.
    """
    if not scored:
        return False
    best_tier = scored[0][0]
    if best_tier < 2:
        return True
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


# AI 자연어 질의(하이브리드). 1차 경량 확정 → 미스·모호한 부분 일치 시 2차 의미 검색.
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
