# 03. 그래프 데이터 무결성 DB 강제

브랜치(제안): `feat/graph-integrity-constraints`

## 배경

현재 `Edge` 모델의 핵심 제약(거리·비용 음수 금지, 자기 자신 참조 금지, 전이/일반 간선의 층 일치 여부 등)이
주석과 시드 로직에만 의존하고 있어, 손상된 데이터가 DB에 그대로 들어갈 수 있다. 건물 전체 그래프 조회에서
전이 간선의 `from_node_id`만 건물 소속을 확인하면 다른 건물의 노드가 잘못 연결될 위험도 있다.

## 범위(백엔드만)

SQLAlchemy 모델, DB 제약, 시드 전 검증. (02번 작업에서 도입한 `TransferMode` 등 타입에 의존하므로 02번 이후에 작업한다.)

## 작업 항목

1. `backend/app/models/`의 Edge 모델에 `CheckConstraint`를 추가한다.
   - `length_m >= 0`
   - `cost_m >= 0`
   - `from_node_id <> to_node_id`
   - `transfer_mode IS NULL OR transfer_mode IN (...)`
2. `Edge`에 `building_id`를 명시적으로 저장하고, 전이 간선 조회 시 양쪽 endpoint가 같은 건물에 속하는지 검증한다.
3. 일반 간선과 수직 전이 간선의 테이블 분리 여부를 검토한다(분리하지 않기로 결정해도 근거를 문서화).
4. graph validator를 만들어 API 응답 전 또는 시드 시 다음을 검증한다.
   - 중복 node ID / edge ID
   - 존재하지 않는 endpoint
   - 다른 건물을 잇는 간선
   - 음수·NaN·Infinity 거리 또는 비용
   - from == to인 간선
   - 빈 geometry / 한 점짜리 geometry
   - 일반 간선의 층 불일치, 수직 전이 간선의 동일 층 연결
   - 에스컬레이터 방향과 층 level 불일치
   - 연결되지 않은 매장 입구, 고립된 그래프 컴포넌트
5. DTO에서 NaN/Infinity를 거부하도록 검증을 추가한다(pydantic validator 등).
6. graph revision(또는 checksum) 생성 로직을 추가한다 — 06번(타일 캐시)·클라이언트 캐시 무효화의 키로 재사용됨.
7. SQLite 연결 시 다음 PRAGMA를 명시적으로 적용한다.
   ```
   PRAGMA foreign_keys=ON;
   PRAGMA busy_timeout=5000;
   PRAGMA journal_mode=WAL;
   ```

## 완료 기준

- [x] 잘못된 그래프(제약 위반)는 DB commit 전에 실패한다. — Edge CheckConstraint(`length_m>=0`, `cost_m>=0`, `from<>to`, `transfer_mode` 화이트리스트) + 시드 게이트(`validate_seeded_graph`)가 커밋 전 롤백.
- [x] 다른 건물을 연결하는 간선은 저장할 수 없다. — 시드 게이트가 `cross_building_edge`를 에러로 막고, `get_building_graph`는 전이 간선을 양 끝 노드가 모두 그 건물일 때만 싣는다.
- [x] API 응답에 NaN, Infinity, 음수 비용이 노출되지 않는다. — 그래프 DTO가 `allow_inf_nan=False`·`ge=0`으로 거부.
- [x] 시드 성공 시 검증 결과와 그래프 통계가 artifact(JSON 등)로 남는다. — `reset_and_seed`가 `data/seed_graph_report.json`에 기록.
- [x] `PRAGMA foreign_keys=ON` 등이 연결 시점에 적용됨을 테스트로 확인한다. — `tests/unit/test_database_pragmas.py`.

## 설계 결정

- **간선 테이블을 분리하지 않는다(항목 3).** 층 내부 간선과 수직 전이 간선을 별도 테이블로
  쪼개면 조회·DTO·시드가 모두 두 경로로 갈라지는데, 지금 필요한 무결성은 CheckConstraint +
  시드 검증기로 충분히 달성된다. 두 종류의 차이는 `Edge.floor_id`(NULL이면 전이)와
  `transfer_mode`로 이미 명확하고, 단일 층 조회는 `floor_id` 필터로 전이 간선을 자연히
  제외한다. 분리의 이득(약간의 제약 단순화)보다 갈라진 코드 경로의 유지비가 크다.
- **`Edge.building_id` 컬럼을 두지 않는다(항목 2).** 전이 간선의 "양 끝이 같은 건물" 불변식은
  SQLite CheckConstraint로는 두 노드의 소속 건물을 비교할 수 없어(서브쿼리 불가) 컬럼만
  더해서는 강제되지 않는다. 대신 (a) 시드 게이트가 `cross_building_edge`를 에러로 막아 저장을
  차단하고, (b) `get_building_graph`가 양 끝 노드가 모두 그 건물 소속인 전이 간선만 실어
  조회 단계에서도 타 건물로 새지 않게 한다. 비정규화 컬럼 없이 같은 보장을 얻는다.

## 참고

- 원문서 7~9페이지 "P0-4. 그래프 데이터 무결성이 DB에서 강제되지 않음".
- 완료 후 04번(수직 이동 생성 알고리즘)과 05번(매장 입구 스냅)에서 이 validator를 재사용한다.
- 검증기·리비전 구현: `app/graph/integrity.py`, `app/graph/revision.py`.
