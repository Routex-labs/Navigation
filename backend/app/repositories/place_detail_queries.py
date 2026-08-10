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
            # source는 출처의 **종류**다(studio/manual/derived). 오버레이가 있으면
            # 사람이 적은 것이므로 manual이고, 그 문구를 어디서 옮겨 왔는지는 url이
            # 따로 들고 간다.
            "source": "manual" if overlay else "studio",
            "updated_at": overlay.get("updated_at"),
            "url": overlay.get("source"),
        },
    }


def _classify(store: Store) -> str:
    return classify_place_kind(store.subcategory)


# 소분류 하나로 kind를 정한다. **이 함수가 kind 규칙의 단일 출처다** —
# 매장 색인(`building_queries.list_store_index`)도 같은 값을 실어 보내야 하는데,
# 규칙을 그쪽에 베끼면 "상세는 안 열리는데 목록에는 있는" 상태가 조용히 생긴다.
# Store가 아니라 소분류 문자열을 받는 이유는 색인 질의가 ORM 객체가 아니라
# 컬럼만 뽑기 때문이다(1,640건에 객체를 만들 이유가 없다).
def classify_place_kind(subcategory: str | None) -> str:
    if subcategory in _EXCLUDED_SUBCATEGORIES:
        return "excluded"
    if subcategory in _FACILITY_SUBCATEGORIES:
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

    # 영업시간은 소개·메뉴보다 위다. 상세를 연 사람이 가장 먼저 정하는 것이 "지금
    # 갈 수 있나"이고, 그 판단이 무슨 매장인지 읽는 것보다 앞선다(지도·상세 UI 개선
    # 계획이 "헤더 바로 아래 한 줄"이라고 적어 둔 자리에 섹션 배열로 가장 가깝다).
    hours = _hours_section(overlay.get("hours"))
    if hours is not None:
        sections.append(hours)

    tags = overlay.get("tags")
    if isinstance(tags, list) and tags:
        sections.append({"type": "tags", "tags": [str(tag) for tag in tags]})

    summary = overlay.get("summary")
    if isinstance(summary, str) and summary.strip():
        sections.append({"type": "summary", "text": summary.strip()})

    menu_items = _rich_items(
        overlay.get("menu"),
        ("name", "image_asset"),
        (
            "group",
            "category",
            "name_en",
            "description",
            "price",
            "volume",
            "calories",
            "caffeine",
            "allergens",
        ),
        ("badges",),
    )
    if menu_items:
        sections.append({"type": "menu", "items": menu_items})

    items = _key_value_items(overlay)
    if items:
        sections.append({"type": "keyValue", "items": items})

    # 영업시간·대표번호처럼 낡는 값이 들어 있는 섹션이다. businessInfo보다 위에 두는
    # 이유는 매장을 고르는 데 실제로 쓰이기 때문이고, 아래 주소는 건물 주소라 이미
    # 아는 정보다.
    demo_info_items = _rich_items(overlay.get("demoInfo"), ("label", "value", "source", "confirmed_at"))
    if demo_info_items:
        sections.append({"type": "demoInfo", "items": demo_info_items})

    # 링크는 운영 정보 아래에 둔다. 매장을 고르는 데 쓰이는 값이 아니라, 고른 뒤에
    # 더 알아보려는 사람이 찾는 자리다.
    link_items = _rich_items(overlay.get("links"), ("label", "url"))
    if link_items:
        sections.append({"type": "links", "items": link_items})

    business_info_items = _rich_items(overlay.get("businessInfo"), ("label", "value"))
    if business_info_items:
        sections.append({"type": "businessInfo", "items": business_info_items})

    polygon = _polygon_points(store)
    if polygon:
        sections.append({"type": "map", "polygon_local_m": polygon})

    return sections


# 영업시간 섹션. 요일 7개가 다 있고 구간이 하나라도 있어야 만든다.
#
# **판정 문자열을 만들지 않는다.** 서버가 "영업 중"을 계산해 넣으면 그 값은 응답을
# 만든 순간부터 틀리기 시작하고, ETag 캐시가 걸려 있어 더 오래 살아남는다. 서버가
# 내려보내는 것은 규칙뿐이고, 지금 시각과의 비교는 화면이 한다(설계 9-1).
#
# 요일 키가 하나라도 없으면 섹션 자체를 만들지 않는다. 검증기가 시드 단계에서
# 막지만, 그 검사를 우회한 데이터가 들어와도 화면에 "모르는 요일 = 휴무"가 뜨지
# 않게 하는 두 번째 문이다.
def _hours_section(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None

    weekly_raw = raw.get("weekly")
    if not isinstance(weekly_raw, dict) or any(key not in weekly_raw for key in place_details.WEEKDAY_KEYS):
        return None

    weekly = {key: _intervals(weekly_raw[key]) for key in place_details.WEEKDAY_KEYS}
    # 7일이 전부 빈 배열이면 "늘 닫혀 있다"는 말이 되는데, 그건 영업시간이 아니라
    # 폐점이다. 규칙이 하나도 없는 섹션을 내려보내지 않는다(계약 4-2 규칙 1).
    if not any(weekly.values()):
        return None

    source = str(raw.get("source", "")).strip()
    confirmed_at = str(raw.get("confirmed_at", "")).strip()
    if not source or not confirmed_at:
        return None

    offset = raw.get("utc_offset_minutes")
    return {
        "type": "hours",
        "weekly": weekly,
        "exceptions": _hours_exceptions(raw.get("exceptions")),
        # 매장이 전부 서울에 있어 기본값이 뜻을 갖는다. 그래도 응답에는 **항상**
        # 실어 보낸다 — 클라이언트와 서버가 각자 기본값을 들면 둘이 갈라진다.
        "utc_offset_minutes": offset if isinstance(offset, int) and not isinstance(offset, bool) else 540,
        "confirmed_at": confirmed_at,
        "source": source,
    }


def _hours_exceptions(raw: Any) -> list[dict[str, Any]]:
    if not isinstance(raw, list):
        return []

    exceptions: list[dict[str, Any]] = []
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        day = str(entry.get("date", "")).strip()
        if not day:
            continue
        closed = entry.get("closed") is True
        intervals = _intervals(entry.get("intervals"))
        # 휴무도 아니고 구간도 없는 예외는 그 날짜에 아무 말도 하지 않는다.
        if not closed and not intervals:
            continue
        exception: dict[str, Any] = {"date": day, "closed": closed, "intervals": intervals}
        note = str(entry.get("note", "")).strip()
        if note:
            exception["note"] = note
        exceptions.append(exception)
    return exceptions


def _intervals(raw: Any) -> list[dict[str, str]]:
    if not isinstance(raw, list):
        return []
    intervals = []
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        opens = str(entry.get("open", "")).strip()
        closes = str(entry.get("close", "")).strip()
        if opens and closes:
            intervals.append({"open": opens, "close": closes})
    return intervals


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


# 필수 키가 하나라도 비면 항목을 버리고, 선택 키는 값이 있을 때만 싣는다.
#
# 선택 키를 빈 문자열로 채워 내려보내지 않는 이유는 섹션을 아예 만들지 않는 규칙(계약
# 4-2 규칙 1)과 같다 — 빈 값이 실려 나가면 클라이언트가 "있는데 비었다"와 "없다"를
# 구분하는 분기를 갖게 되고, 그 분기가 카드마다 다른 높이로 새어 나온다.
def _rich_items(
    raw: Any,
    keys: tuple[str, ...],
    optional_keys: tuple[str, ...] = (),
    list_keys: tuple[str, ...] = (),
) -> list[dict[str, Any]]:
    if not isinstance(raw, list):
        return []

    items: list[dict[str, Any]] = []
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        item: dict[str, Any] = {key: str(entry.get(key, "")).strip() for key in keys}
        if not all(item.values()):
            continue
        for key in optional_keys:
            value = str(entry.get(key, "")).strip()
            if value:
                item[key] = value
        # 문자열 배열 키(menu.badges). 위 선택 키와 달리 빈 배열도 싣지 않는다 —
        # 없는 것과 비어 있는 것을 구분할 이유가 없고, 응답에 `"badges": []`가
        # 316줄 붙으면 그만큼이 그냥 전송 낭비다.
        for key in list_keys:
            values = [str(one).strip() for one in entry.get(key) or [] if str(one).strip()]
            if values:
                item[key] = values
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
