"""건물 층 지도를 MVT(Mapbox Vector Tile) 바이트로 렌더링하는 Query 함수.

- geo_transform은 DB 컬럼으로 저장하지 않고, 요청마다 해당 건물 Node들의
  (x_m, y_m, lat, lng) 실측 대응점으로 즉석 피팅한다. 실측 앵커가 3개
  미만이면(예: test-center처럼 합성 데이터) 임의 앵커에 1m=1m로 배치하는
  합성 대응점으로 대체한다 — None을 반환해 지도에 아무것도 못 그리게 두는
  대신, 위치는 가짜지만 형태/크기는 정확한 지도를 보여준다.
"""

from __future__ import annotations

import mapbox_vector_tile
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.domain.georeference import GeoTransform, PointPair, fit_wgs84_transform
from app.domain.tiling import build_floor_tile_layers, tile_bounds
from app.models import Building, Floor, Node, Poi, Store
from app.queries.building_queries import _find_floor

# test-center처럼 실측 wgs84 앵커가 전혀 없는 합성 건물을 임의로 배치할 기준점
# (서울시청 — client의 GPS 실패 fallback 위치와 맞춰서, 데모 앱에서 우연히라도
# 같은 동네에 보이게 한다). 실측 좌표가 아니라 "지도에 뭔가 보이게" 하기 위한
# 자리끼움일 뿐이다.
_SYNTHETIC_ANCHOR_LAT = 37.5665
_SYNTHETIC_ANCHOR_LNG = 126.9780
_METERS_PER_DEGREE_LAT = 111_320.0


def _synthetic_geo_pairs(anchor_lat: float, anchor_lng: float) -> list[PointPair]:
    """실측 앵커가 없는 건물을 위해 local_m 1m = 실좌표 1m로 매핑하는 가상
    대응점 3개를 만든다."""
    from math import cos, radians

    lng_scale = cos(radians(anchor_lat))

    def to_wgs84(x_m: float, y_m: float) -> tuple[float, float]:
        lat = anchor_lat + y_m / _METERS_PER_DEGREE_LAT
        lng = anchor_lng + x_m / (_METERS_PER_DEGREE_LAT * lng_scale)
        return lat, lng

    pairs = []
    for x_m, y_m in ((0.0, 0.0), (100.0, 0.0), (0.0, 100.0)):
        lat, lng = to_wgs84(x_m, y_m)
        pairs.append(PointPair(x=x_m, y=y_m, u=lng, v=lat))
    return pairs


def _fit_building_geo_transform(session: Session, building_id: str) -> GeoTransform:
    """건물의 모든 층 Node 중 실측 wgs84가 채워진 것으로 local_m -> wgs84
    affine 변환을 피팅한다. 대응점이 3개 미만이면 합성 대응점으로 대체한다."""
    rows = session.execute(
        select(Node.x_m, Node.y_m, Node.lat, Node.lng)
        .join(Floor, Node.floor_id == Floor.id)
        .where(
            Floor.building_id == building_id,
            Node.lat.is_not(None),
            Node.lng.is_not(None),
        )
    ).all()

    pairs = [PointPair(x=x_m, y=y_m, u=lng, v=lat) for x_m, y_m, lat, lng in rows]
    if len(pairs) < 3:
        pairs = _synthetic_geo_pairs(_SYNTHETIC_ANCHOR_LAT, _SYNTHETIC_ANCHOR_LNG)
    return fit_wgs84_transform(pairs)


def render_floor_tile(
    session: Session,
    building_id: str,
    floor_name: str,
    z: int,
    x: int,
    y: int,
) -> bytes | None:
    """층 지도를 MVT 바이트로 렌더링한다. 건물/층이 없으면 None."""
    floor = _find_floor(session, building_id, floor_name)
    if floor is None:
        return None
    building = session.get(Building, building_id)
    if building is None:
        return None

    transform = _fit_building_geo_transform(session, building_id)
    bounds = tile_bounds(z, x, y)
    stores = session.scalars(select(Store).where(Store.floor_id == floor.id)).all()
    pois = session.scalars(select(Poi).where(Poi.floor_id == floor.id)).all()
    layers = build_floor_tile_layers(building, stores=stores, pois=pois, transform=transform, bounds=bounds)

    return mapbox_vector_tile.encode(
        layers,
        default_options={
            "quantize_bounds": (bounds.west, bounds.south, bounds.east, bounds.north),
        },
    )
