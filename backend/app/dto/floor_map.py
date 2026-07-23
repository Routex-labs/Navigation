# 층 지도 API 응답 모델.

from typing import Literal

from pydantic import BaseModel

from app.dto.route import FloorGraphResponse


# 건물 로컬 평면 좌표 한 점. 단위는 미터이며 원점은 건물마다 다르다.
class PointResponse(BaseModel):
    x: float  # 로컬 좌표 X (미터)
    y: float  # 로컬 좌표 Y (미터)


# WGS84 실좌표 한 점. local_m을 affine 변환해 얻는다.
class LatLngResponse(BaseModel):
    lat: float  # 위도
    lng: float  # 경도


# 층 식별 정보.
class FloorResponse(BaseModel):
    id: str     # 층 고유 id (원천 데이터 내부 식별자, 불투명 — 화면에 노출하지 않는다)
    name: str   # 사람이 보는 사이니지 라벨 (예: B2, 1F). "지하 2층"이 아니다
    level: int  # 정렬용 정수 (지하 음수 B2=-2, 지상 양수 1F=1). 문자열 name은 정렬 불가


# 매장 하나. 화장실·엘리베이터 같은 편의시설도 매장으로 내려간다.
class StoreResponse(BaseModel):
    id: str        # 매장 고유 id
    floor_id: str  # 소속 층 id
    name: str      # 매장명

    category: str | None = None     # 카테고리 (예: 패션·편의시설), 선택
    subcategory: str | None = None  # 세부 카테고리 (예: elevator·restroom), 선택

    centroid_local_m: PointResponse  # 매장 중심점 (local_m)
    # 실측 앵커가 부족하면 합성 좌표 기반 근사치가 채워진다.
    centroid_wgs84: LatLngResponse | None       # 중심점 실좌표. 변환 불가면 null
    polygon_wgs84: list[LatLngResponse] | None  # 외곽 폴리곤 실좌표. 폴리곤이 없으면 null

    entrance_local_m: PointResponse | None       # 입구 좌표 (local_m), 선택
    entrance_node_id: str | None                 # 입구와 이어진 그래프 노드 id. 온디바이스 경로의 도착 노드
    polygon_local_m: list[PointResponse] | None  # 외곽 폴리곤 (local_m), 선택


# 지도 위 마커 하나. 그래프 노드에서 승격된 시설점이다.
class PoiResponse(BaseModel):
    id: str           # POI 고유 id
    type: str         # 종류 (elevator/escalator/toilet/exit 등). 클라이언트가 아이콘을 고르는 키
    name: str | None  # 표시 이름, 선택

    position_local_m: PointResponse        # 마커 위치 (local_m)
    position_wgs84: LatLngResponse | None  # 마커 실좌표. 변환 불가면 null

    linked_node_id: str | None  # 이 마커가 승격된 원본 그래프 노드 id, 선택


# 층 하나를 그리는 데 필요한 전체 묶음. Flutter 지도 화면이 이 응답 하나로 층을 렌더한다.
class FloorMapResponse(BaseModel):
    floor: FloorResponse  # 이 응답이 어떤 층인지

    navigation_coordinate_system: Literal["local_m"]  # 좌표계 표기. 현재 local_m 고정
    map_calibration_version: str  # 지도 보정 버전. 미보정이면 "unversioned"

    footprint_local_m: list[PointResponse]        # 층 외곽선 (local_m). 층 것이 없으면 건물 것으로 폴백
    footprint_wgs84: list[LatLngResponse] | None  # 외곽선 실좌표. 변환 불가면 null

    navigation_graph: FloorGraphResponse  # 길찾기 그래프. 클라이언트가 캐시해 온디바이스 다익스트라에 쓴다

    stores: list[StoreResponse]  # 이 층의 매장 폴리곤
    pois: list[PoiResponse]      # 이 층의 시설 마커
