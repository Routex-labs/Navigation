"""
순수 도메인 데이터 객체.
"""

from dataclasses import dataclass, field

@dataclass(frozen=True)
class Building:
    id: str
    name: str
    area_m2: float
    perimeter_m: float
    footprint_local_m: list[dict] = field(default_factory=list) # [{"x", "y"}, ...]

@dataclass(frozen=True)
class Floor:
    id: str
    building_id: str
    name: str # 예: "1F"
    level: int

@dataclass(frozen=True)
class Node:
    id: str
    floor_id: str
    type: str # corridor | junction | store_entrance | escalator | elevator | dead_end
    name: str | None
    x_m: float
    y_m: float
    lat: float | None  # WGS84 (provisional)
    lng: float | None

@dataclass(frozen=True)
class Edge:
    id: str
    floor_id: str
    from_node_id: str
    to_node_id: str
    length_m: float
    bidirectional: bool
    geometry_local_m: list[dict] = field(default_factory=list)

@dataclass(frozen=True)
class Store:
    id: str
    floor_id: str
    name: str
    centroid_x_m: float
    centroid_y_m: float
    entrance_node_id: str | None
    polygon_local_m: list[dict] | None = None

@dataclass(frozen=True)
class Poi:
    id: str
    floor_id: str
    type: str  # elevator | escalator | toilet | exit | ...
    name: str | None
    x_m: float
    y_m: float
    linked_node_id: str | None