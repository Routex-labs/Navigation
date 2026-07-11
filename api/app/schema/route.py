"""최단 경로 API 응답 모델."""

from typing import Literal

from pydantic import BaseModel, Field


class LocalPointResponse(BaseModel):
    x: float
    y: float


class GraphFloorResponse(BaseModel):
    id: str
    name: str


class GraphNodeResponse(BaseModel):
    id: str
    type: str
    name: str | None
    x_m: float
    y_m: float
    lat: float | None
    lng: float | None


class GraphEdgeResponse(BaseModel):
    id: str
    from_node_id: str = Field(alias="from")
    to_node_id: str = Field(alias="to")
    length_m: float
    bidirectional: bool
    geometry_local_m: list[LocalPointResponse]


class FloorGraphResponse(BaseModel):
    floor: GraphFloorResponse
    nodes: list[GraphNodeResponse]
    edges: list[GraphEdgeResponse]


class RouteResponse(BaseModel):
    start_node_id: str
    end_node_id: str
    path_found: Literal[True]
    node_ids: list[str]
    edge_ids: list[str]
    coordinate_system: Literal["local_m"]
    path_points: list[LocalPointResponse]
    total_distance_m: float
