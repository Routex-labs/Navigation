"""
FastAPI 애플리케이션 진입점(entry point)

앱 조립은 전부 FastAPIConfig.create_app() 이 담당하고, 이 모듈은 
uvicorn 이 import할 'app'객체만 노출한다.

실행 방법 (api/ 디렉토리에서):
  1) 최초 1회 DB 적재: python scripts/load_dataset.py
  2) 서버 실행:        uvicorn app.main:app --reload
"""
from app.FastAPIConfig import create_app

app = create_app()