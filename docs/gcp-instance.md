# GCP 배포 (Cloud Run)

> 백엔드 FastAPI 서버를 Google Cloud Run에 배포하고 관리하는 방법을 정리합니다.
> Flutter 클라이언트는 로컬에서 실행하고 이 서버 주소를 바라봅니다.

## 배포된 서비스 요약

| 항목 | 값 |
|---|---|
| 서비스 이름 | `navigation-api` |
| 프로젝트 ID | `navigation-demo-2026` |
| 리전 | `asia-northeast3` (서울) |
| 서비스 URL | `https://navigation-api-465890645804.asia-northeast3.run.app` |
| 인증 | 없음 (`--allow-unauthenticated`, 데모용 공개) |
| 메모리 | 512 MiB |
| CPU | 1 vCPU |
| 최소 인스턴스 | 1 (콜드 스타트 방지) |
| 최대 인스턴스 | 100 (기본값) |
| 동시 요청 | 80 (기본값) |
| 요청 타임아웃 | 300초 |
| 컨테이너 포트 | 8080 (`$PORT`) |

> URL은 두 형태가 모두 동작합니다:
> `https://navigation-api-465890645804.asia-northeast3.run.app` (프로젝트 번호형),
> `https://navigation-api-xqghilybuq-du.a.run.app` (해시형).

## 콘솔에서 관리 (웹, CLI 불필요)

- 콘솔 홈: <https://console.cloud.google.com>
- 이 서비스: <https://console.cloud.google.com/run/detail/asia-northeast3/navigation-api?project=navigation-demo-2026>
- 결제/사용량: <https://console.cloud.google.com/billing>

서비스 상세 화면 탭:

| 탭 | 내용 |
|---|---|
| 측정항목(METRICS) | 요청 수, 지연시간, CPU/메모리 사용량 |
| 개정(REVISIONS) | 배포 이력, 각 개정의 리소스·인스턴스·환경변수 |
| 로그(LOGS) | 컨테이너 실시간 로그 (시드 및 uvicorn 출력) |
| YAML | 전체 설정 선언형 스펙 |

설정 변경: 상단 **"새 버전 편집 및 배포(Edit & Deploy New Revision)"** 버튼에서 메모리/CPU/인스턴스/환경변수를 폼으로 수정하면 새 개정이 배포됩니다.

## 아키텍처 특성

- **DB는 휘발성 SQLite**입니다. 컨테이너가 시작될 때마다 `scripts.seed.reset_and_seed`로 더현대 서울 데이터(1F~4F)를 다시 적재합니다. 이 앱은 읽기 위주라 데모에 문제없습니다.
- 시드 후 데이터가 사라지는 쓰기 작업이 필요해지면 Cloud SQL 등 외부 DB로 전환해야 합니다.

## 재배포

로컬 코드 기준으로 이미지를 다시 빌드(Cloud Build)하고 배포합니다. 로컬 Docker 불필요.

```powershell
cd D:\Navigation\backend
gcloud run deploy navigation-api `
  --source . `
  --region asia-northeast3 `
  --allow-unauthenticated `
  --min-instances 1
```

## 상태 확인

```powershell
# 헬스체크
Invoke-RestMethod https://navigation-api-465890645804.asia-northeast3.run.app/health
# → status : ok

# 건물 목록 (시드 확인)
Invoke-RestMethod https://navigation-api-465890645804.asia-northeast3.run.app/buildings

# 현재 설정 조회
gcloud run services describe navigation-api --region asia-northeast3
```

## Flutter 클라이언트 연결

```powershell
cd D:\Navigation\client
flutter run --dart-define=API_BASE_URL=https://navigation-api-465890645804.asia-northeast3.run.app
```

TMAP/VWorld 키를 함께 쓰려면 `--dart-define=TMAP_APP_KEY=...`, `--dart-define=VWORLD_API_KEY=...`를 추가합니다.
키를 생략하면 각각 목업 경로 / OSM 배경지도로 자동 대체됩니다.

## 비용 관리

`--min-instances 1`은 대기 인스턴스를 항상 1개 유지하므로 소액이 지속 과금됩니다.

```powershell
# 시연 후: 대기 인스턴스 끄기 (첫 요청만 몇 초 느려지고 이후 유휴 시 무료)
gcloud run services update navigation-api --region asia-northeast3 --min-instances 0

# 서비스 완전 삭제
gcloud run services delete navigation-api --region asia-northeast3
```

## gcloud CLI 참고

- 설치 위치: `C:\Users\HANSUNG\AppData\Local\Google\Cloud SDK`
- 결제 계정 연결: `gcloud billing projects link navigation-demo-2026 --billing-account=<ACCOUNT_ID>`
- 필요한 API: `run.googleapis.com`, `cloudbuild.googleapis.com`, `artifactregistry.googleapis.com`
