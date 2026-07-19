"""층 지도 API 응답 모델."""

from typing import Literal

from pydantic import BaseModel

from app.schemas.route import FloorGraphResponse


class PointResponse(BaseModel):
    x: float
    y: float


class LatLngResponse(BaseModel):
    lat: float
    lng: float


class FloorResponse(BaseModel):
    id: str
    name: str
    level: int


class StoreResponse(BaseModel):
    id: str
    floor_id: str
    name: str
    category: str | None = None
    subcategory: str | None = None
    centroid_local_m: PointResponse
    # 실측 앵커가 부족하면 합성 좌표 기반 근사치가 채워진다.
    centroid_wgs84: LatLngResponse | None
    polygon_wgs84: list[LatLngResponse] | None
    entrance_local_m: PointResponse | None
    entrance_node_id: str | None
    polygon_local_m: list[PointResponse] | None


class PoiResponse(BaseModel):
    id: str
    type: str
    name: str | None
    position_local_m: PointResponse
    position_wgs84: LatLngResponse | None
    linked_node_id: str | None


class FloorMapResponse(BaseModel):
    floor: FloorResponse
    navigation_coordinate_system: Literal["local_m"]
    footprint_local_m: list[PointResponse]
    footprint_wgs84: list[LatLngResponse] | None
    navigation_graph: FloorGraphResponse
    stores: list[StoreResponse]
    pois: list[PoiResponse]
