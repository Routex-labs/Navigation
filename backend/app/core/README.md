# `app/core` — 애플리케이션 설정과 DB 연결

앱 전체가 공유하는 **인프라 기반**을 제공한다. 세 가지뿐이다.

1. **설정값**을 환경변수에서 읽어 한곳에 모은다 (`config.py`)
2. **DB 엔진과 요청 단위 Session**을 만든다 (`database.py`)
3. **개발 진단 로그**를 남긴다 — SQL(`database.py`)과 HTTP JSON(`request_capture.py`)

비즈니스 규칙(경로 탐색, 좌표 변환)이나 HTTP 처리는 여기에 없다. "DB에 어떻게 붙는가"와
"개발 중 무엇이 오갔는지 기록"만 담당한다.

> Spring 대응: `application.yml`(설정) + `DataSource`/`EntityManagerFactory`(연결) 자리.

---

## 구성 파일

| 파일 | 역할 | 핵심 심볼 |
|---|---|---|
| `config.py` | 환경변수 → 설정 객체 | `settings`, `Settings`, `DEFAULT_DATABASE_URL` |
| `database.py` | 엔진·세션·요청 의존성 + SQL 진단 로그 | `engine`, `SessionLocal`, `get_db()` |
| `request_capture.py` | HTTP 요청/응답 JSON 진단 로그 (ASGI 미들웨어) | `RequestCaptureMiddleware`, `start_runtime_logs()`, `clear_runtime_logs()` |
| `__init__.py` | 패키지 표식 | — |

---

## `config.py` — 설정

```python
API_ROOT = Path(__file__).resolve().parents[2]          # backend/
DEFAULT_DATABASE_URL = f"sqlite:///{(API_ROOT / 'data' / 'navigation.db').as_posix()}"


class Settings(BaseSettings):
    database_url: str = DEFAULT_DATABASE_URL
    sql_echo: bool = False        # NAV_SQL_ECHO — 실행된 SQL을 app/sql/queries.sql에
    http_capture: bool = False    # NAV_HTTP_CAPTURE — 요청/응답 JSON을 app/args/에
    warm_embedding: bool = False  # NAV_WARM_EMBEDDING — 기동 시 임베딩 모델 백그라운드 선로드
    model_config = SettingsConfigDict(env_prefix="NAV_", case_sensitive=False)


settings = Settings()   # import 시 1회 생성, 프로세스 전역 재사용
```

- **`settings`는 모듈 전역 싱글턴이다.** 다른 모듈은 `from app.core.config import settings`로 가져다 쓴다.
- **환경변수 접두사는 `NAV_`.** `database_url` 필드는 환경변수 `NAV_DATABASE_URL`로 덮어쓴다 (`case_sensitive=False`라 대소문자 무관).
- **진단 로그 둘은 기본이 꺼짐(False)이다.** 로컬 개발 실행에서만
  `NAV_SQL_ECHO=1`·`NAV_HTTP_CAPTURE=1`로 켠다. 실행 명령은
  [`DEBUG_LOGGING.md`](../../DEBUG_LOGGING.md)를 따른다.
- **`NAV_WARM_EMBEDDING`도 기본 꺼짐이다.** 켜면 `main.create_app()`이 기동 직후
  임베딩 모델을 백그라운드 데몬 스레드로 선로드해 첫 `/query/ai` 지연을 없앤다. 켠 프로세스는
  torch를 로드하고 메모리를 상주시키므로 **배포 이미지에서만 켜고**(`Dockerfile`), 테스트·로컬은
  끈다. 배포 스펙은 [`gcp-instance.md`](../../../docs/guide/gcp-instance.md).
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

## `request_capture.py` — HTTP 진단 미들웨어

`NAV_HTTP_CAPTURE`가 켜졌을 때만 `main.create_app()`이 붙인다. 요청 JSON과 응답 상태 코드를
`backend/app/args/{나노초}-{method}-{경로}.json`에 한 건씩 남긴다.

```python
app.add_middleware(RequestCaptureMiddleware)   # main.py, http_capture일 때만
```

- **비밀값 마스킹.** `password`·`token`·`authorization` 같은 키가 보이면 값을 `***`로 바꾼다.
  중첩 dict·list 안쪽까지 재귀로 훑는다.
- **`/health`는 첫 한 건만.** Docker healthcheck가 10초마다 때리므로 기동 확인용 1건만 남기고
  이후는 건너뛴다. 안 그러면 진단 폴더가 healthcheck로만 가득 찬다.
- **실패해도 API를 막지 않는다.** 파일 쓰기가 `OSError`로 실패하면 조용히 넘어간다
  (`except OSError: pass`). 진단이 실제 응답을 깨뜨리면 안 된다.
- **수명주기 정리는 `main.py`의 lifespan이 한다.** 기동 시 이전 실행의 로그를 비우고
  (`start_runtime_logs`), 정상 종료 시 파일을 지운다(`clear_runtime_logs`).
  Docker bind mount 자체는 지울 수 없으므로 **폴더는 남기고 내부 항목만** 비운다.

> 두 진단 디렉터리(`app/sql/`, `app/args/`)는 `.gitignore`에 있다. 서버를 종료하면
> 비워지므로, 필요한 확인은 종료 전에 해야 한다.

---

## 의존성 방향

```
config.py          ──►  (환경변수만 읽음. 다른 app 모듈에 의존 안 함)
database.py        ──►  config.settings, config.API_ROOT
request_capture.py ──►  config.API_ROOT, starlette 타입

routers / repositories  ──►  core.database.get_db, SessionLocal
main.create_app()       ──►  core.request_capture (미들웨어·lifespan)
scripts/seed            ──►  core.database.SessionLocal, engine
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
| SQL 로그 보기 | `NAV_SQL_ECHO=1`로 실행 후 `backend/app/sql/queries.sql` |
| 실제 요청 인자 보기 | `NAV_HTTP_CAPTURE=1`로 실행 후 `backend/app/args/*.json` |
| 테스트에서 임시 DB 쓰기 | `dependency_overrides[get_db]` 교체 (conftest 참고) |

---

> **다음 읽기:** [`app/models` — SQLAlchemy ORM 데이터 모델](../models/README.md)
