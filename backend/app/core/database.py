# SQLAlchemy Engine, 요청 단위 Session 의존성.

from collections.abc import Iterator
from datetime import datetime
from pathlib import Path

from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import API_ROOT, settings


engine = create_engine(
    settings.database_url,
    connect_args={"check_same_thread": False}
    if settings.database_url.startswith("sqlite")
    else {},
)


def _mask_sql_parameters(parameters: object) -> object:
    """로그에 비밀값이 섞여도 원문이 남지 않게 한다."""
    secret_markers = ("password", "secret", "token", "apikey", "api_key", "authorization")
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
    # backend/가 아닌 저장소 루트에 두어 개발자가 PowerShell에서 바로 확인한다.
    log_root = API_ROOT.parent if API_ROOT.name == "backend" else API_ROOT
    log_dir = log_root / "sql"
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().astimezone().isoformat(timespec="milliseconds")
        with (log_dir / "queries.sql").open("a", encoding="utf-8") as log_file:
            log_file.write(f"-- {timestamp}\n{statement}\n-- parameters: {_mask_sql_parameters(parameters)!r}\n\n")
    except OSError as error:
        # 진단 로그 쓰기 실패가 시드·API·트랜잭션을 중단시키면 안 된다.
        print(f"SQL 진단 로그를 저장하지 못했습니다: {error}")


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

SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)


# 요청마다 Session을 만들고, 예외 시 rollback 후 항상 닫는다.
def get_db() -> Iterator[Session]:
    session = SessionLocal()
    try:
        yield session
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
