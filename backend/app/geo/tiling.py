# 건물의 local_m 지오메트리를 MVT 타일용 WGS84 GeoJSON 레이어로 변환한다.
# MVT 바이트 인코딩(mapbox_vector_tile) 자체는 외부 포맷 라이브러리 의존이라
# Query 쪽에서 호출한다. 이 모듈은 순수하게 (1) 슬리피맵 z/x/y -> WGS84 경계
# 상자 계산, (2) local_m -> wgs84 좌표 변환, (3) 타일과 겹치는 feature만 골라
# GeoJSON 레이어를 만드는 역할만 한다. FastAPI, SQLAlchemy, mapbox_vector_tile을
# 알지 못하고 ORM 모델(app.models)의 필드에만 의존한다.
#
# SVG 도면으로 보정한 정밀 좌표(footprint_wgs84_svg, svg_polygon_wgs84,
# centroid_lat/lng)는 현재 ORM 스키마에 없어 이 모듈은 건물 전체 affine
# 변환(GeoTransform)으로 근사한 좌표만 사용한다.

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from math import atan, degrees, pi, sinh
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from app.geo.georeference import GeoTransform
    from app.models import Building, Poi, Store


# 슬리피맵 타일 하나가 덮는 WGS84 경계 상자.
@dataclass(frozen=True)
class TileBounds:
    west: float
    south: float
    east: float
    north: float

    # 이 경계 상자가 다른 경계 상자와 겹치는지(경계 포함) 확인한다.
    def intersects(self, other_west: float, other_south: float, other_east: float, other_north: float) -> bool:
        return (
            self.west <= other_east
            and other_west <= self.east
            and self.south <= other_north
            and other_south <= self.north
        )


# 표준 슬리피맵(z/x/y, Web Mercator) 타일 좌표를 WGS84 경계 상자로 바꾼다.
def tile_bounds(z: int, x: int, y: int) -> TileBounds:
    if z < 0 or not (0 <= x < 2**z) or not (0 <= y < 2**z):
        raise ValueError(f"타일 좌표 범위를 벗어났습니다: z={z}, x={x}, y={y}")

    tiles_per_axis = 2.0**z

    # 경도는 타일 격자에 선형 비례한다.
    west = x / tiles_per_axis * 360.0 - 180.0
    east = (x + 1) / tiles_per_axis * 360.0 - 180.0

    # 타일 y는 위쪽(북쪽)이 작은 값이라 north가 y, south가 y+1에 대응한다.
    north = _tile_edge_latitude(y, tiles_per_axis)
    south = _tile_edge_latitude(y + 1, tiles_per_axis)

    return TileBounds(west=west, south=south, east=east, north=north)


# Web Mercator 타일 y좌표 한쪽 변의 위도(도).
def _tile_edge_latitude(y: int, tiles_per_axis: float) -> float:
    lat_rad = atan(sinh(pi * (1 - 2 * y / tiles_per_axis)))
    return degrees(lat_rad)


def _polygon_bbox(ring: list[list[float]]) -> tuple[float, float, float, float]:
    lngs = [point[0] for point in ring]
    lats = [point[1] for point in ring]
    return min(lngs), min(lats), max(lngs), max(lats)


# local_m 점 목록을 [lng, lat] 목록으로 옮긴다(폴리곤을 닫지는 않음).
def local_points_to_lnglat(points: list[dict], transform: GeoTransform) -> list[list[float]]:
    return [list(reversed(transform.apply(p["x"], p["y"]))) for p in points]


def _close_ring(ring: list[list[float]]) -> list[list[float]]:
    if ring and ring[0] != ring[-1]:
        return [*ring, ring[0]]
    return ring


def _local_polygon_ring(points: list[dict], transform: GeoTransform) -> list[list[float]]:
    return _close_ring(local_points_to_lnglat(points, transform))


# 매장 feature의 properties. category/subcategory는 클라이언트가 MapLibre
# setFilter로 카테고리 필터를 걸 때 쓴다.
#
# 두 컬럼 모두 nullable이라 값이 없는 매장이 실제로 있다. None일 때 **키 자체를
# 넣지 않는다.** 이유:
#
#   mapbox_vector_tile 2.2.0의 인코더는 값 타입을 _can_handle_val로 거르는데
#   (`isinstance(v, (str, bool, int, float))`), None은 여기에 걸려 예외도 null
#   인코딩도 아니고 **그 키를 조용히 통째로 버린다**. 즉 None을 그대로 넘겨도
#   지금은 "키 없음"으로 나온다 — 확인한 실제 동작이다.
#
#   그래도 여기서 명시적으로 빼는 건, 그 동작이 우리가 의존해도 되는 계약이
#   아니기 때문이다. 라이브러리가 판올림하며 null 인코딩으로 바뀌면 타일 계약이
#   조용히 달라지고(클라이언트 필터가 어긋난다), 무엇보다 "None이면 키가 없다"는
#   결정이 코드에 안 남아 리뷰에서 보이지 않는다. 호출부에서 빼면 인코더 버전과
#   무관하게 계약이 고정된다.
#
#   키 없음이 안전한 이유: MapLibre 필터에서 `['has', 'category']`로 값 유무를
#   판정할 수 있다. 반대로 null이 실리면 `has`는 참이 되면서 비교는 어긋나
#   "값이 없다"를 표현할 깔끔한 방법이 사라진다.
def _store_properties(store: Store) -> dict:
    properties: dict = {"id": store.id, "name": store.name, "kind": "store"}
    if store.category is not None:
        properties["category"] = store.category
    if store.subcategory is not None:
        properties["subcategory"] = store.subcategory
    return properties


# 건물 하나의 layers(footprint/stores/pois)를 wgs84 GeoJSON feature로 만든다.
# 타일 경계 상자와 겹치지 않는 feature는 걸러낸다(정밀 클리핑 없이 bbox 교차만
# 확인 — 실내 지도는 feature 수가 적어 이 정도로도 타일이 과도하게 커지지 않는다).
# transform이 None이면 빈 레이어만 담은 유효한 빈 타일을 돌려준다 — 404 대신
# "표시할 게 없다"로 처리해 MapLibre가 에러 없이 조용히 아무것도 안 그리게 한다.
def build_floor_tile_layers(
    building: Building,
    # 호출부가 session.scalars(...).all()의 Sequence를 그대로 넘긴다 — list로 좁히지 않는다.
    stores: Sequence[Store],
    pois: Sequence[Poi],
    transform: GeoTransform | None,
    bounds: TileBounds,
    footprint_local_m: list[dict] | None = None,
) -> list[dict]:
    if transform is None:
        return []

    layers: list[dict] = []

    # 층 외곽선을 받으면 그것을 그린다. 건물 footprint는 기준층 것이라 지하층
    # 타일에도 1F 윤곽이 찍힌다.
    footprint = footprint_local_m or building.footprint_local_m or []
    footprint_ring = _local_polygon_ring(footprint, transform)
    if footprint_ring and bounds.intersects(*_polygon_bbox(footprint_ring)):
        layers.append(
            {
                "name": "footprint",
                "features": [
                    {
                        "geometry": {"type": "Polygon", "coordinates": [footprint_ring]},
                        "properties": {"kind": "footprint", "building_id": building.id},
                    }
                ],
            }
        )

    # 매장 폴리곤 — 타일에 걸치지 않는 것은 버린다.
    store_features = []
    for store in stores:
        if not store.polygon:
            continue
        ring = _local_polygon_ring(store.polygon, transform)
        if not ring or not bounds.intersects(*_polygon_bbox(ring)):
            continue
        store_features.append(
            {
                "geometry": {"type": "Polygon", "coordinates": [ring]},
                "properties": _store_properties(store),
            }
        )
    layers.append({"name": "stores", "features": store_features})

    # POI는 점이라 bbox 교차가 곧 포함 여부다.
    poi_features = []
    for poi in pois:
        lat, lng = transform.apply(poi.x_m, poi.y_m)
        if not bounds.intersects(lng, lat, lng, lat):
            continue
        poi_features.append(
            {
                "geometry": {"type": "Point", "coordinates": [lng, lat]},
                "properties": {"id": poi.id, "name": poi.name, "type": poi.type},
            }
        )
    layers.append({"name": "pois", "features": poi_features})

    return layers
