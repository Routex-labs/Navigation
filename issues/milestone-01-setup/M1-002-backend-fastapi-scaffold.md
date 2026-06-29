# M1-002 · FastAPI 백엔드 골격 생성

- **상태**: Draft
- **마일스톤**: M1 · 프로젝트 초기 설정
- **컴포넌트**: api
- **GitHub**: -
- **선행 이슈**: 없음 (M1-001과 병렬 가능)

## 설명

평면도 GeoJSON을 서빙하고 이후 RAG 엔드포인트가 붙을 **최소 FastAPI 골격**을 만든다.
[06-tech-stack.md](../../docs/research/06-tech-stack.md)의 백엔드 디렉토리 구조와 엔드포인트
설계를 실제 파일로 옮긴다. 측위 연산은 온디바이스(클라이언트)이므로 백엔드는
**정적 데이터 서빙 + (이후)RAG** 두 가지로 책임을 한정한다.

## 작업 내용

### 1. 프로젝트 생성

- 저장소 루트에 `api/`를 만들고 06 문서 구조대로 디렉토리를 잡는다.
  ```
  api/
  ├─ app/
  │   ├─ main.py
  │   ├─ routers/buildings.py     routers/query.py(stub)
  │   ├─ services/floor_store.py
  │   ├─ schemas/                 (pydantic 모델)
  │   └─ data/                    (정적 GeoJSON)
  ├─ tests/
  ├─ requirements.txt
  └─ README.md
  ```

### 2. 의존성

- `api/requirements.txt`에 06 문서 버전을 핀으로 적는다.
  ```
  fastapi==0.115.*
  uvicorn[standard]==0.32.*
  pydantic==2.9.*
  shapely==2.0.*
  pytest==8.3.*
  httpx==0.27.*
  ```
- 가상환경(`python -m venv .venv`) 생성 후 `pip install -r requirements.txt` 성공 확인.

### 3. 엔드포인트 구현

- `/health` — `{"status": "ok"}` 반환 (배포·헬스체크용).
- `GET /buildings` — 정적 JSON에서 건물 목록 반환.
- `GET /buildings/{id}` — 건물 메타 + 입구 좌표.
- `GET /buildings/{id}/floors/{floor}` — 해당 층 평면도 GeoJSON.
- `POST /query/destination`, `POST /query/info` — **스텁만**(501 또는 고정 더미 응답).
  실제 RAG는 [09 문서](../../docs/research/09-rag-integration.md) 후속 이슈에서 구현.

### 4. 샘플 데이터

- `app/data/`에 데모용 건물 1개와 층 1개의 GeoJSON 샘플을 넣는다.
  06 문서의 `wall / corridor / door / poi / node / edge` 타입 중 최소 `corridor + poi` 몇 개.
- 실제 평면도가 아니어도 되며, 형식 검증용 최소 샘플이면 충분하다.

### 5. CORS

- Flutter 앱(다른 origin)에서 호출할 수 있게 `CORSMiddleware`를 추가한다(개발 중 `*` 허용).

### 6. pydantic 스키마

- `schemas/`에 `Building`, `Floor`, `POI` 요청/응답 모델을 정의해 응답 형식을 고정한다.

### 7. 컨테이너 (선택)

- `api/Dockerfile`(`python:3.12-slim` 베이스)을 추가한다. VERSION.md 태그 규칙(`navigation/api:0.1.0`) 준수.

### 8. 문서화

- `api/README.md`에 실행법과 엔드포인트 목록을 적는다.

## 파일 (Files)

```
api/requirements.txt
api/app/main.py
api/app/routers/buildings.py
api/app/routers/query.py          (스텁)
api/app/services/floor_store.py
api/app/schemas/building.py
api/app/data/sample_building.json
api/app/data/floors/floor_1.geojson
api/tests/test_buildings.py
api/Dockerfile                    (선택)
api/README.md
```

## 수용 기준 (Acceptance Criteria)

- `uvicorn app.main:app --reload`로 서버가 뜬다.
- `GET /health`가 `200 OK`와 `{"status":"ok"}`를 반환한다.
- `GET /buildings`가 샘플 건물 목록을 반환한다.
- `GET /buildings/{id}/floors/{floor}`가 유효한 GeoJSON을 반환한다.
- `/docs`(Swagger UI)에서 모든 엔드포인트가 보인다.
- `pytest`가 통과한다.

## 검증 (Verification)

```bash
cd api
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload
# 다른 터미널에서:
curl localhost:8000/health
curl localhost:8000/buildings
pytest
```

## 메모

- RAG 엔드포인트는 **스텁만** 둔다. sentence-transformers/FAISS 설치는 09 후속 이슈로 분리해
  이 골격이 무거워지지 않게 한다.
- 1차 데이터 소스는 정적 GeoJSON 파일이다. DB는 확장 시점에 도입한다(06 문서).
