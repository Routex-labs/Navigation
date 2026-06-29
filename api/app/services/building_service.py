"""
app/services/building_service.py
=================================
건물 데이터 처리 비즈니스 로직.

역할:
  - JSON 파일에서 건물 데이터를 읽고 라우터가 필요한 형태로 가공
  - 라우터(routers/)는 "어떤 URL에 응답할지"만 알고,
    실제 데이터 처리는 이 서비스에 위임 → 역할 분리
  - 나중에 DB(PostgreSQL 등)로 교체할 때 이 파일만 수정하면 됨 (라우터 코드 무변경)

현재 데이터 소스:
  app/data/sample_building.json (데모용 건물 1개 + 2개 층 GeoJSON)
"""

import json
from pathlib import Path

# __file__: 이 파일(building_service.py)의 절대 경로
# .parent: services/ 폴더
# .parent.parent: app/ 폴더
# / "data": app/data/ 폴더 → 실행 위치가 달라도 항상 올바른 경로 참조
_DATA_DIR = Path(__file__).parent.parent / "data"


def _load_building() -> dict:
    """JSON 파일을 읽어 Python dict로 변환. 앞의 _ 는 이 모듈 내부에서만 쓰는 함수 관례."""
    with open(_DATA_DIR / "sample_building.json", encoding="utf-8") as f:
        return json.load(f)


def get_all_buildings() -> list[dict]:
    """
    전체 건물 목록 반환.
    floor_data(층별 GeoJSON)는 용량이 크므로 목록에서 제외하고 요약 필드만 반환.
    """
    b = _load_building()
    return [{"id": b["id"], "name": b["name"], "floors": b["floors"]}]


def get_building(building_id: str) -> dict | None:
    """
    building_id가 일치하는 건물 반환. 없으면 None.
    라우터에서 None을 받으면 HTTP 404로 변환.
    """
    b = _load_building()
    if b["id"] != building_id:
        return None
    return {"id": b["id"], "name": b["name"], "floors": b["floors"]}


def get_floor_geojson(building_id: str, floor: int) -> dict | None:
    """
    특정 건물의 특정 층 GeoJSON 반환. 건물이나 층이 없으면 None.
    floor는 int로 받지만 JSON 키는 문자열이므로 str(floor)로 변환 후 조회.
    """
    b = _load_building()
    if b["id"] != building_id:
        return None
    return b["floor_data"].get(str(floor))  # str() 변환: JSON 키는 항상 문자열
