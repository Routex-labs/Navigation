# SQLAlchemy Engine, 요청 단위 Session 의존성.

from collections.abc import Iterator

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import settings


# SQLite는 연결마다 아래 PRAGMA가 기본값이 아니라, 매 연결에서 명시적으로 켜야 한다.
#   foreign_keys=ON  — FK가 기본은 꺼져 있어, 켜지 않으면 존재하지 않는 노드를 가리키는
#                      간선이나 고아 참조가 그대로 저장된다. 그래프 무결성의 최전선이다.
#   busy_timeout     — 다른 연결이 쓰기 락을 잡고 있을 때 즉시 실패("database is locked")
#                      하지 않고 최대 5초 재시도한다(시드·요청이 겹칠 때 안정성).
#   journal_mode=WAL — 읽기와 쓰기가 서로를 막지 않게 해, reload 중 시드/조회 경합을 줄인다.
#                      파일 DB에만 지속 적용되고 :memory:는 무시된다(그래도 호출은 무해).
# 커넥션 풀이 커넥션을 재사용하므로, 새 연결이 맺어질 때마다(connect 이벤트) 다시 건다.
def enable_sqlite_pragmas(target: Engine) -> None:
    if not target.url.drivername.startswith("sqlite"):
        return

    @event.listens_for(target, "connect")
    def _set_sqlite_pragmas(dbapi_connection, _connection_record):
        cursor = dbapi_connection.cursor()
        try:
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.execute("PRAGMA busy_timeout=5000")
            cursor.execute("PRAGMA journal_mode=WAL")
        finally:
            cursor.close()


# 커넥션 풀을 들고 있는 무거운 객체라 프로세스 전역 1개만 만든다.
# check_same_thread=False는 SQLite 전용 — 동기 def 핸들러가 anyio 스레드풀에서
# 돌기 때문에, 커넥션을 만든 스레드와 만지는 스레드가 다를 수 있다.
engine = create_engine(
    settings.database_url,
    connect_args={"check_same_thread": False} if settings.database_url.startswith("sqlite") else {},
)
enable_sqlite_pragmas(engine)


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
