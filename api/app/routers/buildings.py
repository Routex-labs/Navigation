"""
app/routers/buildings.py
========================
건물(Building) 관련 HTTP 엔드포인트 정의.

역할:
  - URL 경로와 함수를 연결 (어떤 URL 요청을 어떤 함수로 처리할지 결정)
  - 요청 파라미터를 추출해 service에 전달
  - service가 None을 반환하면 HTTP 404 에러로 변환
  - 실제 데이터 처리 로직은 building_service에 위임 (역할 분리)

등록된 경로 (prefix=/buildings):
  GET /buildings              → 전체 건물 목록
  GET /buildings/{id}         → 특정 건물 상세 정보
  GET /buildings/{id}/floors/{floor} → 특정 층 GeoJSON
"""

from fastapi import APIRouter, HTTPException
from app.services import building_service

# prefix: 이 라우터의 모든 경로 앞에 /buildings 자동 삽입
# tags: Swagger(/docs) UI에서 묶어서 표시할 그룹 이름
router = APIRouter(prefix="/buildings", tags=["buildings"])


@router.get("")
def list_buildings():
    """전체 건물 목록 반환. floor_data 같은 무거운 데이터는 제외하고 요약 정보만 응답."""
    return building_service.get_all_buildings()


@router.get("/{building_id}")
def get_building(building_id: str):
    """
    building_id에 해당하는 건물 상세 정보 반환.
    경로의 {building_id} 부분이 자동으로 함수 파라미터로 바인딩됨.
    """
    result = building_service.get_building(building_id)
    if result is None:
        # service가 None → 해당 ID의 건물이 없음 → 404 응답
        raise HTTPException(status_code=404, detail="Building not found")
    return result


@router.get("/{building_id}/floors/{floor}")
def get_floor(building_id: str, floor: int):
    """
    특정 건물의 특정 층 GeoJSON 반환.
    Flutter의 지도 화면에서 평면도를 그리는 데 사용.
    """
    result = building_service.get_floor_geojson(building_id, floor)
    if result is None:
        raise HTTPException(status_code=404, detail="Floor not found")
    return result
