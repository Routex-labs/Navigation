"""층 길찾기 그래프 API 응답 모델.

최단 경로 계산은 클라이언트가 이 그래프로 온디바이스 다익스트라를 돌린다(서버 미보유).
"""

from pydantic import BaseModel, Field


# 그래프 좌표 한 점 (local_m).
class LocalPointResponse(BaseModel):
    x: float  # 로컬 좌표 X (미터)
    y: float  # 로컬 좌표 Y (미터)


# 이 그래프가 어느 층 것인지. 지도 응답의 FloorResponse보다 얇다(level 없음).
class GraphFloorResponse(BaseModel):
    id: str    # 층 고유 id
    name: str  # 사람이 보는 층 라벨 (예: B2)


# 경로 그래프의 정점. 통로 교차점·매장 입구·수직이동 지점이 여기 해당한다.
class GraphNodeResponse(BaseModel):
    id: str           # 노드 고유 id
    type: str         # 노드 종류 (통로·입구·엘리베이터 등). 경로 안내 문구와 아이콘의 근거
    name: str | None  # 표시 이름, 선택

    x_m: float  # 노드 위치 X (local_m)
    y_m: float  # 노드 위치 Y (local_m)

    lat: float | None  # 실측 위도. 이 값이 채워진 노드들이 좌표 변환의 앵커가 된다
    lng: float | None  # 실측 경도. 앵커가 3개 미만이면 합성 좌표로 폴백한다

    # 건물 전체 그래프에서만 채워진다(층별 그래프는 단일 층이라 생략). 전 층 노드가
    # 한 그래프에 섞일 때 클라이언트가 층별로 다시 나누는 근거.
    floor_id: str | None = None


# 두 노드를 잇는 간선. 다익스트라의 가중치는 length_m다.
class GraphEdgeResponse(BaseModel):
    id: str  # 간선 고유 id

    # 내부 from_node_id/to_node_id를 API에서는 짧은 from/to 키로 노출한다.
    from_node_id: str = Field(alias="from")  # 시작 노드 id
    to_node_id: str = Field(alias="to")      # 도착 노드 id

    length_m: float      # 간선 길이 (미터). 경로 비용
    bidirectional: bool  # 양방향 통행 가능 여부. False면 from→to만 지날 수 있다

    geometry_local_m: list[LocalPointResponse]  # 간선을 그릴 꺾은선 (local_m). 비면 직선으로 그린다

    # 층 내부 간선은 None, 수직 전이 간선은 "elevator"/"escalator". 경로 안내 문구·아이콘 근거.
    transfer_mode: str | None = None


# 한 층의 길찾기 그래프 전체.
class FloorGraphResponse(BaseModel):
    floor: GraphFloorResponse       # 이 그래프가 속한 층
    nodes: list[GraphNodeResponse]  # 정점 목록
    edges: list[GraphEdgeResponse]  # 간선 목록


# 이 그래프가 어느 건물 것인지. 그래프 응답 최상단 식별자.
class GraphBuildingResponse(BaseModel):
    id: str    # 건물 고유 id
    name: str  # 건물 표시 이름


# 건물 전체 길찾기 그래프. 전 층 노드 + 층 내부 간선 + 수직 전이 간선을 한데 담아
# 클라이언트가 층 간 경로까지 온디바이스 다익스트라로 계산하게 한다.
class BuildingGraphResponse(BaseModel):
    building: GraphBuildingResponse  # 이 그래프가 속한 건물
    vertical: str                    # 적용된 수직 이동 정책 (auto/elevator/escalator)
    nodes: list[GraphNodeResponse]   # 전 층 정점 목록 (floor_id로 층 구분)
    edges: list[GraphEdgeResponse]   # 층 내부 + 수직 전이 간선 목록
