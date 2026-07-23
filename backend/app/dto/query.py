"""자연어 질의(/query) 응답 모델.

경량 매칭 결과를 고정된 형태로 직렬화한다. 요청 모델은 routers/query.py에 있다.
값 생성은 repositories/query_search가 하고, 여기서는 계약(나가는 모양)만 선언한다.
"""

from pydantic import BaseModel


# 건물 로컬 평면 좌표 한 점.
class LocalPoint(BaseModel):
    x: float  # 로컬 좌표 X (미터)
    y: float  # 로컬 좌표 Y (미터)


# WGS84 실좌표 한 점.
class LatLng(BaseModel):
    lat: float  # 위도
    lng: float  # 경도


# destination·info가 공유하는 매칭 대상 매장 정보.
class QueryMatch(BaseModel):
    store_id: str  # 매칭된 매장 고유 id
    name: str      # 매장명

    category: str | None     # 카테고리, 선택
    subcategory: str | None  # 세부 카테고리, 선택

    floor_id: str                # 소속 층 내부 id
    floor_name: str              # 사람이 보는 층 라벨(예: B2). Floor.name 조인으로 채운다.

    entrance_node_id: str | None  # 온디바이스 경로의 도착 노드. 없으면 status=ok_no_route.

    centroid_local_m: LocalPoint   # 매장 중심점 (local_m)
    centroid_wgs84: LatLng | None  # 지도 표시용 실좌표. 건물에 wgs84 앵커가 없으면 null.


# 목적지 질의 응답. 최적 매장 1건을 안내 대상으로 준다.
class DestinationResponse(BaseModel):
    status: str              # ok | ok_no_route | no_match
    query: str               # 사용자가 보낸 원문. 화면에 되비추는 용도
    match: QueryMatch | None  # 최적 1건. no_match면 null


# 정보 질의 응답. 대표 1건에 더해 "그게 어느 층들에 있는지"를 함께 준다.
class InfoResponse(BaseModel):
    status: str               # ok | no_match
    query: str                # 사용자가 보낸 원문
    match: QueryMatch | None  # 대표 1건. no_match면 null
    floors: list[str]         # 대상이 존재하는 층 이름들(level 오름차순)
