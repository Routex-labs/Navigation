# `app/models` — SQLAlchemy ORM 엔티티

DB **테이블 정의(스키마)**를 담는다. SQLAlchemy `DeclarativeBase` 기반 ORM 클래스들이다.
`Base.metadata`가 이 선언에서 테이블을 만들고(`create_all`), 각 계층이 이 객체로 DB를 읽고 쓴다.

> Spring 대응: JPA `@Entity`. **API 응답 형태(`dto/`)와는 별개다** — 저장되는 모양 vs 나가는 모양.

---

## 구성 파일

| 파일 | 엔티티 | 관계 |
|---|---|---|
| `base.py` | `Base` (DeclarativeBase) | 모든 엔티티의 공통 부모 |
| `building.py` | `Building`, `Floor` | `Building 1:N Floor` 양방향 |
| `navigation.py` | `Node`, `Edge` | `Edge → Node` 단방향 2개(from/to) |
| `place.py` | `Store`, `Poi` | Floor 소속 + 선택적 Node FK |
| `__init__.py` | 위 전부 re-export | `Base.metadata` 등록 보장 |

---

## 엔티티 관계

```
Building 1──N Floor 1──N ┬─ Node ─┐
                         ├─ Edge ─┘ (from_node_id, to_node_id → Node)
                         ├─ Store  (entrance_node_id → Node, 선택)
                         └─ Poi    (linked_node_id → Node, 선택)
```

- **`Floor`가 허브다.** Node·Edge·Store·Poi 모두 `floor_id`로 층에 매인다.
- **`Edge.floor_id`는 nullable.** 층 내부 간선은 층 id를, **층을 잇는 수직 전이 간선(엘리베이터/에스컬레이터)은 `NULL`**을 가진다. 단일 층 조회는 `floor_id`로 필터되어 전이 간선을 자연히 제외하고, 건물 전체 경로 탐색에서만 쓰인다(`Edge.transfer_mode` 참고).

---

## 설계 규칙 (중요)

- **역방향 컬렉션을 만들지 않는다.** `Node.outgoing_edges` 같은 관계는 없다. 그래프 조회는 한 층의 Node·Edge 전체를 한 번에 읽어 `navigation_graph`로 직렬화하므로(경로 탐색 자체는 클라이언트가 온디바이스로 수행) 역방향 관계가 불필요하고, 있으면 N+1을 유발한다.
- **지도 좌표 배열은 JSON 컬럼.** `geometry`, `polygon`, `footprint_local_m`은 관계로 분해하지 않고 SQLite JSON으로 저장한다(`Mapped[list[dict] | None]`). 별도 테이블로 쪼개면 불필요한 JOIN만 는다.
- **좌표는 평면 컬럼.** `x_m`, `y_m`처럼 미터 단위 float. `{"x":…, "y":…}` 중첩 JSON으로의 변환은 `repositories/`가 응답 dict를 조립할 때 명시적으로 한다.
- **인덱스는 조회 패턴 기준.** `idx_nodes_floor`, `idx_edges_from` 등 실제 필터/조인 컬럼에만 건다.

---

## 의존성 방향

```
models/*  ──►  sqlalchemy, models.base 만 (app 상위 계층에 의존 안 함)

repositories / scripts.seed  ──►  models
dto/  ──X──  models   (역할 분리: dto는 models를 import하지 않는다)
```

- **models는 순수 스키마 계층.** 조회 로직(`select`)은 여기 두지 않고 `repositories/`에 둔다.
- `__init__.py`가 모든 모델을 import해야 `Base.metadata`에 테이블이 등록된다 — `create_all` 전에 반드시 `import app.models`가 필요.

---

## 자주 하는 작업

| 하고 싶은 것 | 방법 |
|---|---|
| 컬럼 추가 | 해당 엔티티에 `Mapped[...] = mapped_column(...)` 추가 → DB 재생성(`reset_and_seed`) |
| 새 테이블 | 새 엔티티 클래스 + `__init__.py`에 등록 |
| 스키마 반영 | 마이그레이션 도구 없음 → 개발 DB는 `python -m scripts.seed.reset_and_seed`로 drop & create |
| API에 노출할 필드 고르기 | models가 아니라 `dto/`에서 결정 |
