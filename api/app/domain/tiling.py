"""건물의 local_m 지오메트리를 MVT 타일용 WGS84 GeoJSON 레이어로 변환한다.

MVT 바이트 인코딩(mapbox_vector_tile) 자체는 외부 포맷 라이브러리 의존이라
Query 쪽에서 호출한다. 이 모듈은 순수하게 (1) 슬리피맵 z/x/y -> WGS84 경계
상자 계산, (2) local_m -> wgs84 좌표 변환, (3) 타일과 겹치는 feature만 골라
GeoJSON 레이어를 만드는 역할만 한다. FastAPI, SQLAlchemy, mapbox_vector_tile을
알지 못하고 ORM 모델(``app.models``)의 필드에만 의존한다.

SVG 도면으로 보정한 정밀 좌표(footprint_wgs84_svg, svg_polygon_wgs84,
centroid_lat/lng)는 현재 ORM 스키마에 없어 이 모듈은 건물 전체 affine
변환(``GeoTransform``)으로 근사한 좌표만 사용한다.
"""

from __future__ import annotations

from dataclasses import dataclass
from math import atan, degrees, pi, sinh
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from app.domain.georeference import GeoTransform
    from app.models import Building, Poi, Store


@dataclass(frozen=True)
class TileBounds:
    """슬리피맵 타일 하나가 덮는 WGS84 경계 상자."""

    west: float
    south: float
    east: float
    north: float

    def intersects(self, other_west: float, other_south: float, other_east: float, other_north: float) -> bool:
        """이 경계 상자가 다른 경계 상자와 겹치는지(경계 포함) 확인한다."""
        return (
            self.west <= other_east
            and other_west <= self.east
            and self.south <= other_north
            and other_south <= self.north
        )


def tile_bounds(z: int, x: int, y: int) -> TileBounds:
    """표준 슬리피맵(z/x/y, Web Mercator) 타일 좌표를 WGS84 경계 상자로 바꾼다."""
    if z < 0 or not (0 <= x < 2**z) or not (0 <= y < 2**z):
        raise ValueError(f"타일 좌표 범위를 벗어났습니다: z={z}, x={x}, y={y}")

    tiles_per_axis = 2.0**z
    west = x / tiles_per_axis * 360.0 - 180.0
    east = (x + 1) / tiles_per_axis * 360.0 - 180.0
    # 타일 y는 위쪽(북쪽)이 작은 값이라 north가 y, south가 y+1에 대응한다.
    north = _tile_edge_latitude(y, tiles_per_axis)
    south = _tile_edge_latitude(y + 1, tiles_per_axis)
    return TileBounds(west=west, south=south, east=east, north=north)


def _tile_edge_latitude(y: int, tiles_per_axis: float) -> float:
    """Web Mercator 타일 y좌표 한쪽 변의 위도(도)."""
    lat_rad = atan(sinh(pi * (1 - 2 * y / tiles_per_axis)))
    return degrees(lat_rad)


def _polygon_bbox(ring: list[list[float]]) -> tuple[float, float, float, float]:
    lngs = [point[0] for point in ring]
    lats = [point[1] for point in ring]
    return min(lngs), min(lats), max(lngs), max(lats)


def local_points_to_lnglat(points: list[dict], transform: "GeoTransform") -> list[list[float]]:
    """local_m 점 목록을 [lng, lat] 목록으로 옮긴다(폴리곤을 닫지는 않음)."""
    return [list(reversed(transform.apply(p["x"], p["y"]))) for p in points]


def _close_ring(ring: list[list[float]]) -> list[list[float]]:
    if ring and ring[0] != ring[-1]:
        return [*ring, ring[0]]
    return ring


def _local_polygon_ring(points: list[dict], transform: "GeoTransform") -> list[list[float]]:
    return _close_ring(local_points_to_lnglat(points, transform))


def build_floor_tile_layers(
    building: "Building",
    stores: list["Store"],
    pois: list["Poi"],
    transform: "GeoTransform | None",
    bounds: TileBounds,
) -> list[dict]:
    """건물 하나의 layers(footprint/stores/pois)를 wgs84 GeoJSON feature로 만든다.

    이 타일 경계 상자와 겹치지 않는 feature는 걸러낸다(정밀 클리핑은 하지
    않고 bbox 교차만 확인 — 실내 지도는 feature 수가 적어 이 정도로도
    타일이 과도하게 커지지 않는다).

    transform이 None이면 빈 레이어만 담은 유효한 빈 타일을 돌려준다 — 404
    대신 "표시할 게 없다"로 처리해 MapLibre 쪽에서 에러 없이 조용히 아무것도
    그리지 않게 한다.
    """
    if transform is None:
        return []

    layers: list[dict] = []

    footprint_ring = _local_polygon_ring(building.footprint_local_m or [], transform)
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
                "properties": {"id": store.id, "name": store.name, "kind": "store"},
            }
        )
    layers.append({"name": "stores", "features": store_features})

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
