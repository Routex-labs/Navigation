# Navigation

> 실외에서 실내까지 이어지는 경로 안내를 위한 Flutter 클라이언트와 FastAPI 백엔드 데모입니다.

처음 실행한다면 [로컬 개발 가이드](docs/guide/local-development-guide.md)부터 보세요. Windows, macOS, Android 에뮬레이터/실기기, iOS 시뮬레이터/실기기 실행 방법을 분리해서 정리해 두었습니다.

## 구성

```text
client/  Flutter 앱 (Android · iOS · macOS)
backend/ FastAPI · SQLAlchemy · SQLite 백엔드
docs/    실행, 구조, 조사 문서
```

```text
Flutter 앱 ──HTTP──> FastAPI ──> SQLite
                    │
                    └── 실내 지도 · 매장 · 그래프 API (경로 계산은 클라이언트 온디바이스)
```

## 빠른 시작

상세 실행법은 [로컬 개발 가이드](docs/guide/local-development-guide.md)를 따릅니다. 요약하면 백엔드를 먼저 띄우고, Flutter 앱은 `client/`에서 실행합니다.

**백엔드 — 로컬 Python (기본)**

```powershell
Set-Location backend
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python -m scripts.seed.reset_and_seed
$env:NAV_SQL_ECHO = '1'
$env:NAV_HTTP_CAPTURE = '1'
python -m uvicorn app.main:app --reload --reload-dir app --host 0.0.0.0 --port 8001 2>&1 | ForEach-Object { $_; $_ | Out-File ..\backend-local.log -Append -Encoding utf8 }
```

서버 상태를 확인합니다.

```powershell
Invoke-RestMethod http://127.0.0.1:8001/health
```

**분석 노트북 (선택)** — `backend/notebooks/`의 평가 노트북을 돌릴 때만 필요합니다.

```powershell
python -m pip install -r requirements-dev.txt
```

**Flutter 앱 — Android 에뮬레이터 예시**

```powershell
Set-Location client
flutter pub get
flutter devices
flutter run
```

Android 에뮬레이터는 기본값 `http://10.0.2.2:8001`을 사용하므로 별도 API 주소 지정이 필요 없습니다. 실기기, iOS, macOS 실행 방법과 네트워크·HTTP 주의사항은 [로컬 개발 가이드](docs/guide/local-development-guide.md)를 따르세요.

Docker Compose는 배포 이미지·컨테이너 환경을 확인할 때만 사용합니다. 실제 Cloud Run 배포는
[GCP 배포 문서](docs/guide/gcp-instance.md)를 따릅니다.

## 주요 API

| 용도 | 경로 |
|---|---|
| 상태 확인 | `GET /health` |
| 건물 목록 | `GET /buildings` |
| 층 지도 | `GET /buildings/{building_id}/floors/{floor_name}` (매장·POI·`navigation_graph` 포함) |
| 층 그래프 | `GET /buildings/{building_id}/floors/{floor_name}/graph` (한 층 내부 간선) |
| 건물 전체 그래프 | `GET /buildings/{building_id}/graph?vertical=auto\|elevator\|escalator` (전 층 + 수직 전이 간선, 층 간 경로용) |
| 목적지 경량 검색 | `POST /query/destination` |
| 위치·층 정보 검색 | `POST /query/info` |
| AI 의미 검색 | `POST /query/ai` |

최단 경로는 서버가 계산하지 않습니다. 클라이언트가 그래프(nodes·edges)로 온디바이스 Dijkstra(`client/lib/domain/dijkstra.dart`)를 실행합니다. **한 층 안 경로는 층 지도 응답의 `navigation_graph`**로, **층 간 경로는 건물 전체 그래프**(`/{id}/graph`, 수직 전이 간선 포함)로 계산합니다.

현재 앱의 기본 데모 건물은 `thehyundai-seoul`이며, 기본 시드는 Studio B6~6F 12개 층 데이터를 적재합니다. API 전체 계약은 서버 실행 뒤 [http://127.0.0.1:8001/docs](http://127.0.0.1:8001/docs)에서 확인할 수 있습니다.

## 문서

- [로컬 개발 가이드](docs/guide/local-development-guide.md): 플랫폼별 실행, API 주소, 문제 해결
- [FastAPI 요청 흐름](docs/backend/fastapi-request-flow.md): Router → Query → SQLite 구조

## 데이터셋 작업

더현대서울 원천 데이터셋 추출·미리보기 작업은 앱 실행과 별개입니다. 관련 산출물과 스크립트는 [thehyundai_indoor_navigation_dataset/README.md](thehyundai_indoor_navigation_dataset/README.md)를 참고하세요.

## 개발 규칙

- API 계약은 Flutter 클라이언트가 소비하는 JSON 형태를 우선으로 유지합니다.
- 개발 DB 초기화와 시드는 서버 시작 시가 아니라 `python -m scripts.seed.reset_and_seed`로 실행합니다.
- 일상 개발·기능 검증은 로컬 Python을 사용하고, Docker는 배포 환경 호환성 확인에만 사용합니다.
- CI/CD 자동화는 `.github/workflows/`에서 관리합니다.
