"""자연어 질의(/query) 응답 모델.

경량 매칭 결과를 고정된 형태로 직렬화한다. 요청 모델은 routers/query.py에 있다.
값 생성은 repositories/query_search가 하고, 여기서는 계약(나가는 모양)만 선언한다.
"""

from pydantic import BaseModel, Field


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
    name: str  # 매장명

    category: str | None  # 카테고리, 선택
    subcategory: str | None  # 세부 카테고리, 선택

    floor_id: str  # 소속 층 내부 id
    floor_name: str  # 사람이 보는 층 라벨(예: B2). Floor.name 조인으로 채운다.

    entrance_node_id: str | None  # 온디바이스 경로의 도착 노드. 없으면 status=ok_no_route.

    centroid_local_m: LocalPoint  # 매장 중심점 (local_m)
    centroid_wgs84: LatLng | None  # 지도 표시용 실좌표. 건물에 wgs84 앵커가 없으면 null.


# 목적지 질의 응답. 최적 매장 1건을 안내 대상으로 준다.
class DestinationResponse(BaseModel):
    status: str  # ok | ok_no_route | no_match | ambiguous
    query: str  # 사용자가 보낸 원문. 화면에 되비추는 용도
    match: QueryMatch | None  # 최적 1건. no_match면 null


# 정보 질의 응답. 대표 1건에 더해 "그게 어느 층들에 있는지"를 함께 준다.
class InfoResponse(BaseModel):
    status: str  # ok | no_match
    query: str  # 사용자가 보낸 원문
    match: QueryMatch | None  # 대표 1건. no_match면 null
    floors: list[str]  # 대상이 존재하는 층 이름들(level 오름차순)


# --- 탐색(Discovery) 계약 — POST /query/ai ---
# 설계: docs/backend/native/conversational-discovery.md 8-2·8-3절.
# destination(단일 목적지)과 달리 "여러 후보 + 되물음"을 표현한다.


# clarify 질문의 선택지 하나. 실제 후보가 있는 값만 만든다(빈 chip 금지, 4-3절).
class DiscoveryOption(BaseModel):
    facet: str  # 축 이름(styles·cuisines·...). 클라이언트가 selected_facets 키로 되돌려 보낸다
    value: str  # 축의 값(vocabulary에 선언된 값). 되돌려 보낼 실제 값
    label: str  # 화면 표시용 라벨. 현재는 value와 같지만 계약을 분리해 둔다
    count: int  # 이 값을 가진 현재 후보 수


# 추천 매장 1건. QueryMatch(목적지 계약)에 추천 근거만 덧붙인다.
class DiscoveryMatch(QueryMatch):
    # 이번 질문/선택과 실제로 일치한 검증 태그만 담는다. 원본 facet 전체를 보내지 않는다(2절·8-3절).
    matched_facets: dict[str, list[str]] = Field(default_factory=dict)
    # matched_facets에서만 템플릿으로 조립한 추천 이유. 근거 태그가 없으면 null(추측 금지, 2절).
    reason: str | None = None


# 탐색 질의 응답. mode가 화면 분기의 유일한 근거다.
class DiscoveryResponse(BaseModel):
    # direct   : 명확한 목적지 1건 — matches 1건, 질문 없음
    # clarify  : 후보가 넓고 구분력 있는 축이 있음 — question + options + 초기 후보 3건
    # results  : 충분히 좁혀졌거나 되물을 축이 없음 — 다양성 보정된 최대 5건
    # no_match : 후보 없음
    # degraded : 의미 검색 기능 자체를 못 쓰는 상태(모델·인덱스 미가용). 경량 결과가 있으면 함께 담는다
    mode: str
    query: str  # 사용자가 보낸 원문. 화면에 되비추는 용도
    question: str | None = None  # clarify일 때만. 7-3절 템플릿에서 고른다
    options: list[DiscoveryOption] = Field(default_factory=list)  # clarify일 때만 채워진다
    matches: list[DiscoveryMatch] = Field(default_factory=list)
