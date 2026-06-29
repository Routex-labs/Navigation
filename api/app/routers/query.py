"""
app/routers/query.py
====================
자연어 질의(RAG) 관련 HTTP 엔드포인트 정의.

역할:
  - Flutter 앱에서 "강의실 101 어디야?" 같은 자연어 질문을 받아 처리
  - 현재는 스텁(stub) 구현 — 실제 RAG 로직은 후속 이슈에서 추가 예정
  - Pydantic 모델로 요청 Body의 형태(스키마)를 강제하여 잘못된 요청 자동 거부

등록된 경로 (prefix=/query):
  POST /query/destination → 목적지 질의 (예: "편의점 어디야?")
  POST /query/info        → 장소 정보 질의 (예: "화장실 몇 층이야?")
"""

from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter(prefix="/query", tags=["query"])


class DestinationRequest(BaseModel):
    """
    POST /query/destination 요청 Body 스키마.
    Flutter가 JSON으로 보내면 FastAPI가 자동으로 이 모델로 파싱·검증.
    예: {"text": "강의실 101", "building_id": "bldg-001"}
    """
    text: str          # 사용자가 입력한 자연어 질문
    building_id: str   # 질문 대상 건물 ID


class InfoRequest(BaseModel):
    """POST /query/info 요청 Body 스키마. DestinationRequest와 동일한 구조."""
    text: str
    building_id: str


@router.post("/destination")
def query_destination(body: DestinationRequest):
    """
    목적지 자연어 질의 처리.
    body.text에 사용자 질문이 들어옴.
    현재는 stub — RAG(sentence-transformers + FAISS) 구현은 후속 이슈.
    """
    return {"status": "stub", "query": body.text, "result": None}


@router.post("/info")
def query_info(body: InfoRequest):
    """
    장소 정보 자연어 질의 처리.
    현재는 stub — RAG 구현은 후속 이슈.
    """
    return {"status": "stub", "query": body.text, "result": None}
