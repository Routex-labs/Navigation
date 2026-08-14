# 한 폴리곤을 여러 매장이 나눠 쓰는 자리의 칸 계산 (더현대 서울 31곳·91매장).
#
# 타일(app/geo/tiling.py)과 층 도면 응답(app/repositories/building_queries.py)이 **이
# 모듈 하나를 함께 쓴다.** 두 벌로 두면 바닥 fill과 강조 폴리곤이 서로 다른 자리를
# 가리킨다 — 실제로 그랬다. 왜 이렇게 나누는지는 docs/backend/shared-polygon-split.md.
#
# ORM 모델(app.models.Store)의 필드에만 의존하고 좌표계 변환은 알지 못한다.

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from app.models import Store


# 나눠 쓰는 폴리곤에서 매장 하나가 받는 띠. 축에 수직인 두 경계 사이다.
@dataclass(frozen=True)
class SharedSlab:
    axis_is_x: bool
    low: float
    high: float

    @property
    def middle(self) -> float:
        return (self.low + self.high) / 2


# 다른 매장 이름 2개 이상을 이어 붙인 "묶음 매장" id. 라벨도 칸 배치도 주지 않는다.
# 판정 근거와 예시는 docs/backend/shared-polygon-split.md.
def aggregate_store_ids(stores: Sequence[Store]) -> set[str]:
    squashed = {store.id: "".join(store.name.split()) for store in stores if store.name}
    aggregate_ids: set[str] = set()
    for store in stores:
        mine = squashed.get(store.id, "")
        if len(mine) < 4:
            continue
        contained = {
            other_name
            for other_id, other_name in squashed.items()
            if other_id != store.id and len(other_name) >= 2 and other_name != mine and other_name in mine
        }
        if len(contained) >= 2:
            aggregate_ids.add(store.id)
    return aggregate_ids


# centroid가 같은 매장 묶음. 2곳 이상인 그룹만 돌려준다.
def shared_store_groups(
    stores: Sequence[Store],
    exclude_ids: set[str],
) -> list[list[Store]]:
    groups: dict[tuple[float, float], list[Store]] = {}
    for store in stores:
        if not store.polygon or store.id in exclude_ids:
            continue
        # mm 단위 반올림. 원본이 같은 값을 복사해 넣은 경우만 묶이고,
        # 실제로 다른 매장이 우연히 묶일 수 없는 정밀도다.
        key = (round(store.centroid_x_m, 3), round(store.centroid_y_m, 3))
        groups.setdefault(key, []).append(store)
    return [group for group in groups.values() if len(group) >= 2]


# 그룹 폴리곤의 긴 축(axis_is_x, low, span)과 그 축 기준 매장 순서.
# 순서는 다비오 입구 핀을 축에 투영해 따르고, 핀이 없으면 id로 고정한다.
def group_axis_and_order(group: list[Store]) -> tuple[bool, float, float, list[Store]]:
    # 그룹은 폴리곤 있는 매장만 담는다([shared_store_groups]) — 타입만 좁힌다.
    polygon = group[0].polygon or []
    xs = [point["x"] for point in polygon]
    ys = [point["y"] for point in polygon]
    span_x = max(xs) - min(xs)
    span_y = max(ys) - min(ys)
    axis_is_x = span_x >= span_y
    low = min(xs) if axis_is_x else min(ys)
    span = span_x if axis_is_x else span_y

    def order_key(store: Store) -> tuple[float, str]:
        coord = store.entrance_x_m if axis_is_x else store.entrance_y_m
        return (coord if coord is not None else 0.0, store.id)

    return axis_is_x, low, span, sorted(group, key=order_key)


# 매장 id → 그 매장이 받는 띠. 폴리곤의 긴 축을 매장 수로 나누고, 순서는 다비오 입구
# 핀을 그 축에 투영해 따른다.
#
# **두 곳이 나눠 쓰는 자리만 나눈다.** 세 곳 이상은 칸이 줄무늬처럼 갈라져 도면이 표처럼
# 보였다(실기기 확인) — 그 자리는 폴리곤도 원본 그대로 둔다. 이 함수가 그 결정의 단일
# 출처다(docs/backend/shared-polygon-split.md).
def shared_slabs(groups: Sequence[list[Store]]) -> dict[str, SharedSlab]:
    out: dict[str, SharedSlab] = {}
    for group in groups:
        if len(group) != 2:
            continue
        axis_is_x, low, span, ordered = group_axis_and_order(group)
        width = span / len(ordered)
        for index, store in enumerate(ordered):
            slab_low = low + index * width
            out[store.id] = SharedSlab(axis_is_x=axis_is_x, low=slab_low, high=slab_low + width)
    return out


# 폴리곤(local_m)을 축에 수직인 두 경계 사이의 띠로 자른다. Sutherland–Hodgman —
# 띠가 볼록이라 오목한 폴리곤도 안전하다. 결과가 도형이 못 되면 빈 목록이고 호출부가
# 원본을 쓴다.
def clip_polygon_to_slab(
    polygon: list[dict],
    axis_is_x: bool,
    low: float,
    high: float,
) -> list[dict]:
    def axis_value(point: dict) -> float:
        return point["x"] if axis_is_x else point["y"]

    def clip(points: list[dict], bound: float, keep_ge: bool) -> list[dict]:
        result: list[dict] = []
        for index in range(len(points)):
            current = points[index]
            previous = points[index - 1]
            current_in = (axis_value(current) >= bound) == keep_ge or axis_value(current) == bound
            previous_in = (axis_value(previous) >= bound) == keep_ge or axis_value(previous) == bound
            if current_in != previous_in:
                span = axis_value(current) - axis_value(previous)
                t = 0.0 if span == 0 else (bound - axis_value(previous)) / span
                result.append(
                    {
                        "x": previous["x"] + (current["x"] - previous["x"]) * t,
                        "y": previous["y"] + (current["y"] - previous["y"]) * t,
                    }
                )
            if current_in:
                result.append(current)
        return result

    points = list(polygon)
    points = clip(points, low, keep_ge=True)
    if len(points) < 3:
        return []
    points = clip(points, high, keep_ge=False)
    return points if len(points) >= 3 else []


# 매장 id → 자기 칸으로 자른 폴리곤(local_m). 나눠 쓰지 않는 매장은 키가 없다.
#
# **[stores]는 한 층의 매장 전체여야 한다.** 부분 집합을 주면 짝을 못 찾아 아무것도
# 나누지 않는다.
def split_shared_polygons(stores: Sequence[Store]) -> dict[str, list[dict]]:
    groups = shared_store_groups(stores, aggregate_store_ids(stores))
    by_id = {store.id: store for group in groups for store in group}
    out: dict[str, list[dict]] = {}
    for store_id, slab in shared_slabs(groups).items():
        clipped = clip_polygon_to_slab(
            by_id[store_id].polygon or [],
            slab.axis_is_x,
            slab.low,
            slab.high,
        )
        if clipped:
            out[store_id] = clipped
    return out
