# `app/core` — 애플리케이션 설정과 DB 연결

앱 전체가 공유하는 **인프라 기반**을 제공한다. 두 가지뿐이다.

1. **설정값**을 환경변수에서 읽어 한곳에 모은다 (`config.py`)
2. **DB 엔진과 요청 단위 Session**을 만든다 (`database.py`)

비즈니스 규칙(경로 탐색, 좌표 변환)이나 HTTP 처리는 여기에 없다. "DB에 어떻게 붙는가"만 담당한다.

> Spring 대응: `application.yml`(설정) + `DataSource`/`EntityManagerFactory`(연결) 자리.

---

## 구성 파일

| 파일 | 역할 | 핵심 심볼 |
|---|---|---|
| `config.py` | 환경변수 → 설정 객체 | `settings`, `Settings`, `DEFAULT_DATABASE_URL` |
| `database.py` | 엔진·세션·요청 의존성 | `engine`, `SessionLocal`, `get_db()` |
| `__init__.py` | 패키지 표식 | — |

---

## `config.py` — 설정

```python
API_ROOT = Path(__file__).resolve().parents[2]          # backend/
DEFAULT_DATABASE_URL = f"sqlite:///{(API_ROOT / 'data' / 'navigation.db').as_posix()}"


class Settings(BaseSettings):
    database_url: str = DEFAULT_DATABASE_URL
    model_config = SettingsConfigDict(env_prefix="NAV_", case_sensitive=False)


settings = Settings()   # import 시 1회 생성, 프로세스 전역 재사용
```

- **`settings`는 모듈 전역 싱글턴이다.** 다른 모듈은 `from app.core.config import settings`로 가져다 쓴다.
- **환경변수 접두사는 `NAV_`.** `database_url` 필드는 환경변수 `NAV_DATABASE_URL`로 덮어쓴다 (`case_sensitive=False`라 대소문자 무관).
- **기본 DB는 `backend/data/navigation.db`** (SQLite 파일). `API_ROOT`는 이 파일(`app/core/config.py`) 기준 두 단계 위 = `backend/`.
  - `parents[0]=core`, `parents[1]=app`, `parents[2]=backend`.
  - ⚠️ 이 파일을 다른 깊이로 옮기면 `parents[2]`도 같이 고쳐야 한다.

### DB 위치/종류 바꾸기

코드 수정 없이 환경변수로:

```bash
# 다른 파일 경로
NAV_DATABASE_URL="sqlite:///C:/tmp/nav.db"
# 인메모리(테스트 등)
NAV_DATABASE_URL="sqlite://"
# 다른 DBMS (드라이버 설치 필요)
NAV_DATABASE_URL="postgresql+psycopg://user:pw@host/db"
```

Docker Compose는 `NAV_DATABASE_URL: sqlite:////app/data/navigation.db`를 주입한다.

---

## `database.py` — 엔진과 Session

```python
engine = create_engine(
    settings.database_url,
    connect_args={"check_same_thread": False}
    if settings.database_url.startswith("sqlite")
    else {},
)
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
```

- **`engine`은 프로세스 전역 1개.** 커넥션 풀을 들고 있는 무거운 객체라 재사용한다.
- **`check_same_thread=False`는 SQLite 전용.** FastAPI 동기 핸들러는 anyio 스레드풀에서 실행되므로, 요청을 만든 스레드와 다른 스레드가 커넥션을 만질 수 있다. SQLite의 기본 스레드 검사를 꺼서 이를 허용한다. 다른 DB URL이면 이 옵션을 넣지 않는다.
- **`autoflush=False`**: 조회 직전 자동 flush를 끈다. seed 로직이 flush 시점을 직접 제어할 수 있게 한다(`scripts/seed/seed_navigation.py`가 Building을 먼저 flush해 identity map에 올리는 식).
- **`autocommit=False`**: 명시적으로 commit할 때까지 트랜잭션이 열려 있다.

### `get_db()` — 요청 단위 Session 의존성

```python
def get_db() -> Iterator[Session]:
    session = SessionLocal()
    try:
        yield session
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
```

- **요청마다 Session 하나를 만들고, 끝나면 반드시 닫는다.** FastAPI가 `Depends(get_db)`로 이 제너레이터를 구동한다.
- 라우터에서:
  ```python
  @router.get(...)
  def handler(session: Session = Depends(get_db)):
      ...
  ```
- 핸들러가 예외를 던지면 `except`에서 **rollback**, 정상이든 아니든 `finally`에서 **close**.
- 테스트는 이 의존성을 시드된 임시 DB로 교체한다(`tests/conftest.py`의 `app.dependency_overrides[get_db]`).

> Spring 대응: `get_db` = 요청 스코프 `EntityManager` 주입 + 트랜잭션 경계 정리(`@Transactional`이 대신 해주던 rollback/close를 여기서 명시적으로 한다).

---

## 의존성 방향

```
config.py  ──►  (환경변수만 읽음. 다른 app 모듈에 의존 안 함)
database.py ──►  config.settings

routers / repositories / services  ──►  core.database.get_db, SessionLocal
scripts/seed                       ──►  core.database.SessionLocal, engine
```

- **core는 app의 다른 어떤 계층에도 의존하지 않는다.** 가장 안쪽 기반 레이어다.
- 반대로 거의 모든 계층이 core에 의존한다. 그래서 core는 얇고 안정적으로 유지한다.

---

## 자주 하는 작업

| 하고 싶은 것 | 방법 |
|---|---|
| DB 파일 위치 바꾸기 | 환경변수 `NAV_DATABASE_URL` |
| 새 설정값 추가 | `Settings`에 필드 추가 → `NAV_<이름>` 환경변수로 주입 |
| DB 초기화/시드 | `python -m scripts.seed.reset_and_seed` (core를 직접 건드리지 않음) |
| 테스트에서 임시 DB 쓰기 | `dependency_overrides[get_db]` 교체 (conftest 참고) |
