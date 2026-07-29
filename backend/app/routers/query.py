# 자연어 질의 HTTP 엔드포인트.
# 경량 매칭 구현 — 매장 이름·카테고리·동의어로 목적지/정보를 찾는다.
# /query/ai는 경량 1차가 놓쳤거나 모호한 부분 일치를 FAISS 의미 검색 2차로 보완한다.
# URL·요청 Body 검증, Depends(get_db), response_model, 404 변환만 담당한다.
# 실제 매칭은 repositories/query_search가 담당한다. sqlite 동기 IO라 핸들러는 def.
# 경로 목록 (prefix=/query):
#   POST /query/destination → 목적지 매장 1건 + 입구 노드
#   POST /query/ai          → 탐색 결과(mode + 질문/선택지 + 여러 후보)
#   POST /query/info        → 대상 정보 + 존재하는 층 목록

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from pydantic import AfterValidator, BaseModel, Field
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.dto.query import DestinationResponse, DiscoveryResponse, InfoResponse
from app.repositories import query_search

# /query 아래의 자연어 질의 엔드포인트를 Swagger에서 query 그룹으로 묶는다.
router = APIRouter(prefix="/query", tags=["query"])


def _reject_blank_text(value: str) -> str:
    """공백만 있는 질의는 빈 문자열과 같은 422로 막되 원문 자체는 보존한다."""
    if not value.strip():
        raise ValueError("text must contain non-whitespace characters")
    return value


QueryText = Annotated[
    str,
    Field(min_length=1, max_length=query_search.MAX_QUERY_LENGTH),
    AfterValidator(_reject_blank_text),
]


# POST /query/destination 요청 Body. 예: {"text": "MLB", "building_id": "thehyundai-seoul"}
# current_floor_id는 층 라벨("B2")·내부 id 모두 받는다(근거: query_search._load_stores).
class DestinationRequest(BaseModel):
    text: QueryText
    building_id: str
    current_floor_id: str | None = None


# POST /query/info 요청 Body. DestinationRequest와 동일 구조.
class InfoRequest(BaseModel):
    text: QueryText
    building_id: str
    current_floor_id: str | None = None


# POST /query/ai 요청 Body. 탐색(Discovery) 전용 — destination과 계약이 다르다.
# selected_facets는 사용자가 clarify 질문에서 고른 값이다. 서버 대화 세션을 만들지 않고
# 클라이언트가 매 요청에 원문과 현재 선택을 다시 보내는 stateless 계약이다(8-2절).
# 예: {"text": "신발", "building_id": "thehyundai-seoul", "selected_facets": {"styles": ["스포츠"]}}
class AiRequest(BaseModel):
    text: QueryText
    building_id: str
    current_floor_id: str | None = None
    selected_facets: dict[str, list[str]] | None = None


# 목적지 자연어 질의. 최적 매장 1건과 입구 노드를 반환한다.
@router.post("/destination", response_model=DestinationResponse)
def query_destination(body: DestinationRequest, session: Session = Depends(get_db)):
    result = query_search.match_destination(
        session,
        body.building_id,
        body.text,
        current_floor_id=body.current_floor_id,
    )
    if result is None:
        raise HTTPException(status_code=404, detail="Building not found")
    return result


# AI 자연어 탐색 질의. 명확한 목적지는 바로 1건(direct), 넓은 질의는 되묻거나(clarify)
# 다양성 보정된 여러 후보(results)를 준다. 응답 계약은 destination과 다르다(DiscoveryResponse).
# 설계: docs/backend/native/conversational-discovery.md 8절.
@router.post("/ai", response_model=DiscoveryResponse)
def query_ai(body: AiRequest, session: Session = Depends(get_db)):
    result = query_search.discover(
        session,
        body.building_id,
        body.text,
        current_floor_id=body.current_floor_id,
        selected_facets=body.selected_facets,
    )
    if result is None:
        raise HTTPException(status_code=404, detail="Building not found")
    return result


# 장소 정보 자연어 질의. 대상 정보와 존재하는 층 목록을 반환한다.
@router.post("/info", response_model=InfoResponse)
def query_info(body: InfoRequest, session: Session = Depends(get_db)):
    result = query_search.match_info(
        session,
        body.building_id,
        body.text,
        current_floor_id=body.current_floor_id,
    )
    if result is None:
        raise HTTPException(status_code=404, detail="Building not found")
    return result
