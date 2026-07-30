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

- [ ] 잘못된 그래프(제약 위반)는 DB commit 전에 실패한다.
- [ ] 다른 건물을 연결하는 간선은 저장할 수 없다.
- [ ] API 응답에 NaN, Infinity, 음수 비용이 노출되지 않는다.
- [ ] 시드 성공 시 검증 결과와 그래프 통계가 artifact(JSON 등)로 남는다.
- [ ] `PRAGMA foreign_keys=ON` 등이 연결 시점에 적용됨을 테스트로 확인한다.

## 참고

- 원문서 7~9페이지 "P0-4. 그래프 데이터 무결성이 DB에서 강제되지 않음".
- 완료 후 04번(수직 이동 생성 알고리즘)과 05번(매장 입구 스냅)에서 이 validator를 재사용한다.
