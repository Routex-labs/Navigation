# 건물 목록/상세 API 응답 모델.

from pydantic import BaseModel

from app.dto.floor_map import PointResponse


class BuildingSummaryResponse(BaseModel):
    id: str
    name: str
    floors: list[str]


class BuildingDetailResponse(BuildingSummaryResponse):
    area_m2: float | None
    perimeter_m: float | None
    footprint_local_m: list[PointResponse]
