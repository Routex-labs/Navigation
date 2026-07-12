"""개발 SQLite DB를 ORM 모델 정의 기준으로 삭제 후 재생성하는 CLI.

FastAPI 서버 startup에서는 절대 호출하지 않는다. 개발 초기화는 이 명령으로만 한다.
"""

from pathlib import Path

from app.core.database import engine
import app.models  # noqa: F401  # 모든 모델을 Base.metadata에 등록
from app.models.base import Base


def reset_database() -> None:
    """개발 SQLite DB의 모든 테이블을 삭제하고 ORM 정의대로 다시 생성한다."""
    # SQLite 파일 DB는 부모 디렉터리(data/)가 없으면 파일을 만들지 못한다.
    database = engine.url.database
    if engine.url.drivername.startswith("sqlite") and database and database != ":memory:":
        Path(database).parent.mkdir(parents=True, exist_ok=True)
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)


if __name__ == "__main__":
    reset_database()
    print("개발 DB 테이블 재생성 완료")
