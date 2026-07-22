# 자연어 질의 경량 매칭.
# 매장 이름·카테고리·동의어를 텍스트로 매칭해 최적 1건을 고른다. 임베딩/RAG 없음.
# - match_destination: 최적 매장 1건 + 입구 노드(온디바이스 경로용).
# - match_info:        최적 1건 + 대상이 존재하는 층 목록.
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
from app.repositories.geo_transform import fit_building_geo_transform

_SYNONYMS_PATH = API_ROOT / "resources" / "query_synonyms.json"

# 질의 꼬리(조사·의문형) — 정규화 때 최대 1개 제거. 긴 것부터 검사한다.
_TAILS = tuple(
    sorted(("몇 층이야", "몇층이야", "몇 층", "몇층", "어디야", "어디", "위치", "알려줘"),
           key=len, reverse=True)
)


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


def _normalize_query(text: str) -> str:
    t = _norm(text)
    for tail in _TAILS:
        if t.endswith(tail):
            return t[: -len(tail)].strip()
    return t


# 매칭 우선순위 tier. 낮을수록 우선. 안 걸리면 None.
def _tier(store: Store, q: str, canon: str) -> int | None:
    name = _norm(store.name or "")
    cat = _norm(store.category or "")
    sub = _norm(store.subcategory or "")
    if name in (q, canon):
        return 0  # 정확 이름 일치
    if q in (cat, sub) or canon in (cat, sub):
        return 1  # 카테고리/서브카테고리 일치
    if (q and q in name) or (canon and canon in name):
        return 2  # 이름 부분 일치
    return None


# (tier, floor.level, store.id) 오름차순 정렬 — 결정적. 동점도 항상 같은 1건이 뽑힌다.
def _rank(
    rows: list[tuple[Store, Floor]],
    text: str,
) -> list[tuple[int, int, str, Store, Floor]]:
    q = _normalize_query(text)
    canon = _synonyms().get(q, q)  # 동의어가 있으면 표준어로, 없으면 그대로.
    scored = []
    for store, floor in rows:
        tier = _tier(store, q, canon)
        if tier is not None:
            scored.append((tier, floor.level, store.id, store, floor))
    scored.sort(key=lambda row: (row[0], row[1], row[2]))
    return scored


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
        statement = statement.where(Floor.id == current_floor_id)
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
    _, _, _, store, floor = scored[0]
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
    by_level: dict[str, int] = {}
    for _, level, _sid, _store, matched_floor in scored:
        by_level.setdefault(matched_floor.name, level)
    floors = [name for name, _ in sorted(by_level.items(), key=lambda kv: kv[1])]
    return {
        "status": "ok",
        "query": text,
        "match": _to_match(store, floor, transform),
        "floors": floors,
    }
