# Navigation API ORM 리팩터링 작업 지시서

## 새 세션 인계 사항

### 현재 상태

- 설계 문서의 범위·엔티티 관계·응답 모델·Query/Service 경계·Router/DI·테스트 기준은
  확정됐다. 구현 코드는 아직 변경하지 않았다.
- 사용자 작업으로 untracked 상태인 아래 항목을 보존한다. 이 리팩터링과 무관한 문서는
  삭제·덮어쓰기·일괄 stage하지 않는다.
  - `docs/FastAPI-실습-가이드.md`
  - `docs/api-orm-refactoring-plan.md`
  - 이 파일
- 첫 문서 커밋은 리팩터링 문서 두 개만 선택해 stage한다. 다른 untracked 문서는 포함하지
  않는다.

### 새 세션의 첫 작업

1. 저장소의 `AGENTS.md`, 이 파일, `docs/api-orm-refactoring-plan.md`를 읽는다.
2. `git status --short`와 전체 테스트를 실행해 기준선을 기록한다.
3. 기준선이 통과하면 아래 커밋 체크리스트 순서대로 구현한다. 한 커밋의 검증이 통과하기 전
   다음 커밋을 시작하지 않는다.

### 커밋 체크리스트

- [ ] `문서: ORM 전환 계획 정리` — 리팩터링 문서만 stage
- [ ] `의존성: ORM 패키지 추가` — SQLAlchemy, pydantic-settings import 검증
- [ ] `코어: DB 세션 추가` — Settings, engine, SessionLocal, `get_db` import·Session 생성 검증
- [ ] `모델: 지도 ORM 추가` — 8개 모델과 빈 SQLite `create_all()` 검증
- [ ] `시드: 지도 데이터 ORM 적재` — `reset → seed`와 데이터 적재 검증
- [ ] `스키마: GET 응답 모델 추가` — 새 `schemas/` 응답 모델 검증
- [ ] `조회: 건물 ORM 쿼리 추가` — 건물·매장·지도·그래프 Query 검증
- [ ] `서비스: 경로 탐색 이전` — NavigationService 경로 규칙 검증
- [ ] `라우터: ORM DI 전환` — `routers/`, `main.py`, response_model, URL/상태 코드 검증
- [ ] `테스트: ORM 검증 전환` — 임시 시드 DB fixture, 정상·오류 API 검증
- [ ] `정리: sqlite3 구조 제거` — 전체 테스트와 import 검색 후 레거시 삭제

### 커밋 경계 규칙

- 커밋 분리는 현재 구조상 합리적이다. 의존성 → Core → 모델 → seed → 스키마 →
  Query/Service → Router → 테스트 → 레거시 제거의 단방향 의존성을 따른다.
- 새 `schemas/`, `queries/`, `services/`, `routers/`는 각 커밋에서 먼저 추가한다. 기존
  `schema/`, `router/`, `FastAPIConfig.py`, sqlite3 Repository/Service는 마지막 정리 커밋
  전까지 삭제하지 않는다.
- Router 전환 커밋에서만 `main.py`와 새 `routers/`를 활성화한다. 그 전 커밋들은 기존 API와
  기존 테스트를 계속 통과시켜야 한다.

```text
목표

E:\경진대회\Navigation\api의 FastAPI 백엔드를 raw sqlite3 + 수동 DDL/Repository 구조에서
SQLAlchemy 2.0 ORM 구조로 리팩터링한다.

확정된 범위

- DB는 SQLite를 유지한다. PostgreSQL은 도입하지 않는다.
- Alembic은 도입하지 않는다.
- 개발 DB는 명시적 CLI에서만 `drop_all() → create_all() → seed`로 초기화한다.
- FastAPI 서버 startup 시 DB 초기화/시드하지 않는다.
- Flutter 호환을 위해 기존 API URL, HTTP 상태 코드, 응답 JSON 키를 유지한다.
- 특히 `from`, `to`, `centroid_local_m`, `path_points` 등 응답 구조를 바꾸지 않는다.
- 현재 쓰기 API가 없으므로 Create/Update Pydantic DTO는 만들지 않는다.

목표 구조

api/app/
├── core/
│   ├── config.py              # Settings, DATABASE_URL
│   └── database.py            # engine, SessionLocal, get_db
├── models/
│   ├── base.py
│   ├── building.py            # Building, Floor
│   ├── navigation.py          # Node, Edge
│   ├── place.py               # Store, Poi, FloorVectorMap, MapFeature
│   └── __init__.py
├── queries/
│   └── building_queries.py    # 단순 ORM 조회
├── services/
│   └── navigation_service.py  # 최단 경로 계산만
├── schemas/                   # Pydantic 요청/응답 모델
├── routers/                   # HTTP/DI/400·404 변환만
└── scripts/
    ├── reset_database.py
    ├── seed_navigation.py
    └── reset_and_seed.py

Service 배치 결정

- Service 유지: NavigationService
  - Floor, Node, Edge 조회
  - 다익스트라 실행
  - 역방향 Edge geometry 보정 및 path_points 조립
- Service 미생성: 건물 목록/상세, 매장 검색, 층 지도, 그래프 조회
  - `queries/building_queries.py`에 둔다.
- RAG Query API는 현재 stub이므로 Service를 만들지 않는다.

구현 순서

0. 작업 전 현재 파일을 읽고 `git status --short`와 전체 테스트 결과를 확인한다.
1. `api/requirements.txt`에 `sqlalchemy>=2.0`, `pydantic-settings>=2.0`을 추가한다.
2. `core/config.py`, `core/database.py`를 추가한다.
   - Session은 요청마다 생성한다.
   - get_db는 예외 시 rollback, finally에서 close한다.
   - 이 단계에서는 기존 FastAPIConfig/sqlite3 DI를 아직 제거하지 않는다.
3. 8개 ORM 모델을 작성한다.
   - Building, Floor, Node, Edge, Store, Poi, FloorVectorMap, MapFeature
   - 기존 DDL의 PK, FK, nullable, unique, index를 보존한다.
   - Edge는 from_node_id, to_node_id 두 FK를 가진다.
   - 좌표 배열/geometry/polygon은 JSON 컬럼으로 유지한다.
4. 빈 임시 SQLite DB에서 `Base.metadata.create_all()`이 성공하는지 확인한다.
5. `reset_database.py`, `seed_navigation.py`, `reset_and_seed.py`를 구현한다.
   - 기존 load_dataset.py의 JSON 파싱·좌표 보정 로직을 옮긴다.
   - raw DDL, sqlite3.connect, raw INSERT는 새 시드 코드에서 제거한다.
   - 시드는 ORM 객체를 만들고 한 트랜잭션으로 commit한다.
6. 모든 GET API의 Pydantic 응답 모델을 구현한다.
   - 기존 FloorMapResponse, FloorGraphResponse, RouteResponse 유지
   - HealthResponse, BuildingSummaryResponse, BuildingDetailResponse 등 추가
   - ORM 구조와 API JSON 구조가 다르면 Query/Service에서 응답 dict를 조립한다.
7. `queries/building_queries.py`를 구현한다.
   - list_buildings: Building + selectinload(Building.floors)
   - get_building
   - search_stores
   - get_floor_map
   - get_floor_graph
   - Query 함수는 Session을 받고 HTTPException을 import하지 않는다.
8. `NavigationService`를 구현한다.
   - 기존 BuildingService의 get_shortest_path, _build_path_points만 옮긴다.
   - 한 층의 Node·Edge 전체를 각각 한 번 조회한다.
   - 탐색 중 관계를 반복 순회하지 말고 id→객체 dict로 탐색한다.
9. buildings Router를 전환한다.
   - 단순 조회: get_db Session + building_queries
   - route: get_db Session + NavigationService
   - Router에는 파라미터, Depends, response_model, 400/404만 남긴다.
   - 기존 `router/`는 `routers/`로, `FastAPIConfig.py`의 앱 조립은 `main.py`로 전환한다.
10. 임시 시드 DB 기반 테스트로 전환하고 전체 테스트를 통과시킨다.
    - DB 연결 자체는 테스트하지 않고 seed·ORM 조회·경로 규칙·API 계약을 검증한다.
    - 정상 흐름과 핵심 400/404·잘못된 시드 입력 오류를 각각 최소 한 사례로 검증한다.
11. 테스트가 모두 통과한 뒤에만 기존 코드를 제거한다.
   - 삭제 후보: BuildingRepository, SqliteBuildingRepository,
     BuildingService, domain/building.py, 기존 load_dataset.py, 기존 sqlite3 DI
   - 삭제 전 `rg "BuildingService|SqliteBuildingRepository|BuildingRepository|sqlite3" api/app api/tests`로 import를 확인한다.

로딩 전략

- Building → floors: selectinload 사용 (건물 목록의 N+1 방지)
- Floor → Building 또는 Floor → FloorVectorMap: 필요할 때만 joinedload 가능
- Floor → Stores/Nodes/Edges/Pois/MapFeatures: 여러 컬렉션 joinedload 금지
  (행 곱집합 방지). selectinload 또는 명시적 select 사용.

검증 기준

- 빈 개발 DB에서 reset + seed 성공
- 기존 단위/통합 테스트 전체 통과
- /health, buildings, store search, floor map, graph, route 응답이 기존과 동일
- Flutter가 소비하는 URL/JSON 키 변경 없음
- raw sqlite3 Repository와 중복 BuildingService가 최종적으로 남지 않음

작업 규칙

- 문서 초안보다 실제 현재 파일 내용을 우선한다.
- 단계 하나의 테스트가 통과하기 전 다음 단계로 진행하지 않는다.
- 기존 코드 삭제는 새 코드로 API와 테스트가 검증된 뒤에만 한다.
```

상세 근거와 ORM 모델 전체 초안은 `docs/api-orm-refactoring-plan.md`를 참고한다.
