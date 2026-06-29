"""
app/schemas/building.py
========================
API 응답/요청 데이터 구조(스키마) 정의.

역할:
  - Pydantic 모델로 데이터 형태를 선언 → FastAPI가 자동으로 타입 검증 및 JSON 직렬화
  - Swagger(/docs)에서 자동으로 모델 구조를 문서화
  - 잘못된 형태의 데이터가 들어오면 FastAPI가 422 에러로 자동 거부

모델 구조:
  POI      → 관심 지점 (강의실, 화장실, 편의점 등 지도에 표시될 위치)
  Floor    → 층 정보 (층 번호 + GeoJSON 평면도)
  Building → 건물 기본 정보 (ID, 이름, 보유 층 목록)
"""

from pydantic import BaseModel
from typing import Any


class POI(BaseModel):
    """
    관심 지점(Point of Interest) 스키마.
    GeoJSON Feature 형태로 지도에 핀을 꽂는 데 사용.
    """
    id: str                        # 고유 식별자 (예: "poi-101")
    name: str                      # 표시 이름 (예: "강의실 101")
    type: str                      # 분류 (예: "classroom", "restroom", "store")
    geometry: dict[str, Any]       # GeoJSON geometry (Point, Polygon 등)
    properties: dict[str, Any] = {}  # 추가 속성 (기본값: 빈 dict)


class Floor(BaseModel):
    """층 정보 스키마. flutter_map이 이 GeoJSON을 받아 평면도를 렌더링."""
    floor: int                # 층 번호 (예: 1, 2, -1)
    geojson: dict[str, Any]  # GeoJSON FeatureCollection (corridor + poi 포함)


class Building(BaseModel):
    """건물 기본 정보 스키마. 목록 조회 시 응답으로 사용."""
    id: str          # 고유 식별자 (예: "bldg-001")
    name: str        # 건물 이름 (예: "데모 건물")
    floors: list[int]  # 보유 층 번호 목록 (예: [1, 2, 3])
