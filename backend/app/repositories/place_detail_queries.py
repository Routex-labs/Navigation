# 매장·시설 상세 조회 Query 함수.
# - Session을 첫 인자로 받고 API 응답과 동일한 dict를 조립한다.
# - None은 존재하지 않는 Building/Store를 뜻하고, HTTP 상태 변환은 Router가 한다.
# - 표시용 값은 DB에 없다. 코어는 Store/Floor에서, 나머지는 오버레이에서 온다.

from __future__ import annotations

from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.models import Building, Store
from app.repositories import place_details

# 상세 시트를 열지 않는 소분류. 주차구역 787 + 에스컬레이터 152 + 엘리베이터 68 =
# 1,007건으로 전체 1,640건의 61%다. 이들은 "설명"이라는 개념이 성립하지 않는다.
# 404로 만들지 않는 이유: 존재하지 않는 것과 상세가 없는 것은 다르고, 클라이언트가
# kind를 보고 시트를 열지 말지 결정하는 편이 id 규칙을 클라이언트에 심는 것보다 낫다.
_EXCLUDED_SUBCATEGORIES = {"주차", "에스컬레이터", "엘리베이터"}

# 사람이 설명을 쓰지 않고 위치 안내만 파생하는 시설. 화장실·락커·교통·생활편의
# 92건이 여기 해당한다.
_FACILITY_SUBCATEGORIES = {"화장실", "생활편의", "교통", "락커"}


# 매장/시설 상세. 건물·매장이 없으면 None.
def get_place_detail(
    session: Session,
    building_id: str,
    place_id: str,
) -> dict[str, Any] | None:
    if session.get(Building, building_id) is None:
        return None

    store = session.scalars(select(Store).where(Store.id == place_id).options(selectinload(Store.floor))).one_or_none()
    # 다른 건물의 매장 id로 조회하면 존재하지 않는 것으로 취급한다 — 건물별
    # URL인데 남의 건물 매장이 열리면 층 라벨·길찾기가 전부 어긋난다.
    if store is None or store.floor is None or store.floor.building_id != building_id:
        return None

    overlay = place_details.load_overlays().get(place_id, {})
    kind = _classify(store)

    return {
        "kind": kind,
        "id": store.id,
        "name": store.name,
        "subtitle": _subtitle(store),
        "category": store.category,
        "subcategory": store.subcategory,
        "location": {
            "building_id": building_id,
            "floor_label": store.floor.name,
            "position_local_m": {"x": store.centroid_x_m, "y": store.centroid_y_m},
            "entrance_node_id": store.entrance_node_id,
        },
        "actions": _actions(store, kind),
        "sections": _sections(store, kind, overlay),
        "provenance": {
            "source": "manual" if overlay else "studio",
            "updated_at": overlay.get("updated_at"),
        },
    }


def _classify(store: Store) -> str:
    if store.subcategory in _EXCLUDED_SUBCATEGORIES:
        return "excluded"
    if store.subcategory in _FACILITY_SUBCATEGORIES:
        return "facility"
    return "store"


# "B2 · 카페·베이커리" 형태. 소분류가 대분류와 같거나 비면 층만 남긴다.
def _subtitle(store: Store) -> str:
    floor_label = store.floor.name if store.floor else None
    detail = store.subcategory or store.category
    if detail and detail != store.name:
        return f"{floor_label} · {detail}" if floor_label else detail
    return floor_label or ""


def _actions(store: Store, kind: str) -> list[dict[str, str]]:
    actions: list[dict[str, str]] = []
    # 입구 노드가 없으면 온디바이스 다익스트라가 도착점을 잡을 수 없다.
    # 버튼을 띄워 두고 눌렀을 때 실패하는 것보다 아예 내리지 않는 편이 낫다.
    if store.entrance_node_id is not None:
        actions.append({"type": "directions", "label": "길찾기"})
    if kind != "excluded":
        actions.append({"type": "favorite", "label": "저장"})
    return actions


def _sections(
    store: Store,
    kind: str,
    overlay: dict[str, Any],
) -> list[dict[str, Any]]:
    # 상세를 열지 않는 대상에는 섹션을 만들지 않는다. 코어만으로 충분하고,
    # 클라이언트도 이 kind에서는 시트를 띄우지 않는다.
    if kind == "excluded":
        return []

    sections: list[dict[str, Any]] = []

    # 오버레이가 준 순서를 따르지 않고 서버가 순서를 고정한다 — 매장마다 순서가
    # 달라지면 사용자가 같은 정보를 같은 자리에서 찾지 못한다.
    #
    # 순서는 "사진 → 소개 → 메뉴 → 위치"다. 사진으로 매장을 알아보고 어떤 곳인지
    # 읽은 다음 메뉴를 본다. 주소(businessInfo)는 맨 아래다 — 건물 안에서 길을 찾는
    # 사용자에게 건물 주소는 이미 아는 정보라, 위쪽 자리를 쓸 값어치가 없다.
    hero_items = _rich_items(overlay.get("hero"), ("local_asset",))
    if hero_items:
        sections.append({"type": "hero", "items": hero_items})

    notice = overlay.get("notice")
    if isinstance(notice, dict) and str(notice.get("text", "")).strip():
        sections.append(
            {
                "type": "notice",
                "text": str(notice["text"]).strip(),
                "until": notice.get("until"),
            }
        )

    tags = overlay.get("tags")
    if isinstance(tags, list) and tags:
        sections.append({"type": "tags", "tags": [str(tag) for tag in tags]})

    summary = overlay.get("summary")
    if isinstance(summary, str) and summary.strip():
        sections.append({"type": "summary", "text": summary.strip()})

    menu_items = _rich_items(overlay.get("menu"), ("name", "price", "description", "image_asset"))
    if menu_items:
        sections.append({"type": "menu", "items": menu_items})

    items = _key_value_items(overlay)
    if items:
        sections.append({"type": "keyValue", "items": items})

    business_info_items = _rich_items(overlay.get("businessInfo"), ("label", "value"))
    if business_info_items:
        sections.append({"type": "businessInfo", "items": business_info_items})

    polygon = _polygon_points(store)
    if polygon:
        sections.append({"type": "map", "polygon_local_m": polygon})

    return sections


def _key_value_items(overlay: dict[str, Any]) -> list[dict[str, str]]:
    raw = overlay.get("keyValue")
    if not isinstance(raw, list):
        return []
    items = []
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        label = str(entry.get("label", "")).strip()
        value = str(entry.get("value", "")).strip()
        # 값이 빈 항목을 내려보내면 클라이언트에 "빈 줄" 분기가 생긴다.
        if label and value:
            items.append({"label": label, "value": value})
    return items


def _rich_items(raw: Any, keys: tuple[str, ...]) -> list[dict[str, str]]:
    if not isinstance(raw, list):
        return []

    items: list[dict[str, str]] = []
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        item = {key: str(entry.get(key, "")).strip() for key in keys}
        if all(item.values()):
            items.append(item)
    return items


# 폴리곤이 없는 매장이 14건 있다. 그 경우 map 섹션 자체를 만들지 않는다.
def _polygon_points(store: Store) -> list[dict[str, float]]:
    if not store.polygon:
        return []
    points = []
    for point in store.polygon:
        if isinstance(point, dict) and "x" in point and "y" in point:
            points.append({"x": float(point["x"]), "y": float(point["y"])})
    return points
