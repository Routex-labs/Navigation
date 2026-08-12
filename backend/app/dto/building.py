# 건물 목록/상세 API 응답 모델.

from pydantic import BaseModel

from app.dto.floor_map import LatLngResponse, PointResponse


# 건물 목록 한 줄. 앱이 건물을 고르고 첫 층을 여는 데 필요한 최소 정보다.
class BuildingSummaryResponse(BaseModel):
    id: str  # 건물 고유 id (예: thehyundai-seoul)
    name: str  # 건물 표시 이름

    # 엘리베이터 버튼판 순서(위층 → 아래층). 표시 순서일 뿐 기본 층이 아니다.
    floors: list[str]  # 층 라벨 목록. 내부 id가 아니라 사람이 보는 이름
    # 앱이 처음 열 층. 목록 순서와 분리해 명시한다.
    default_floor: str | None = None  # 출입구가 있는 지상 1층 기준. 층이 없으면 null


# 카테고리 필터가 쓰는 (층·대분류·소분류)별 매장 수 한 줄.
#
# 지도 위 pill 목록과 "이 층 N곳" 안내를 이 응답 하나로 만든다. 층 지도
# (`/floors/{floor}`)를 층마다 받아 세던 것을 대체한다 — 그쪽은 폴리곤·좌표까지
# 실려 있어 개수를 세자고 받기엔 너무 무겁다.
class CategoryCountResponse(BaseModel):
    floor: str  # 층 라벨(예: B2). 층 지도 응답과 같은 표기
    category: str  # 대분류(예: 카페)
    subcategory: str | None  # 소분류(예: 카페·베이커리). 없는 매장이 있어 선택
    count: int  # 그 조합의 매장 수


# 온디바이스 자동완성 인덱스 한 줄.
#
# 앱이 시작할 때 건물당 1회 받아 초성·부분 일치·오타 교정의 원본으로 쓴다
# (설계: docs/client/search-input-assist.md K절). 매장 목록을 주는 응답이
# `/stores`(StoreResponse)와 둘이 된 이유는 목적이 다르기 때문이다 — 그쪽은 층 지도를
# 그리는 응답이라 폴리곤을 local_m·wgs84 두 벌로 싣고, 자동완성은 그 좌표를 한 번도
# 쓰지 않는다. 기존 계약은 그대로 두고 검색 전용 목록을 따로 둔다.
#
# **좌표를 넣지 않는 것이 이 모델의 존재 이유다.** 후보 목록은 이름과 층 라벨만
# 그리므로 중심점이 필요 없고, 후보를 탭한 뒤 필요해지는 좌표는 이미 두 경로로
# 얻는다 — 지도를 열면 어차피 받는 층 지도 응답의 `centroid_local_m`,
# 또는 상세 `/places/{id}`의 `position_local_m`(ETag로 캐시됨). 1건이 필요할 때
# 1건만 가져오는 쪽이 1640건 전부에 좌표를 붙여 매번 내려보내는 것보다 싸다.
# 실측(매장 1640건): 이 응답 341KB에 중심점을 얹으면 +82KB(local_m만)·
# +194KB(wgs84까지)로 최대 1.6배가 된다. 같은 데이터의 `/stores`는 1,229KB다.
class StoreIndexResponse(BaseModel):
    id: str  # 매장 고유 id. 상세(`/places/{id}`) 조회 키
    name: str  # 매장명. 원문 그대로 — 구두점(A.P.C.)을 서버에서 지우지 않는다
    floor_id: str  # 소속 층 id. 층 지도 응답의 StoreResponse.floor_id와 대조하는 키
    floor_name: str  # 사람이 보는 층 라벨(예: B2). 후보 한 줄에 바로 표시한다
    category: str | None  # 대분류(예: 패션), 없는 매장이 있어 선택
    subcategory: str | None  # 소분류(예: 여성패션), 선택
    # 상세와 같은 분류(store·facility·excluded). 이 색인에는 상세를 열지 않는
    # 주차·에스컬레이터·엘리베이터가 61% 섞여 있어, 매장만 골라야 하는 화면이
    # 규칙을 다시 만들지 않도록 서버가 함께 준다.
    kind: str
    entrance_node_id: str | None  # 도착 노드. null이면 그 후보는 길찾기로 이어지지 않는다


# 건물 상세. 목록 응답에 도면을 그리는 데 필요한 값을 더한다.
class BuildingDetailResponse(BuildingSummaryResponse):
    area_m2: float | None  # 건물 바닥 면적 (제곱미터), 선택
    perimeter_m: float | None  # 건물 둘레 (미터), 선택

    footprint_local_m: list[PointResponse]  # 건물 대표 외곽선 (local_m). 기준층 것이라 층별 외곽은 층 지도 응답을 쓴다
    # 야외 지도에서 건물 폴리곤을 그리기 위한 wgs84 외곽선.
    # 실측 wgs84 앵커가 없어 아핀을 만들 수 없으면 None.
    footprint_wgs84: list[LatLngResponse] | None = None

    # 타일 URL에 `?v=`로 붙일 버전 토큰. 시드가 바뀌면 값이 바뀐다.
    # 클라이언트가 이걸 붙이면 서버가 타일에 immutable을 줘서 재검증(304)이
    # 아예 나가지 않는다. 안 붙여도 동작은 같고 캐시 수명만 짧아진다.
    tile_revision: str | None = None
