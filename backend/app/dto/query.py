"""자연어 질의(/query) 응답 모델.

경량 매칭 결과를 고정된 형태로 직렬화한다. 요청 모델은 routers/query.py에 있다.
값 생성은 repositories/query_search가 하고, 여기서는 계약(나가는 모양)만 선언한다.
"""

from pydantic import BaseModel


class LocalPoint(BaseModel):
    x: float
    y: float


class LatLng(BaseModel):
    lat: float
    lng: float


# destination·info가 공유하는 매칭 대상 매장 정보.
class QueryMatch(BaseModel):
    store_id: str
    name: str
    category: str | None
    subcategory: str | None
    floor_id: str
    floor_name: str                 # 사람이 보는 층 라벨(예: B2). Floor.name 조인으로 채운다.
    entrance_node_id: str | None    # 온디바이스 경로의 도착 노드. 없으면 status=ok_no_route.
    centroid_local_m: LocalPoint
    centroid_wgs84: LatLng | None   # 지도 표시용 실좌표. 건물에 wgs84 앵커가 없으면 null.


class DestinationResponse(BaseModel):
    status: str                     # ok | ok_no_route | no_match
    query: str
    match: QueryMatch | None


class InfoResponse(BaseModel):
    status: str                     # ok | no_match
    query: str
    match: QueryMatch | None
    floors: list[str]               # 대상이 존재하는 층 이름들(level 오름차순)
