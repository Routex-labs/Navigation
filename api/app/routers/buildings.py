"""건물/층/그래프/매장 HTTP 엔드포인트.

URL 파라미터, Depends(get_db), response_model, 400/404 변환만 담당한다.
단순 조회는 building_queries, 최단 경로만 NavigationService를 사용한다.
sqlite3/SQLAlchemy 동기 IO이므로 모든 핸들러는 def(동기)로 선언한다.

경로 목록 (prefix=/buildings):
  GET /buildings                                → 건물 목록
  GET /buildings/{id}                           → 건물 상세 (footprint 포함)
  GET /buildings/{id}/stores?q=검색어           → 매장 검색
  GET /buildings/{id}/floors/{floor}            → 층 지도 데이터 (매장+POI)
  GET /buildings/{id}/floors/{floor}/graph      → 길찾기 그래프 (nodes+edges)
  GET /buildings/{id}/floors/{floor}/route      → 최단 경로
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.queries import building_queries
from app.schemas.building import BuildingDetailResponse, BuildingSummaryResponse
from app.schemas.floor_map import FloorMapResponse, StoreResponse
from app.schemas.route import FloorGraphResponse, RouteResponse
from app.services.navigation_service import NavigationService

router = APIRouter(prefix="/buildings", tags=["buildings"])


@router.get("", response_model=list[BuildingSummaryResponse])
def list_buildings(session: Session = Depends(get_db)):
    """전체 건물 목록. footprint 같은 무거운 데이터는 제외한 요약."""
    return building_queries.list_buildings(session)


@router.get("/{building_id}", response_model=BuildingDetailResponse)
def get_building(building_id: str, session: Session = Depends(get_db)):
    """건물 상세 정보 (면적, 둘레, footprint 폴리곤 포함)."""
    result = building_queries.get_building(session, building_id)
    if result is None:
        raise HTTPException(status_code=404, detail="Building not found")
    return result


@router.get("/{building_id}/stores", response_model=list[StoreResponse])
def search_stores(
    building_id: str,
    q: str = "",  # ?q=검색어 쿼리 파라미터. 미지정 시 전체 매장
    session: Session = Depends(get_db),
):
    """건물 내 매장 이름 검색. q 미지정 시 전체 매장 반환."""
    result = building_queries.search_stores(session, building_id, q)
    if result is None:
        raise HTTPException(status_code=404, detail="Building not found")
    return result


@router.get(
    "/{building_id}/floors/{floor_name}",
    response_model=FloorMapResponse,
)
def get_floor_map(
    building_id: str,
    floor_name: str,
    session: Session = Depends(get_db),
):
    """층 지도 데이터. Flutter 지도 화면이 footprint/매장 폴리곤/POI를 그리는 데 사용."""
    result = building_queries.get_floor_map(session, building_id, floor_name)
    if result is None:
        raise HTTPException(status_code=404, detail="Floor not found")
    return result


@router.get("/{building_id}/route", response_model=RouteResponse)
def get_building_route(
    building_id: str,
    start_node_id: str,
    end_node_id: str,
    session: Session = Depends(get_db),
):
    """건물 전체에서 층을 넘나드는 최단 경로(엘리베이터·에스컬레이터 환승 포함)."""
    try:
        result = NavigationService(session).get_building_shortest_path(
            building_id=building_id,
            start_node_id=start_node_id,
            end_node_id=end_node_id,
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error

    if result is None:
        raise HTTPException(status_code=404, detail="Building not found")
    if not result["path_found"]:
        raise HTTPException(status_code=404, detail="Route not found")
    return result


@router.get(
    "/{building_id}/floors/{floor_name}/route",
    response_model=RouteResponse,
)
def get_shortest_route(
    building_id: str,
    floor_name: str,
    start_node_id: str,
    end_node_id: str,
    session: Session = Depends(get_db),
):
    """두 노드 사이의 최단 경로. 계산 규칙은 NavigationService에 있다."""
    try:
        result = NavigationService(session).get_shortest_path(
            building_id=building_id,
            floor_name=floor_name,
            start_node_id=start_node_id,
            end_node_id=end_node_id,
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error

    if result is None:
        raise HTTPException(status_code=404, detail="Floor not found")

    if not result["path_found"]:
        raise HTTPException(status_code=404, detail="Route not found")

    return result


@router.get(
    "/{building_id}/floors/{floor_name}/graph",
    response_model=FloorGraphResponse,
)
def get_floor_graph(
    building_id: str,
    floor_name: str,
    session: Session = Depends(get_db),
):
    """층 길찾기 그래프. 클라이언트/서버 경로 탐색의 입력."""
    result = building_queries.get_floor_graph(session, building_id, floor_name)
    if result is None:
        raise HTTPException(status_code=404, detail="Floor not found")
    return result
