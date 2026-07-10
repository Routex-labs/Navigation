"""Repository와 Service 사이에서 사용하는 순수 도메인 데이터 객체."""

from dataclasses import dataclass, field

# frozen=True는 조회된 도메인 값이 Service에서 실수로 변경되는 것을 막는다.

@dataclass(frozen=True)
class Building:
    """건물의 기본 정보와 실내 좌표계 기준 외곽선."""

    id: str
    name: str
    area_m2: float
    perimeter_m: float
    # SQLite TEXT에 JSON으로 저장된 건물 외곽 폴리곤을 복원한 값이다.
    footprint_local_m: list[dict] = field(default_factory=list)  # [{"x", "y"}, ...]

@dataclass(frozen=True)
class Floor:
    """건물에 속한 층. level은 층 표시 순서를 정할 때 사용한다."""

    id: str
    building_id: str
    name: str  # 예: "1F"
    level: int

@dataclass(frozen=True)
class LocalPoint:
    """실내 지도에서 사용하는 로컬 미터 좌표 값 객체."""

    x_m: float
    y_m: float

@dataclass(frozen=True)
class Node:
    """길찾기 그래프의 정점. 복도 교차점이나 매장 입구 등을 나타낸다."""

    id: str
    floor_id: str
    type: str  # corridor | junction | store_entrance | escalator | elevator | dead_end
    name: str | None
    # DB의 x_m/y_m 두 컬럼을 하나의 좌표 값 객체로 묶는다.
    position: LocalPoint
    lat: float | None  # WGS84 (provisional)
    lng: float | None

@dataclass(frozen=True)
class Edge:
    """두 Node를 연결하는 길찾기 그래프 간선."""

    id: str
    floor_id: str
    from_node_id: str
    to_node_id: str
    length_m: float  # 다익스트라가 사용하는 비음수 가중치
    bidirectional: bool  # True면 반대 방향 이동도 허용
    # 단순 직선이 아닌 실제 복도 중심선을 그릴 때 사용하는 polyline이다.
    geometry_local_m: list[dict] = field(default_factory=list)

@dataclass(frozen=True)
class Store:
    """층에 표시할 매장과 길찾기에 연결되는 선택적 입구 정보."""

    id: str
    floor_id: str
    name: str
    centroid: LocalPoint
    # 입구 좌표나 입구 노드가 없는 매장은 None을 가질 수 있다.
    entrance: LocalPoint | None
    entrance_node_id: str | None
    polygon_local_m: list[dict] | None = None

@dataclass(frozen=True)
class Poi:
    """화장실·출구·엘리베이터처럼 매장 외에 표시할 관심 지점."""

    id: str
    floor_id: str
    type: str  # elevator | escalator | toilet | exit | ...
    name: str | None
    position: LocalPoint
    # 길찾기 그래프와 연결되는 경우 해당 Node ID를 가진다.
    linked_node_id: str | None
