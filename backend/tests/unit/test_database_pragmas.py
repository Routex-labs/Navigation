"""SQLite 연결 PRAGMA 적용 검증.

검증 기준:
    무결성 PRAGMA(foreign_keys/busy_timeout/journal_mode)가 연결 시점에 걸린다.
    특히 foreign_keys=ON이 아니면 고아 참조 간선이 그대로 저장되므로, 이 한 줄이
    그래프 무결성의 최전선이다.
"""

from __future__ import annotations

from sqlalchemy import create_engine, text

from app.core.database import enable_sqlite_pragmas


def _engine(tmp_path):
    engine = create_engine(f"sqlite:///{(tmp_path / 'pragma.db').as_posix()}")
    enable_sqlite_pragmas(engine)
    return engine


def test_연결에_foreign_keys가_켜진다(tmp_path):
    engine = _engine(tmp_path)
    try:
        with engine.connect() as conn:
            assert conn.execute(text("PRAGMA foreign_keys")).scalar() == 1
    finally:
        engine.dispose()


def test_연결에_busy_timeout이_설정된다(tmp_path):
    engine = _engine(tmp_path)
    try:
        with engine.connect() as conn:
            assert conn.execute(text("PRAGMA busy_timeout")).scalar() == 5000
    finally:
        engine.dispose()


def test_파일_DB는_WAL_저널모드가_된다(tmp_path):
    engine = _engine(tmp_path)
    try:
        with engine.connect() as conn:
            assert conn.execute(text("PRAGMA journal_mode")).scalar() == "wal"
    finally:
        engine.dispose()


def test_풀에서_재사용된_연결도_PRAGMA가_유지된다(tmp_path):
    # 커넥션 풀이 연결을 돌려쓸 때도 connect 이벤트로 매번 다시 걸려 있어야 한다.
    engine = _engine(tmp_path)
    try:
        for _ in range(3):
            with engine.connect() as conn:
                assert conn.execute(text("PRAGMA foreign_keys")).scalar() == 1
    finally:
        engine.dispose()
