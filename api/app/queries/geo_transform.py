"""건물의 local_m -> WGS84 affine 변환을 요청 시점에 피팅하는 공용 함수.

DB 컬럼으로 저장하지 않고, 해당 건물 Node들의 (x_m, y_m, lat, lng) 실측
대응점으로 매번 즉석 피팅한다. MVT 타일 렌더링(tile_queries)과 JSON 층 지도
응답(building_queries)이 이 함수를 공유해야 두 경로가 같은 좌표를 가리킨다.
"""

from __future__ import annotations

from math import cos, radians

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.domain.georeference import GeoTransform, PointPair, fit_wgs84_transform
from app.models import Floor, Node

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


def fit_building_geo_transform(session: Session, building_id: str) -> GeoTransform:
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
