# GCP 배포 (Cloud Run)

> 백엔드 FastAPI 서버를 Google Cloud Run에 배포하고 관리하는 방법을 정리합니다.
> Flutter 클라이언트는 로컬에서 실행하고 이 서버 주소를 바라봅니다.

> **현재 상태(2026-07-24): 배포된 서비스 없음.** 이전 `navigation-api` 서비스는
> 비용 관리를 위해 삭제되었고, 아래 URL·설정 표는 재배포 시의 **기준 스펙**이다.
> `gcloud run services list`가 비어 있는 것이 정상이며, 재배포는 [재배포](#재배포)를 따른다.

## AI 질의(임베딩) 때문에 주의할 배포 스펙

`/query/ai`는 문장 임베딩 모델(`jhgan/ko-sroberta-multitask`)을 로드한다. 이게 배포
스펙 두 가지를 좌우한다. 근거는 로컬 실측이다.

- **메모리는 최소 2 GiB.** 모델 로드 + 인코딩 1회 후 프로세스 RSS가 **약 775 MB**로
  측정됐다. 표에 남아 있던 512 MiB로는 첫 AI 질의에서 OOM으로 컨테이너가 죽는다.
- **이미지에서 torch는 CPU 전용 휠로 고정한다.** PyPI 기본 인덱스는 리눅스에서 CUDA
  빌드 torch를 주는데, `nvidia-*`/`triton`까지 합쳐 압축 기준 약 2.9 GB다. Cloud Run
  컨테이너에는 GPU가 없어 전부 죽은 용량이므로 `Dockerfile`이 CPU 휠(약 168 MB)로
  고정한다. CUDA는 "GPU 필수"가 아니라 "GPU용 라이브러리를 동봉"한다는 뜻이라,
  CPU 휠로 바꿔도 추론 결과·속도는 동일하다.
- **모델은 빌드 시점에 이미지에 굽는다.** `Dockerfile`이 `scripts.warm_embedding_model`로
  모델(약 420 MB)을 미리 받아 캐시에 넣는다. Cloud Run 파일시스템은 휘발성이라, 굽지
  않으면 콜드 스타트마다 첫 질의가 다운로드를 기다린다.
- **`NAV_WARM_EMBEDDING=1`은 이미지에 이미 설정돼 있다.** 기동 직후 백그라운드 데몬
  스레드가 모델을 올려 첫 질의 대기(약 6초)를 없앤다. 다만 Cloud Run 기본 설정은 요청
  처리 중이 아닐 때 CPU를 조이므로, 이 워밍이 기동 직후에 끝나려면 `--min-instances 1`
  또는 startup CPU boost가 필요하다(둘 다 과금).

## 배포된 서비스 요약

| 항목 | 값 |
|---|---|
| 서비스 이름 | `navigation-api` |
| 프로젝트 ID | `navigation-demo-2026` |
| 리전 | `asia-northeast3` (서울) |
| 서비스 URL | `https://navigation-api-465890645804.asia-northeast3.run.app` |
| 인증 | 없음 (`--allow-unauthenticated`, 데모용 공개) |
| 메모리 | 2 GiB (임베딩 모델 상주 약 775 MB 실측 반영, 최소 요구) |
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

- **DB는 휘발성 SQLite**입니다. 컨테이너 시작은 기본적으로 서버만 띄우고 시드하지 않습니다
  (재시작이 DB를 초기화하지 않게 하기 위함 — `backend/Dockerfile` 참고). 다만 Cloud Run
  파일시스템은 휘발성이라 매 시작마다 빈 DB로 뜨므로, **이 데모에서는 환경변수
  `NAV_SEED_ON_START=1`을 명시해** 기동 직전 1회 `scripts.seed.reset_and_seed`로 더현대 서울
  데이터(B6~6F, 12개 층)를 적재합니다. 이 앱은 읽기 위주라 데모에 문제없습니다.
- **영속 DB(Cloud SQL 등)로 전환하면 `NAV_SEED_ON_START`를 켜지 마세요** — 시드는 배포와
  분리된 1회성 작업으로 돌립니다(로컬: `python -m scripts.seed.reset_and_seed`). 그래야
  재시작이 데이터를 지우지 않습니다.
- 시드 후 데이터가 사라지는 쓰기 작업이 필요해지면 Cloud SQL 등 외부 DB로 전환해야 합니다.

## 운영 환경변수(보안·안정화)

| 환경변수 | 기본값 | 운영 권장 |
|---|---|---|
| `NAV_ENVIRONMENT` | `development` | `production` (CORS 기본을 잠근다) |
| `NAV_CORS_ORIGINS` | (없음) | Flutter 앱 도메인을 콤마로 명시 (와일드카드 금지) |
| `NAV_ALLOWED_HOSTS` | (없음) | 서비스 도메인 지정 시 Host 헤더를 제한 (비면 미적용) |
| `NAV_MAX_REQUEST_BODY_BYTES` | `1000000` | 필요 시 조정. 초과 본문은 413 |
| `NAV_SEED_ON_START` | (없음/미시드) | 휘발성 DB 데모에서만 `1` |

> `NAV_ENVIRONMENT=production`인데 `NAV_CORS_ORIGINS`를 비워 두면 교차 출처 요청이 전부
> 막힙니다(경고 로그가 남습니다). Flutter 웹을 다른 도메인에서 붙인다면 반드시 origin을 넣으세요.

## 재배포

로컬 코드 기준으로 이미지를 다시 빌드(Cloud Build)하고 배포합니다. 로컬 Docker 불필요.
저장소 루트에서 실행합니다.

```powershell
Set-Location backend
gcloud run deploy navigation-api `
  --source . `
  --region asia-northeast3 `
  --allow-unauthenticated `
  --memory 2Gi `
  --min-instances 1 `
  --set-env-vars NAV_SEED_ON_START=1
```

> `--memory 2Gi`는 임베딩 모델 상주 때문에 필수다(위 "주의할 배포 스펙" 참고).
> `--source .`는 `backend/`에서 실행하므로 Cloud Build가 `backend/Dockerfile`을 그대로 쓴다
> (운영 이미지는 이 하나뿐 — 옛 루트 `Dockerfile`은 제거됐다). CPU 전용 torch 고정과 모델
> 굽기가 자동 적용된다. 최초 빌드는 이미지가 커서(수 GB) 몇 분 걸린다.
> `NAV_SEED_ON_START=1`은 휘발성 DB 데모라 매 시작 시 시드하기 위한 것이다 — 영속 DB로
> 바꾸면 빼라(위 "운영 환경변수" 참고).

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
