"""층 지도 API 응답 모델."""

from typing import Literal

from pydantic import BaseModel

from app.schemas.route import FloorGraphResponse


class PointResponse(BaseModel):
    x: float
    y: float


class ViewBoxResponse(BaseModel):
    min_x: float
    min_y: float
    width: float
    height: float


class VectorCoordinateSystemResponse(BaseModel):
    id: Literal["svg_viewbox_px"]
    unit: Literal["px"]
    origin: Literal["top-left"]
    x_axis: Literal["right"]
    y_axis: Literal["down"]
    view_box: ViewBoxResponse


class VectorGeometryResponse(BaseModel):
    type: Literal["Polygon", "LineString", "MultiLineString"]
    coordinates: list[PointResponse] | list[list[PointResponse]]


class MapFeatureResponse(BaseModel):
    id: str
    kind: Literal["footprint", "store", "amenity", "wall", "gate"]
    name: str | None
    category: str | None
    geometry: VectorGeometryResponse
    centroid: PointResponse | None


class VectorMapResponse(BaseModel):
    coordinate_system: VectorCoordinateSystemResponse
    source: dict[str, str]
    features: list[MapFeatureResponse]


class FloorResponse(BaseModel):
    id: str
    name: str
    level: int


class StoreResponse(BaseModel):
    id: str
    floor_id: str
    name: str
    centroid_local_m: PointResponse
    entrance_local_m: PointResponse | None
    entrance_node_id: str | None
    polygon_local_m: list[PointResponse] | None


class PoiResponse(BaseModel):
    id: str
    type: str
    name: str | None
    position_local_m: PointResponse
    linked_node_id: str | None


class FloorMapResponse(BaseModel):
    floor: FloorResponse
    navigation_coordinate_system: Literal["local_m"]
    footprint_local_m: list[PointResponse]
    vector_map: VectorMapResponse | None
    navigation_graph: FloorGraphResponse
    stores: list[StoreResponse]
    pois: list[PoiResponse]
