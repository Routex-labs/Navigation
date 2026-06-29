"""
app/main.py
===========
FastAPI 애플리케이션의 진입점(entry point).

역할:
  - FastAPI 인스턴스(app)를 생성하고 전체 설정을 한 곳에서 관리
  - CORS 미들웨어 등록 (Flutter 클라이언트가 다른 포트에서 요청할 수 있도록 허용)
  - 기능별로 분리된 라우터(routers/)를 app에 연결
  - /health 엔드포인트 직접 제공 (서버 생존 여부 확인용)

실행 방법:
  uvicorn app.main:app --reload
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import buildings, query

app = FastAPI(title="Navigation API", version="0.1.0")

# 개발 중에는 모든 출처(*) 허용. 운영 배포 시 Flutter 앱 도메인으로 교체 필요
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# 기능별 라우터 연결 (/buildings/*, /query/*)
app.include_router(buildings.router)
app.include_router(query.router)


@app.get("/health", tags=["health"])
def health():
    """서버가 정상 동작 중인지 확인하는 엔드포인트. Flutter가 서버 연결 전 호출."""
    return {"status": "ok"}
