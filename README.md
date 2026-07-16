# Navigation

> 실외에서 실내까지 이어지는 경로 안내를 위한 Flutter 클라이언트와 FastAPI 백엔드 데모입니다.

처음 실행한다면 [로컬 개발 가이드](docs/local-development-guide.md)부터 보세요. Windows, macOS, Android 에뮬레이터/실기기, iOS 시뮬레이터/실기기 실행 방법을 분리해서 정리해 두었습니다.

## 구성

```text
client/  Flutter 앱 (Android · iOS · macOS)
api/     FastAPI · SQLAlchemy · SQLite 백엔드
docs/    실행, 구조, 조사 문서
```

```text
Flutter 앱 ──HTTP──> FastAPI ──> SQLite
                    │
                    └── 실내 지도 · 매장 · 그래프 · 최단 경로 API
```

## 빠른 시작

상세 실행법은 [로컬 개발 가이드](docs/local-development-guide.md)를 따릅니다. 요약하면 백엔드를 먼저 띄우고, Flutter 앱은 `client/`에서 실행합니다.

## 더현대서울 지도 데이터셋 구축
**Docker로 백엔드 실행**

```powershell
docker compose up --build api
```

컨테이너는 시작 시 개발 DB를 초기화하고 기본 지도 데이터를 적재한 뒤 `0.0.0.0:8001`로 API를 실행합니다.
상태 확인은 `Invoke-RestMethod http://127.0.0.1:8001/health`로 합니다.

**백엔드 — 로컬 Python**

```powershell
Set-Location api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
python -m scripts.reset_and_seed
uvicorn app.main:app --reload --host 0.0.0.0 --port 8001
```

서버 상태를 확인합니다.

```powershell
Invoke-RestMethod http://127.0.0.1:8001/health
```

**Flutter 앱 — Android 에뮬레이터 예시**

```powershell
Set-Location client
flutter pub get
flutter devices
flutter run
```

Android 에뮬레이터는 기본값 `http://10.0.2.2:8001`을 사용하므로 별도 API 주소 지정이 필요 없습니다. 실기기, iOS, macOS 실행 방법과 네트워크·HTTP 주의사항은 [로컬 개발 가이드](docs/local-development-guide.md)를 따르세요.

## 주요 API

| 용도 | 경로 |
|---|---|
| 상태 확인 | `GET /health` |
| 건물 목록 | `GET /buildings` |
| 층 지도 | `GET /buildings/{building_id}/floors/{floor_name}` |
| 층 그래프 | `GET /buildings/{building_id}/floors/{floor_name}/graph` |
| 최단 경로 | `GET /buildings/{building_id}/floors/{floor_name}/route?start_node_id=...&end_node_id=...` |

현재 앱의 기본 데모 건물은 `test-center`입니다. API 전체 계약은 서버 실행 뒤 [http://127.0.0.1:8001/docs](http://127.0.0.1:8001/docs)에서 확인할 수 있습니다.

## 문서

- [로컬 개발 가이드](docs/local-development-guide.md): 플랫폼별 실행, API 주소, 문제 해결
- [FastAPI 요청 흐름](docs/fastapi-request-flow.md): Router → Query/Service → SQLite 구조
- [프로젝트 개요](docs/navigation-overview.md): 프로젝트 목적과 결정 기록
- [기술 스택](docs/research/06-tech-stack.md): 조사 근거와 기술 선택

## 데이터셋 작업

더현대서울 원천 데이터셋 추출·미리보기 작업은 앱 실행과 별개입니다. 관련 산출물과 스크립트는 [thehyundai_indoor_navigation_dataset/README.md](thehyundai_indoor_navigation_dataset/README.md)를 참고하세요.

## 개발 규칙

- API 계약은 Flutter 클라이언트가 소비하는 JSON 형태를 우선으로 유지합니다.
- 개발 DB 초기화와 시드는 서버 시작 시가 아니라 `python -m scripts.reset_and_seed`로 실행합니다.
- Docker Compose 개발 환경은 컨테이너 시작 command에서 `python -m scripts.reset_and_seed`를 실행합니다.
- CI/CD 자동화는 `.github/workflows/`에서 관리합니다.
