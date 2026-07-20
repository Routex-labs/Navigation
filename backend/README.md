# backend

FastAPI 기반 실내 내비게이션 API 서버.

각 디렉터리는 자체 `README.md`에 상세 설명(역할·구성 파일·설계 근거·의존성·자주 하는 작업)을 담는다.
아래는 그 문서들을 모은 목차다.

## 문서 목차

| 계층 | 디렉터리 | 역할 |
|---|---|---|
| 진입점 | [`app/main.py`](app/main.py) | FastAPI 앱 팩토리 · 라우터 등록 · `/health` |
| 경계 | [`app/routers/`](app/routers/README.md) | HTTP 엔드포인트, 상태 코드 번역 |
| 계약 | [`app/dto/`](app/dto/README.md) | Pydantic 요청/응답 스키마 |
| 접근 | [`app/repositories/`](app/repositories/README.md) | DB 조회 + 응답 dict 조립 |
| 데이터 | [`app/models/`](app/models/README.md) | SQLAlchemy ORM 엔티티 (테이블) |
| 순수 로직 | [`app/geo/`](app/geo/README.md) | 좌표 변환 · 지도 타일 |
| 인프라 | [`app/core/`](app/core/README.md) | 설정 · DB 엔진/세션 |
| 스크립트 | [`scripts/seed/`](scripts/seed/README.md) | DB 초기화 · 시드 (DB 접근) |
| 스크립트 | [`scripts/transform/`](scripts/transform/README.md) | 순수 변환 (파일→파일 / dict→dict) |

## 디렉터리 구조

```
backend/
├── app/                 # 애플리케이션 코드
│   ├── main.py          # FastAPI 진입점 · 라우터 등록
│   ├── core/            # 설정과 인프라 (config, database)
│   ├── models/          # SQLAlchemy ORM 모델 (DB 테이블)
│   ├── dto/             # Pydantic 요청/응답 스키마
│   ├── repositories/    # DB 쿼리 계층 (건물·타일 조회, 좌표 변환)
│   ├── geo/             # 지리 계산 (georeference, tiling)
│   └── routers/         # HTTP 엔드포인트 (buildings, query, fonts)
├── scripts/             # 오프라인 실행용 스크립트
│   ├── seed/            # DB 초기화·시드 (reset_and_seed 등)
│   └── transform/       # 데이터 가공 (글리프 생성, 층 정렬 등)
├── resources/           # 정적 리소스
│   ├── fonts/           # MapLibre SDF 글리프 (Noto Sans KR)
│   └── studio/          # 스튜디오 원본 데이터
├── data/                # 런타임 SQLite DB (gitignore, 재생성 가능)
└── tests/               # 테스트
    ├── unit/            # 단위 테스트 (좌표 변환·타일·시드)
    └── integration/     # 통합 테스트 (API·DB)
```

## 계층 흐름

요청은 바깥(HTTP)에서 안(DB)으로 흐르고, 결과는 `dto`로 직렬화되어 돌아간다.
`geo`는 프레임워크를 모르는 순수 계산 모듈이고, `core`는 모두가 딛는 기반이다.
최단 경로 계산은 서버에 없다 — 층 지도 응답의 `navigation_graph`를 받아 **클라이언트가 온디바이스 Dijkstra**(`client/lib/domain/dijkstra.dart`)로 수행한다.

```
        HTTP 요청
           │
           ▼
   ┌───────────────┐   response_model
   │   routers/    │───────────────► dto/        (계약: 나가는 모양)
   └───────┬───────┘
           │  조회
           ▼
   ┌───────────────┐        ┌──────────────┐
   │ repositories/ │───사용─►│    geo/      │  (순수 로직, 부작용 없음)
   └───────┬───────┘        └──────────────┘
           │
           ▼
   ┌───────────────┐
   │    models/    │
   │   (ORM/DB)    │
   └───────┬───────┘
           ▼
        SQLite

   core/ (config·database) ── 위 모든 계층이 Session/설정을 여기서 얻음
```

의존 규칙: 바깥이 안을 호출하고, 안은 바깥을 모른다. `models`/`geo`는 상위 계층에 의존하지 않으며, `dto`는 `models`를 import하지 않는다(저장되는 모양 ≠ 나가는 모양).

## 실행

### Docker Compose (권장)

저장소 루트(`docker-compose.yml` 위치)에서:

```bash
docker compose up
```

컨테이너가 DB 시드(`scripts.seed.reset_and_seed`)를 먼저 돌린 뒤 서버를 띄운다.
`http://localhost:8001`에서 응답하며, `/health`로 상태를 확인할 수 있다.

### 로컬 실행 (venv)

`backend/`에서:

```bash
# 최초 1회 DB 적재
python -m scripts.seed.reset_and_seed
# 서버 실행
uvicorn app.main:app --reload --host 0.0.0.0 --port 8001
# 테스트
pytest
```

DB 위치·종류는 환경변수 `NAV_DATABASE_URL`로 바꾼다(기본: `backend/data/navigation.db`,
Compose는 컨테이너의 `/app/data/navigation.db`). 자세한 건 [`app/core/README.md`](app/core/README.md).
