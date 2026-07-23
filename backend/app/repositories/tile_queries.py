# 건물 층 지도를 MVT(Mapbox Vector Tile) 바이트로 렌더링하는 Query 함수.
# geo_transform은 DB 컬럼으로 저장하지 않고, 요청마다 해당 건물 Node들의
# (x_m, y_m, lat, lng) 실측 대응점으로 즉석 피팅한다. 실측 앵커가 3개
# 미만이면(예: test-center처럼 합성 데이터) 임의 앵커에 1m=1m로 배치하는
# 합성 대응점으로 대체한다 — None을 반환해 지도에 아무것도 못 그리게 두는
# 대신, 위치는 가짜지만 형태/크기는 정확한 지도를 보여준다.

from __future__ import annotations

import mapbox_vector_tile
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.geo.tiling import build_floor_tile_layers, tile_bounds
from app.models import Building, Poi, Store
from app.repositories.building_queries import _find_floor
from app.repositories.geo_transform import fit_building_geo_transform


# 층 지도를 MVT 바이트로 렌더링한다. 건물/층이 없으면 None.
def render_floor_tile(
    session: Session,
    building_id: str,
    floor_name: str,
    z: int,
    x: int,
    y: int,
) -> bytes | None:
    floor = _find_floor(session, building_id, floor_name)
    if floor is None:
        return None

    building = session.get(Building, building_id)
    if building is None:
        return None

    # 좌표 변환과 타일 경계 — 무엇을 그릴지 고르는 기준.
    transform = fit_building_geo_transform(session, building_id)
    bounds = tile_bounds(z, x, y)

    stores = session.scalars(select(Store).where(Store.floor_id == floor.id)).all()
    pois = session.scalars(select(Poi).where(Poi.floor_id == floor.id)).all()

    layers = build_floor_tile_layers(
        building,
        stores=stores,
        pois=pois,
        transform=transform,
        bounds=bounds,
        footprint_local_m=floor.footprint_local_m,
    )

    return mapbox_vector_tile.encode(
        layers,
        default_options={
            "quantize_bounds": (bounds.west, bounds.south, bounds.east, bounds.north),
        },
    )
