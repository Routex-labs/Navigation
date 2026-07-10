"""
자연어 질의(RAG) 관련 HTTP 엔드포인트

현재는 스텁(stub) — 실제 RAG 로직(sentence-transformers + FAISS)은 후속 이슈.
Pydantic 모델로 요청 Body 스키마를 강제한다.

경로 목록 (prefix=/query):
  POST /query/destination → 목적지 질의 (예: "편의점 어디야?")
  POST /query/info        → 장소 정보 질의 (예: "화장실 몇 층이야?")
"""

from fastapi import APIRouter
from pydantic import BaseModel

# /query 아래의 자연어 질의 엔드포인트를 Swagger에서 query 그룹으로 묶는다.
router = APIRouter(prefix="/query", tags=["query"])


class DestinationRequest(BaseModel):
    """POST /query/destination 요청 Body. 예: {"text": "구찌", "building_id": "thehyundai-seoul"}"""

    # FastAPI가 요청 JSON을 이 필드 구조로 파싱하고 타입을 검증한다.
    text: str
    building_id: str


class InfoRequest(BaseModel):
    """POST /query/info 요청 Body. DestinationRequest와 동일 구조."""

    text: str
    building_id: str


@router.post("/destination")
def query_destination(body: DestinationRequest):
    """목적지 자연어 질의 처리. 현재는 stub."""
    # 후속 RAG 구현 전까지 요청이 정상 수신됐다는 형태만 반환한다.
    return {"status": "stub", "query": body.text, "result": None}


@router.post("/info")
def query_info(body: InfoRequest):
    """장소 정보 자연어 질의 처리. 현재는 stub."""
    # 목적지 검색과 정보 질의를 분리해 향후 서로 다른 검색 로직을 연결할 수 있다.
    return {"status": "stub", "query": body.text, "result": None}
