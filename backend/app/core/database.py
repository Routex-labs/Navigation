# SQLAlchemy Engine, 요청 단위 Session 의존성.

from collections.abc import Iterator
from datetime import datetime
from pathlib import Path

from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import API_ROOT, settings


# 커넥션 풀을 들고 있는 무거운 객체라 프로세스 전역 1개만 만든다.
# check_same_thread=False는 SQLite 전용 — 동기 def 핸들러가 anyio 스레드풀에서
# 돌기 때문에, 커넥션을 만든 스레드와 만지는 스레드가 다를 수 있다.
engine = create_engine(
    settings.database_url,
    connect_args={"check_same_thread": False}
    if settings.database_url.startswith("sqlite")
    else {},
)


def _mask_sql_parameters(parameters: object) -> object:
    """로그에 비밀값이 섞여도 원문이 남지 않게 한다."""
    secret_markers = ("password", "secret", "token", "apikey", "api_key", "authorization")

    # dict·list 안쪽까지 재귀로 훑는다.
    if isinstance(parameters, dict):
        return {
            key: "***" if any(marker in key.lower() for marker in secret_markers)
            else _mask_sql_parameters(value)
            for key, value in parameters.items()
        }
    if isinstance(parameters, (list, tuple)):
        return type(parameters)(_mask_sql_parameters(value) for value in parameters)
    return parameters


def _write_sql(statement: str, parameters: object) -> None:
    # VS Code에서 백엔드 app 아래에 바로 보이도록 소스 패키지 기준으로 저장한다.
    log_dir = API_ROOT / "app" / "sql"

    try:
        log_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().astimezone().isoformat(timespec="milliseconds")
        with (log_dir / "queries.sql").open("a", encoding="utf-8") as log_file:
            log_file.write(f"-- {timestamp}\n{statement}\n-- parameters: {_mask_sql_parameters(parameters)!r}\n\n")
    except OSError as error:
        # 진단 로그 쓰기 실패가 시드·API·트랜잭션을 중단시키면 안 된다.
        print(f"SQL 진단 로그를 저장하지 못했습니다: {error}")


# SQL 진단은 개발 실행에서만 켠다(NAV_SQL_ECHO). 실행 직전 훅으로 원문과 파라미터를 남긴다.
if settings.sql_echo:
    @event.listens_for(engine, "before_cursor_execute")
    def _capture_sql(
        _connection: object,
        _cursor: object,
        statement: str,
        parameters: object,
        _context: object,
        _executemany: bool,
    ) -> None:
        _write_sql(statement, parameters)


# autoflush=False: 조회 직전 자동 flush를 꺼서 seed가 flush 시점을 직접 제어한다.
# autocommit=False: 명시적으로 commit할 때까지 트랜잭션이 열려 있다.
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)


# 요청마다 Session을 만들고, 예외 시 rollback 후 항상 닫는다.
def get_db() -> Iterator[Session]:
    session = SessionLocal()
    try:
        yield session       # 여기서 핸들러가 실행된다
    except Exception:
        session.rollback()  # 핸들러 밖 예외의 최종 안전망
        raise
    finally:
        session.close()     # 응답 전송이 끝난 뒤 실행된다
