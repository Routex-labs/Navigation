"""건물/층/그래프/매장 HTTP 엔드포인트.

URL 파라미터, Depends(get_db), response_model, 400/404 변환만 담당한다.
조회는 building_queries가 담당한다. 최단 경로 계산은 클라이언트가 층 지도 응답의
navigation_graph로 온디바이스 다익스트라를 돌리므로 서버에는 두지 않는다.
sqlite3/SQLAlchemy 동기 IO이므로 모든 핸들러는 def(동기)로 선언한다.

경로 목록 (prefix=/buildings):
  GET /buildings                                → 건물 목록
  GET /buildings/{id}                           → 건물 상세 (footprint 포함)
  GET /buildings/{id}/stores?q=검색어           → 매장 검색
  GET /buildings/{id}/floors/{floor}            → 층 지도 데이터 (매장+POI+그래프)
  GET /buildings/{id}/floors/{floor}/graph      → 길찾기 그래프 (nodes+edges)
  GET /buildings/{id}/floors/{floor}/tiles/{z}/{x}/{y}.mvt → 벡터 타일(MVT)
"""

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.repositories import building_queries, tile_queries
from app.dto.building import BuildingDetailResponse, BuildingSummaryResponse
from app.dto.floor_map import FloorMapResponse, StoreResponse
from app.dto.route import FloorGraphResponse

router = APIRouter(prefix="/buildings", tags=["buildings"])


# 전체 건물 목록. footprint 같은 무거운 데이터는 제외한 요약.
@router.get("", response_model=list[BuildingSummaryResponse])
def list_buildings(session: Session = Depends(get_db)):
    return building_queries.list_buildings(session)


# 건물 상세 정보 (면적, 둘레, footprint 폴리곤 포함).
@router.get("/{building_id}", response_model=BuildingDetailResponse)
def get_building(building_id: str, session: Session = Depends(get_db)):
    result = building_queries.get_building(session, building_id)
    if result is None:
        raise HTTPException(status_code=404, detail="Building not found")
    return result


# 건물 내 매장 이름 검색. q 미지정 시 전체 매장 반환.
@router.get("/{building_id}/stores", response_model=list[StoreResponse])
def search_stores(
    building_id: str,
    q: str = "",  # ?q=검색어 쿼리 파라미터. 미지정 시 전체 매장
    session: Session = Depends(get_db),
):
    result = building_queries.search_stores(session, building_id, q)
    if result is None:
        raise HTTPException(status_code=404, detail="Building not found")
    return result


# 층 지도 데이터. Flutter 지도 화면이 footprint/매장 폴리곤/POI를 그리는 데 사용.
@router.get(
    "/{building_id}/floors/{floor_name}",
    response_model=FloorMapResponse,
)
def get_floor_map(
    building_id: str,
    floor_name: str,
    session: Session = Depends(get_db),
):
    result = building_queries.get_floor_map(session, building_id, floor_name)
    if result is None:
        raise HTTPException(status_code=404, detail="Floor not found")
    return result


# 층 지도 벡터 타일(MVT). MapLibre GL의 벡터 타일 소스가 z/x/y로 호출한다.
@router.get("/{building_id}/floors/{floor_name}/tiles/{z}/{x}/{y}.mvt")
def get_floor_tile(
    building_id: str,
    floor_name: str,
    z: int,
    x: int,
    y: int,
    session: Session = Depends(get_db),
):
    try:
        tile_bytes = tile_queries.render_floor_tile(session, building_id, floor_name, z, x, y)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error

    if tile_bytes is None:
        raise HTTPException(status_code=404, detail="Floor not found")

    return Response(content=tile_bytes, media_type="application/vnd.mapbox-vector-tile")


# 층 길찾기 그래프. 클라이언트/서버 경로 탐색의 입력.
@router.get(
    "/{building_id}/floors/{floor_name}/graph",
    response_model=FloorGraphResponse,
)
def get_floor_graph(
    building_id: str,
    floor_name: str,
    session: Session = Depends(get_db),
):
    result = building_queries.get_floor_graph(session, building_id, floor_name)
    if result is None:
        raise HTTPException(status_code=404, detail="Floor not found")
    return result
