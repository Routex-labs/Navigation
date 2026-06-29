# Navigation API

FastAPI 기반 백엔드 골격. 평면도 GeoJSON 서빙 및 RAG 엔드포인트(스텁) 제공.

## 요구 사항

- Python 3.12+

## 실행

```bash
cd api
python -m venv .venv
.venv\Scripts\activate        # Windows
# source .venv/bin/activate   # macOS/Linux
pip install -r requirements.txt
uvicorn app.main:app --reload
```

서버 기동 후 http://localhost:8000/docs 에서 Swagger UI 확인.

## 엔드포인트

| 메서드 | 경로 | 설명 |
|--------|------|------|
| GET | `/health` | 서버 상태 확인 |
| GET | `/buildings` | 건물 목록 |
| GET | `/buildings/{id}` | 건물 상세 |
| GET | `/buildings/{id}/floors/{floor}` | 층 GeoJSON |
| POST | `/query/destination` | 목적지 질의 (RAG 스텁) |
| POST | `/query/info` | 장소 정보 질의 (RAG 스텁) |

## 구조

Spring Boot의 Controller / Service / Repository / Domain 흐름을 FastAPI에 맞춰 사용한다.

| 역할 | 위치 | 현재 구현 |
|------|------|-----------|
| Controller | `app/routers/` | `buildings.py` |
| Service | `app/services/` | `BuildingService` |
| Repository interface | `app/repositories/` | `BuildingRepository` |
| Repository implementation | `app/repositories/` | `MemoryBuildingRepository` |
| Domain object | `app/domain/` | `Building` |
| DI wiring | `app/core/dependencies.py` | `get_building_service`, `get_building_repository` |

초기 데이터 저장소는 `MemoryBuildingRepository`다. 앱 시작 시 `app/data/sample_building.json`을
`Building` 도메인 객체로 읽어 메모리에 보관한다. 나중에 SQL을 도입할 때는
`BuildingRepository` 계약을 구현하는 `SqlBuildingRepository`를 추가하고 DI 설정만 교체한다.

## 테스트

M1-002의 테스트는 Given / When / Then 흐름을 기준으로 작성한다.
각 테스트는 pytest의 함수 스코프 fixture를 통해 BeforeEach / AfterEach 초기화를 거친다.

- BeforeEach: 앱 override 상태를 비우고 테스트용 `MemoryBuildingRepository`와 새 `TestClient`를 준비한다.
- Given: 요청 경로, payload, 기대 응답을 준비한다.
- When: `TestClient`로 API를 호출한다.
- Then: 상태 코드와 응답 본문을 검증한다.
- AfterEach: 테스트 종료 후 앱 override 상태와 repository cache를 다시 비운다.

```bash
pytest
```

## SDK 버전

- fastapi 0.115.x
- uvicorn 0.32.x
- pydantic 2.9.x
- Python 3.12+
