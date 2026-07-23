# 건물 목록/상세 API 응답 모델.

from pydantic import BaseModel

from app.dto.floor_map import PointResponse


# 건물 목록 한 줄. 앱이 건물을 고르고 첫 층을 여는 데 필요한 최소 정보다.
class BuildingSummaryResponse(BaseModel):
    id: str    # 건물 고유 id (예: thehyundai-seoul)
    name: str  # 건물 표시 이름

    # 엘리베이터 버튼판 순서(위층 → 아래층). 표시 순서일 뿐 기본 층이 아니다.
    floors: list[str]  # 층 라벨 목록. 내부 id가 아니라 사람이 보는 이름
    # 앱이 처음 열 층. 목록 순서와 분리해 명시한다.
    default_floor: str | None = None  # 출입구가 있는 지상 1층 기준. 층이 없으면 null


# 건물 상세. 목록 응답에 도면을 그리는 데 필요한 값을 더한다.
class BuildingDetailResponse(BuildingSummaryResponse):
    area_m2: float | None      # 건물 바닥 면적 (제곱미터), 선택
    perimeter_m: float | None  # 건물 둘레 (미터), 선택

    footprint_local_m: list[PointResponse]  # 건물 대표 외곽선 (local_m). 기준층 것이라 층별 외곽은 층 지도 응답을 쓴다
