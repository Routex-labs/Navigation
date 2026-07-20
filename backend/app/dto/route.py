"""층 길찾기 그래프 API 응답 모델.

최단 경로 계산은 클라이언트가 이 그래프로 온디바이스 다익스트라를 돌린다(서버 미보유).
"""

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
