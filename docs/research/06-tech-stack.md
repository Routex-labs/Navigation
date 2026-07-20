# 06. 기술 스택과 데이터 포맷

현재 구현 기준의 스택 문서다. 초기 조사 단계의 PDR/RAG 중심 설계는 제거하고,
지금 동작하는 **Flutter 클라이언트 + FastAPI API + SQLite 데이터 저장소** 흐름을 기준으로 둔다.

## 1. 현재 방향

```text
Flutter 앱 ──HTTP──> FastAPI ──SQLAlchemy──> SQLite
                    │
                    └── 실내 지도 · 매장 · 그래프 API (경로 계산은 클라이언트 온디바이스)
```

목표는 경진대회 데모에서 바로 보여줄 수 있는 실내 지도와 경로 안내다.
센서 기반 실시간 측위나 자연어 RAG는 후속 확장 후보이며, 현재 필수 구현 범위는 아니다.

## 2. 클라이언트

| 항목 | 현재 값 |
|---|---|
| 프레임워크 | Flutter |
| 언어 | Dart |
| 주요 패키지 | `http`, `permission_handler`, `flutter_map`, `latlong2`, `geolocator`, `flutter_svg` |
| 테스트 | `flutter_test`, `integration_test` |

현재 앱은 백엔드 API에서 건물·층·경로 데이터를 받아 지도 화면에 표시한다.
Android 에뮬레이터에서는 API 기본 주소로 `http://10.0.2.2:8001`을 사용한다.

## 3. 백엔드

| 항목 | 현재 값 |
|---|---|
| 프레임워크 | FastAPI |
| 언어 | Python |
| ASGI 서버 | `uvicorn[standard]` |
| 데이터 검증 | `pydantic`, `pydantic-settings` |
| ORM | SQLAlchemy 2.0 |
| DB | SQLite |
| 테스트 | `pytest`, `httpx` |

백엔드는 HTTP 라우터, 서비스, ORM 모델, DB 세션 구성을 분리한다.
개발 DB 초기화와 시드는 서버 시작 시 자동 실행하지 않고 CLI 스크립트로 실행한다.

## 4. 주요 API

| 용도 | 경로 |
|---|---|
| 상태 확인 | `GET /health` |
| 건물 목록 | `GET /buildings` |
| 층 지도 | `GET /buildings/{building_id}/floors/{floor_name}` |
| 층 그래프 | `GET /buildings/{building_id}/floors/{floor_name}/graph` |

최단 경로는 서버 엔드포인트가 아니다. 클라이언트가 층 지도 응답의 `navigation_graph`로 온디바이스 Dijkstra를 돌린다.

API 계약은 Flutter 클라이언트가 소비하는 JSON 형태를 우선으로 유지한다.

## 5. 데이터 포맷

현재 데이터는 SQLite에 적재하며, 원천/중간 산출물은 JSON 형태로 관리한다.
핵심 모델은 다음 성격을 가진다.

| 데이터 | 역할 |
|---|---|
| Building | 건물 메타데이터 |
| Floor | 층 이름과 층별 지도 범위 |
| Store/POI | 목적지 후보와 표시 정보 |
| NavigationNode | 경로 그래프 노드 |
| NavigationEdge | 경로 그래프 간선 |
| Vector Map | 층별 실내 지도 렌더링 데이터 |

실내 좌표는 GPS 위경도보다 건물 로컬 좌표계를 우선한다.
Flutter 화면 렌더링과 클라이언트 경로 계산이 같은 좌표계를 공유하는 것이 중요하다.

## 6. 개발 · 빌드 · 배포

| 영역 | 도구 | 메모 |
|---|---|---|
| 버전 관리 | Git + GitHub Flow | Projects 보드와 함께 운영 |
| CI/CD | GitHub Actions | `.github/workflows/ci.yml`, `.github/workflows/project-automation.yml` |
| Flutter 린트 | `flutter_lints` | `client/analysis_options.yaml` |
| Python 테스트 | `pytest` | `backend/tests/` |
| 컨테이너 | Docker Compose | `docker compose up --build api`로 API 서버 실행 |

## 7. 후속 후보

아래 항목은 현재 필수 구현 범위가 아니라, 데모가 안정화된 뒤 붙일 수 있는 확장 후보다.

| 후보 | 현재 판단 |
|---|---|
| PDR/센서 기반 실시간 측위 | 아직 미연동. 현재 경로 출발점은 임시 노드/선택값으로 처리 |
| Particle Filter 지도 매칭 | 실제 센서 측위가 들어온 뒤 검토 |
| 자연어/RAG 목적지 검색 | UI/저장소 스텁 또는 mock 이후 실제 백엔드 연동 검토 |
| PostgreSQL/PostGIS | SQLite 한계를 확인한 뒤 전환 검토 |

## 참고 자료

- [Flutter](https://flutter.dev/)
- [FastAPI](https://fastapi.tiangolo.com/)
- [SQLAlchemy](https://www.sqlalchemy.org/)
- [SQLite](https://www.sqlite.org/)
