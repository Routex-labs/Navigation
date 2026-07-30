# SQLAlchemy Engine, 요청 단위 Session 의존성.

from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import settings

# 커넥션 풀을 들고 있는 무거운 객체라 프로세스 전역 1개만 만든다.
# check_same_thread=False는 SQLite 전용 — 동기 def 핸들러가 anyio 스레드풀에서
# 돌기 때문에, 커넥션을 만든 스레드와 만지는 스레드가 다를 수 있다.
engine = create_engine(
    settings.database_url,
    connect_args={"check_same_thread": False} if settings.database_url.startswith("sqlite") else {},
)


# autoflush=False: 조회 직전 자동 flush를 꺼서 seed가 flush 시점을 직접 제어한다.
# autocommit=False: 명시적으로 commit할 때까지 트랜잭션이 열려 있다.
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)


# 요청마다 Session을 만들고, 예외 시 rollback 후 항상 닫는다.
def get_db() -> Iterator[Session]:
    session = SessionLocal()
    try:
        yield session  # 여기서 핸들러가 실행된다
    except Exception:
        session.rollback()  # 핸들러 밖 예외의 최종 안전망
        raise
    finally:
        session.close()  # 응답 전송이 끝난 뒤 실행된다
