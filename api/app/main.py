"""
FastAPI 애플리케이션 진입점(entry point)

앱 조립은 전부 FastAPIConfig.create_app() 이 담당하고, 이 모듈은 
uvicorn 이 import할 'app'객체만 노출한다.

실행 방법 (api/ 디렉토리에서):
  1) 최초 1회 DB 적재: python scripts/load_dataset.py
  2) 서버 실행:        uvicorn app.main:app --reload
"""
from app.FastAPIConfig import create_app

# uvicorn의 ``app.main:app`` 경로가 참조하는 모듈 전역 ASGI 애플리케이션이다.
# 실제 설정과 라우터 조립은 테스트에서도 재사용할 수 있도록 create_app에 위임한다.
app = create_app()
