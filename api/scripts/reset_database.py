"""개발 SQLite DB를 ORM 모델 정의 기준으로 삭제 후 재생성하는 CLI.

FastAPI 서버 startup에서는 절대 호출하지 않는다. 개발 초기화는 이 명령으로만 한다.
"""

from app.core.database import engine
import app.models  # noqa: F401  # 모든 모델을 Base.metadata에 등록
from app.models.base import Base


def reset_database() -> None:
    """개발 SQLite DB의 모든 테이블을 삭제하고 ORM 정의대로 다시 생성한다."""
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)


if __name__ == "__main__":
    reset_database()
    print("개발 DB 테이블 재생성 완료")
