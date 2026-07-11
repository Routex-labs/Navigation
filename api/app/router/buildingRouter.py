"""
건물/층/그래프/매장 HTTP 엔드포인트

url 과 함수를 연결하고, service 가 None을 줄 경우 404
비즈니스 로직은 전부 BuildingService에 위임
블로킹 IO(sqlite3)에 주의하여 모든 핸들러는 def(동기)로 선언한다.
(async def로 사용할 경우 이벤트 루프가 막혀 서버 전체가 멈춘다.)

경로 목록
(prefix=/buildings):
  GET /buildings                                → 건물 목록
  GET /buildings/{id}                           → 건물 상세 (footprint 포함)
  GET /buildings/{id}/stores?q=검색어           → 매장 검색
  GET /buildings/{id}/floors/{floor}            → 층 지도 데이터 (매장+POI)
  GET /buildings/{id}/floors/{floor}/graph      → 길찾기 그래프 (nodes+edges)
"""
from fastapi import APIRouter, Depends, HTTPException

from app.FastAPIConfig import get_building_service
from app.schema.floor_map import FloorMapResponse
from app.schema.route import FloorGraphResponse, RouteResponse
from app.service.buildingService import BuildingService

# prefix는 아래 모든 경로 앞에 /buildings를 붙이고 tags는 Swagger 그룹을 만든다.
router = APIRouter(prefix="/buildings", tags=["buildings"])


@router.get("")
def list_buildings(service: BuildingService = Depends(get_building_service)):
    """전체 건물 목록. footprint 같은 무거운 데이터는 제외한 요약."""
    # Depends가 요청용 Repository와 Service를 조립해 매개변수로 주입한다.
    return service.get_all_buildings()


@router.get("/{building_id}")
def get_building(
    building_id: str,
    service: BuildingService = Depends(get_building_service),
):
    """건물 상세 정보 (면적, 둘레, footprint 폴리곤 포함)."""
    # Router는 비즈니스 로직 없이 Service 결과를 HTTP 응답 의미로 번역한다.
    result = service.get_building(building_id)
    if result is None:
        # Service의 None을 클라이언트가 이해할 수 있는 HTTP 404로 변환한다.
        raise HTTPException(status_code=404, detail="Building not found")
    return result


@router.get("/{building_id}/stores")
def search_stores(
    building_id: str,
    q: str = "",  # 경로에 없는 단순 타입 → 쿼리 파라미터 (?q=...)
    service: BuildingService = Depends(get_building_service),
):
    """건물 내 매장 이름 검색. q 미지정 시 전체 매장 반환."""
    # q는 FastAPI가 ?q=검색어 쿼리 파라미터에서 자동 바인딩한다.
    result = service.search_stores(building_id, q)
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
    service: BuildingService = Depends(get_building_service),
):
    """층 지도 데이터. Flutter 지도 화면이 footprint/매장 폴리곤/POI를 그리는 데 사용."""
    # building_id와 floor_name은 URL 경로에서 문자열로 바인딩된다.
    result = service.get_floor_map(building_id, floor_name)
    if result is None:
        raise HTTPException(status_code=404, detail="Floor not found")
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
    service: BuildingService = Depends(get_building_service),
):
    try:
        result = service.get_shortest_path(
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
    service: BuildingService = Depends(get_building_service),
):
    """층 길찾기 그래프. 클라이언트/서버 A* 경로 탐색의 입력."""
    # 응답은 계산된 경로가 아니라 해당 층의 전체 Node/Edge 데이터다.
    result = service.get_floor_graph(building_id, floor_name)
    if result is None:
        raise HTTPException(status_code=404, detail="Floor not found")
    return result
