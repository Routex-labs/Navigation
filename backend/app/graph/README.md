# `app/graph` — 길찾기 그래프 도메인 (무결성 검증·리비전)

DB에 저장된 길찾기 그래프(노드·간선)를 두고 **저장 전후로 두 가지 순수 계산**을 담는다.
하나는 그래프가 의미적으로 온전한지 검사하는 무결성 검증기, 다른 하나는 "이 그래프가
그대로인가"를 값 하나로 판정하는 내용 기반 리비전이다. 둘 다 `models`의 값 필드만 읽는
순수 함수라 부작용이 없다.

> 왜 별도 계층인가: 검증기는 DB 삽입에 의존하지 않아야 (1) 일부러 깨뜨린 그래프로 검증기
> 자체를 테스트할 수 있고 — DB는 그런 간선을 애초에 거부하므로 —, (2) 간선을 저장하기
> *전에* 같은 규칙으로 검사할 수 있다. 그래서 `repositories`(Session 필요)가 아니라 순수
> 도메인으로 뺐다.

---

## 구성 파일

| 파일 | 역할 | 핵심 심볼 |
|---|---|---|
| `integrity.py` | 그래프 무결성 검증 (DB가 못 잡는 의미·위상 위반) | `validate_graph`, `collect_graph_data`, `validate_seeded_graph`, `GraphReport`, `GraphIssue`, `GraphIntegrityError` |
| `revision.py` | 내용 기반·순서 무관 그래프 체크섬 | `graph_revision` |
| `__init__.py` | 패키지 표식 | — |

---

## `integrity.py` — 무결성 검증기

DB의 `CheckConstraint`·FK(`models/navigation.py`, `core/database.py`의 PRAGMA)는 **구조적**
위반(중복 PK, 고아 참조, 자기 참조, 음수 거리·비용)을 저장 시점에 막는다. 이 검증기는 그
위에서 **DB가 못 잡는 의미·위상 위반**을 잡는다.

```python
def collect_graph_data(session) -> GraphData      # DB 전체 그래프를 검증기 입력 구조로(건물 무관)
def validate_graph(data: GraphData) -> GraphReport # 이슈 목록 + 통계 리포트
def validate_seeded_graph(session) -> GraphReport  # flush → collect → validate, 에러면 예외로 시드 중단
```

- **에러(시드 중단)**: 다른 건물을 잇는 간선(`cross_building_edge`), 층 내부 간선이 다른 층을
  잇거나 `floor_id`가 어긋남(`intra_edge_floor_mismatch`), 수직 전이가 같은 층을 잇거나
  (`transfer_same_floor`) 에스컬레이터 전이가 양방향(`escalator_bidirectional`), NaN/Infinity
  값(`non_finite_value` — SQLite의 `>= 0`으로는 못 거를 수 있다), 음수 값, endpoint 없음,
  자기 루프, 중복 id.
- **경고(통과)**: 점 하나짜리 geometry(`degenerate_geometry`), 그래프에 없는 매장 입구 노드
  (`store_entrance_missing_node`), 여러 조각으로 갈라진 건물 그래프(`disconnected_components` —
  물리적으로 떨어진 구역이 있을 수 있어 무조건 오류로 보지 않는다).

`GraphReport.ok`는 **에러가 하나도 없을 때** 참이다(경고는 통과). `validate_seeded_graph`는
`ok`가 아니면 `GraphIntegrityError`를 던져 commit 전에 롤백을 유도한다 — facet 검증
(`studio_adapter.validate_facet_resources`)과 같은 철학의 시드 게이트다. 리포트의 `stats`
(건물·층·노드·간선·전이 간선·매장 수, 건물별 집계)와 경고는 시드가 artifact로 남긴다.

## `revision.py` — 그래프 리비전

같은 그래프면 같은 값, 데이터가 바뀌면 다른 값. 클라이언트·타일 캐시가 그래프 무효화 키로
쓴다.

```python
def graph_revision(nodes, edges) -> str  # 노드·간선 dict 목록 → 16바이트 hex (blake2b)
```

- **순서 무관**: DB 조회 순서가 달라져도(정렬 미지정) 같은 그래프면 같은 값이 나오도록 노드·
  간선을 `id`로 정렬한 뒤 해싱한다. 안 그러면 재시드마다 캐시가 무의미하게 깨진다.
- **내용 기반**: 응답에 실리는 필드(좌표·거리·비용·전이 수단·층 등)를 그대로 해싱하므로 좌표
  한 점만 바뀌어도 리비전이 바뀐다.
- **정책 반영**: 넘긴 간선 목록 그대로를 해싱한다. `vertical` 정책으로 간선이 필터된 건물
  그래프는 정책마다 다른 리비전을 갖는다(반환 payload가 실제로 다르므로 옳다).

---

## 의존성 방향

```
graph/integrity.py  ──►  app.models (Edge·Floor·Node·Store 값 필드), SQLAlchemy Session(조회만)
graph/revision.py   ──►  표준 라이브러리(hashlib·json)만 — DB도 models도 모른다

scripts/seed/*            ──►  graph.integrity.validate_seeded_graph (시드 게이트)
repositories/building_queries.py ──►  graph.revision.graph_revision (그래프 응답 리비전)
```

- **graph는 app 상위 계층에 의존하지 않는다.** `integrity`는 조회를 위해 Session을 받지만
  라우터·dto는 모르고, `revision`은 dict만 받아 model조차 모른다.
- 검증기는 순수하다 — `collect_graph_data`로 DB를 평범한 dataclass로 뽑은 뒤에는 DB 없이
  `validate_graph`만으로 검사·테스트할 수 있다.

---

## 자주 하는 작업

| 하고 싶은 것 | 어디를 보나 |
|---|---|
| 새 무결성 규칙 추가 | `validate_graph`가 부르는 `_check_*` 함수 + 이슈 코드 |
| 시드가 그래프 오류로 멈춘다 | `GraphIntegrityError` 메시지의 이슈 코드 → 해당 `_check_*` |
| 그래프가 안 바뀌었는데 캐시가 깨진다 | `graph_revision`에 넘기는 노드·간선 필드가 요청마다 같은지 |

---

> **다음 읽기:** [`app/repositories` — DB 조회와 응답 조립](../repositories/README.md)
