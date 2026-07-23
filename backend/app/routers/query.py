# 자연어 질의 HTTP 엔드포인트.
# 경량 매칭 구현 — 매장 이름·카테고리·동의어로 목적지/정보를 찾는다.
# (의미 검색 RAG는 후속. docs/backend/native/query.md 참고.)
# URL·요청 Body 검증, Depends(get_db), response_model, 404 변환만 담당한다.
# 실제 매칭은 repositories/query_search가 담당한다. sqlite 동기 IO라 핸들러는 def.
# 경로 목록 (prefix=/query):
#   POST /query/destination → 목적지 매장 1건 + 입구 노드
#   POST /query/info        → 대상 정보 + 존재하는 층 목록

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.dto.query import DestinationResponse, InfoResponse
from app.repositories import query_search

# /query 아래의 자연어 질의 엔드포인트를 Swagger에서 query 그룹으로 묶는다.
router = APIRouter(prefix="/query", tags=["query"])


# POST /query/destination 요청 Body. 예: {"text": "MLB", "building_id": "thehyundai-seoul"}
# current_floor_id는 층 라벨("B2")·내부 id 모두 받는다(근거: query_search._load_stores).
class DestinationRequest(BaseModel):
    text: str = Field(min_length=1)  # 빈 문자열은 422
    building_id: str
    current_floor_id: str | None = None


# POST /query/info 요청 Body. DestinationRequest와 동일 구조.
class InfoRequest(BaseModel):
    text: str = Field(min_length=1)
    building_id: str
    current_floor_id: str | None = None


# POST /query/ai 요청 Body. AI 쿼리 버튼 전용(자연어). destination과 동일 구조.
class AiRequest(BaseModel):
    text: str = Field(min_length=1)  # 빈 문자열은 422
    building_id: str
    current_floor_id: str | None = None


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


# AI 자연어 질의(하이브리드). 경량 매칭이 놓친 자연어를 임베딩 의미 검색으로 보완한다.
# 응답은 destination과 동일 계약. 상단 일반 검색이 아니라 "AI 쿼리" 버튼에서 사용.
@router.post("/ai", response_model=DestinationResponse)
def query_ai(body: AiRequest, session: Session = Depends(get_db)):
    result = query_search.match_ai_destination(
        session,
        body.building_id,
        body.text,
        current_floor_id=body.current_floor_id,
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
