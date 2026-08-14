# 08. 의존성·모델 재현성 및 API 키 보호

브랜치(제안): `chore/dependency-supply-chain`

## 배경

Python 의존성 중 일부가 하한만 지정되어 있어 빌드 시점에 따라 다른 버전이 설치될 수 있다. 테스트 도구가
운영 requirements에 포함되어 있으면 운영 이미지 용량과 공격 표면이 불필요하게 늘어난다. Hugging Face
임베딩 모델도 모델 이름만 고정하고 revision을 고정하지 않으면 시점에 따라 다른 모델 artifact를 받을 수
있다. 또한 TMAP/VWorld 키가 클라이언트 바이너리에 직접 포함되는 문제는, 백엔드 proxy로 옮기는 방안을
여기서 함께 검토한다.

## 범위(백엔드만)

`backend/requirements*.txt`, `backend/scripts/warm_embedding_model.py`, Dockerfile base image, GitHub
Actions, 외부 지도 API 호출 경로.

## 작업 항목

1. 운영 requirements와 테스트 requirements를 분리한다(`requirements.txt` vs `requirements-dev.txt` 등).
2. `requirements.in`과 lock 파일(pip-compile 등)을 도입하거나, 최소한 버전 상한을 명시한다.
3. hash 기반 dependency 고정을 검토한다(`pip install --require-hashes`).
4. Hugging Face 모델 revision을 고정한다(`warm_embedding_model.py`에서 모델 이름과 함께 commit hash 지정).
5. 모델 artifact checksum 검증을 추가한다(선택 — 캐시 히트 여부와 별개로 무결성 확인).
6. Docker base image의 digest를 고정한다(`FROM python:3.12-slim@sha256:...`).
7. GitHub Actions에서 사용하는 액션의 SHA pinning 여부를 점검한다(`uses: actions/checkout@<sha>`).
8. `pip-audit`(01번에서 이미 CI에 추가했다면 여기서는 확인만) 결과를 리뷰한다.
9. TMAP/VWorld 등 외부 지도·경로 API 호출을 백엔드 proxy로 옮길지 결정한다. 옮기지 않는다면:
   - 키별 일일 quota 설정
   - 사용량 이상 경보
   - 개발/스테이징/운영 키 분리
   - 키 교체 절차 문서화
   옮긴다면 새 proxy 엔드포인트를 `backend/app/routers/`에 추가하고 클라이언트 쪽 후속 작업(별도 브랜치)이 필요함을 PR에 명시한다.

## 완료 기준

- [x] 운영 이미지에 테스트 전용 패키지가 포함되지 않는다. → `pytest`·`httpx`를 `requirements.txt`에서 빼 `requirements-ci.txt`로 옮겼다. Dockerfile은 `requirements.txt`만 설치하므로 테스트 도구가 이미지에서 빠진다.
- [x] 같은 소스로 동일 dependency와 model artifact를 재현할 수 있다. → 운영 requirements 전 항목에 상한을 뒀고, HF 모델 revision을 commit hash로 고정했다. base image digest 고정은 07(Dockerfile 소유)에 위임(아래 "결정 기록" 참고).
- [x] `pip-audit` 결과에 처리되지 않은 높은 심각도 취약점이 없다. → 남은 취약점은 starlette 7건뿐이고 모두 CI ignore 목록에 문서화된 상태다. 완전 해소는 FastAPI 대규모 업그레이드가 필요해 후속 과제로 남긴다(아래 "결정 기록").
- [x] 외부 API 키 보호 방안이 결정되고 문서화된다. → proxy 미이전 + quota/키 분리/교체 절차를 기본 권장으로 정하고 아래에 기록했다.

## 결정 기록 (chore/dependency-supply-chain에서 반영)

### 1) requirements 3분할

- `requirements.txt` — 운영 런타임만. Dockerfile이 이 파일만 설치한다.
- `requirements-ci.txt` — CI 게이트·테스트 실행 도구(`pytest`, `httpx`, `ruff`, `mypy`, `pip-audit`).
- `requirements-dev.txt` — 노트북 분석 도구(`pandas`, `matplotlib`, `jupyter` 등).

`pytest`·`httpx`는 원래 `requirements.txt`에 있어 운영 이미지에 딸려 들어갔다. 백엔드는 외부로 HTTP를 직접 호출하지 않으므로(`httpx`는 FastAPI TestClient 전용) 둘 다 테스트 계층으로 이동. CI는 이미 `requirements-ci.txt`를 설치하므로 `pytest` 실행에 영향 없다.

### 2) 버전 상한 명시 (재현성)

하한만 있던 항목에 상한을 붙였다: `pydantic-settings==2.14.*`, `sqlalchemy==2.0.*`, `numpy>=1.26,<3`. 나머지는 이미 `==X.Y.*`로 고정돼 있었다. CI/테스트 도구도 `pytest==9.1.*`, `httpx==0.28.*`로 고정.

- **정확한 lock은 후속 과제.** 진짜 비트 단위 재현(전이 의존성까지 고정)은 `pip-compile --generate-hashes`로 `requirements.lock`을 만들고 `pip install --require-hashes`로 설치해야 한다. 이번에는 도입하지 않았다(전이 의존성 hash 유지보수 비용 + 로컬 개발 마찰). 범위 상한만으로도 "같은 소스가 같은 minor를 받는" 수준의 재현성은 확보된다.

### 3) HF 모델 revision 고정

`app/repositories/query_semantic.py`에 `_MODEL_REVISION = "8fca7c9c98c26599be0e14b9916b11a756a26f19"`를 추가하고 `_load_model()`의 두 `SentenceTransformer(...)` 호출에 `revision=`을 배선했다. `warm_embedding_model.py`도 같은 상수를 임포트해 워밍 캐시와 런타임 로드가 동일 artifact를 가리키게 했다.

- 값 출처: `huggingface.co/api/models/jhgan/ko-sroberta-multitask/refs`의 `main` targetCommit. 이 저장소는 단일 `main` 브랜치라 이 해시가 사실상의 안정 릴리스다.
- upstream이 `main`을 갱신해도 우리는 이 커밋을 계속 받는다. 모델을 의도적으로 올릴 때만 이 상수를 바꾼다.

### 4) Docker base image digest 고정 → 07에 위임

Dockerfile은 07 소유라 직접 수정하지 않는다. 07(또는 오케스트레이터)이 아래 한 줄로 바꾸면 된다.

```dockerfile
# 현재
FROM python:3.12-slim
# 권장(digest 고정)
FROM python:3.12-slim@sha256:57cd7c3a7a273101a6485ba99423ee568157882804b1124b4dd04266317710de
```

- 위 digest는 조회 시점(2026-07-31) `python:3.12-slim` 태그의 multi-arch manifest-list digest다. 태그는 이동하므로 07이 적용 직전 `docker manifest inspect python:3.12-slim` 또는 Docker Hub API로 재확인할 것을 권장.

### 5) GitHub Actions SHA 고정

`.github/workflows/ci.yml`의 액션을 이동 가능한 태그 → 커밋 SHA로 고정했다(주석에 태그 병기).

- `actions/checkout@v4` → `11d5960a326750d5838078e36cf38b85af677262`
- `actions/setup-python@v5` → `a26af69be951a213d495a4c3e4e4022e16d87065`
- `subosito/flutter-action@v2` → `1a449444c387b1966244ae4d4f8c696479add0b2`

`project-automation.yml`은 외부 액션을 쓰지 않고 `gh api`만 호출하므로 대상 아님.

### 6) pip-audit 결과 (운영 requirements 대상)

`pip-audit -r requirements.txt` 결과 취약 패키지는 `starlette 0.46.2` 하나뿐이며 7개 CVE가 걸린다.

| ID | CVE | 최초 수정 버전 |
| --- | --- | --- |
| PYSEC-2026-1941 | CVE-2025-54121 | 0.47.2 |
| PYSEC-2026-1942 | CVE-2025-62727 | 0.49.1 |
| PYSEC-2026-161  | CVE-2026-48710 | 1.0.1 |
| PYSEC-2026-2280 | CVE-2026-48817 | 1.1.0 |
| PYSEC-2026-2281 | CVE-2026-48818 | 1.1.0 |
| PYSEC-2026-248  | CVE-2026-54282 | 1.3.0 |
| PYSEC-2026-249  | CVE-2026-54283 | 1.3.1 |

- 7건 모두 CI(`ci.yml`)의 `--ignore-vuln`에 이미 등록돼 문서화된 상태다 → "미처리(unhandled) 높은 심각도 취약점"은 없다.
- **완전 해소는 이번 범위에서 하지 않았다.** 전부 없애려면 `starlette>=1.3.1`이 필요한데, `fastapi 0.115`가 `starlette<0.47`을 핀한다. starlette 1.x를 받으려면 FastAPI를 대폭 올려야 하고 이는 API 계약(라우팅·미들웨어·응답 스키마)에 blast radius가 큰 변경이다. **FastAPI+starlette 동반 업그레이드를 별도 브랜치의 후속 과제로 분리**하고, 그때 클라이언트 응답 파싱 회귀까지 함께 확인할 것을 권장한다.

### 7) 외부 지도 API 키 보호 — proxy 미이전 (기본 권장)

TMAP/VWorld 키는 현재 클라이언트가 직접 사용한다(백엔드에는 외부 지도 API 호출 경로가 없다 — `backend/app`에 TMAP/VWorld 호출 코드 없음 확인). 이번 결정은 **백엔드 proxy로 옮기지 않는다**이며 근거와 대체 통제는 다음과 같다.

- **근거**: proxy 이전은 (a) 새 인증·레이트리밋을 갖춘 백엔드 엔드포인트, (b) 클라이언트의 지도/경로 호출 경로 전면 수정, (c) 서버 대역폭·지연 증가를 수반한다. 08은 백엔드 공급망 범위이고 클라이언트 후속이 필수라 범위를 넘는다.
- **대체 통제(문서화 = 이 절)**:
  - **키별 일일 quota**: TMAP·VWorld 콘솔에서 앱/키 단위 일일 호출 상한을 실사용 + 여유분으로 설정. 남용 시 과금·차단을 상한이 막는다.
  - **사용량 이상 경보**: 콘솔 알림(또는 사용량 API 폴링)으로 임계 초과 시 통지. 급증을 조기에 잡는다.
  - **개발/스테이징/운영 키 분리**: 환경별 별도 키로 발급해 한 환경 유출이 전 환경에 번지지 않게 하고, 환경별 quota·경보를 독립 운용.
  - **키 교체 절차**: 유출·정기 교체 시 (1) 새 키 발급 → (2) 환경 설정에 배포 → (3) 신키 트래픽 확인 → (4) 구키 폐기. 클라이언트는 키를 빌드/설정으로 주입하므로 재배포로 교체.
  - **도메인/레퍼러 제한**: 콘솔에서 허용 도메인(운영 프론트 호스트)으로 키 사용을 제한해 키 노출 시 임의 출처 사용을 줄인다.
- **재검토 트리거**: 위 통제로도 남용이 반복되거나, 키를 노출 없이 완전 은닉해야 하는 요구가 생기면 그때 proxy 이전을 별도 과제로 승격. 그 경우 `backend/app/routers/`에 proxy 엔드포인트 추가 + 클라이언트 호출 경로 수정(별도 브랜치)이 필요하다.

## 재점검 (2026-08-14) — 소스는 고쳤지만 배포되는 물건은 확인하지 않았다

위 완료 기준 넷은 그대로 유효하다. 그런데 넷 모두 **소스(`requirements.txt`)를 대상으로**
확인한 것이고, 실제로 배포되는 이미지 안을 들여다본 적은 없다. 그 틈에서 셋이 나왔다.
A는 이번에 고쳤고, B·C는 남아 있다.

### A. CI가 감사하는 의존성 그래프가 배포 이미지와 달랐다 — 해결됨

`ci.yml`은 리눅스 러너에서 `pip install -r requirements.txt`와 `pip-audit -r requirements.txt`를
돈다. `sentence-transformers`가 `torch>=1.11`만 요구하므로, PyPI 기본 인덱스는 리눅스에서
CUDA 빌드를 고른다. 실제 CI 로그에 이렇게 찍힌다.

```
Collecting cuda-toolkit==13.0.3 (from ... torch>=1.11.0->sentence-transformers==5.6.*)
Collecting nvidia-cudnn-cu13==9.20.0.48
Collecting nvidia-cusparselt-cu13==0.8.1
Collecting nvidia-nccl-cu13==2.29.7
Collecting nvidia-nvshmem-cu13==3.4.5
```

배포 이미지는 정반대다. `backend/Dockerfile`이 CPU 전용 인덱스에서 `torch==2.7.0`을 먼저
고정하고 그 위에 `requirements.txt`를 깐다(그 이유는 Dockerfile 주석에 있다).

즉 **감사받는 그래프와 배포되는 그래프가 달랐다.** CI가 녹색이어도 이미지 안의 torch 계열에
대해서는 아무 말도 하지 않은 셈이다.

같은 뿌리에서 시간도 샜다. 백엔드 잡 236초 중 **129초(55%)** 가 이 3 GB를 옮기는 데 쓰였다.

| 단계 | 시간 |
|---|---|
| `setup-python` (pip 캐시 3,033,176,230 B 복원) | 46s |
| `pip install -r requirements.txt -r requirements-ci.txt` | 83s |
| mypy | 38s |
| pytest | 55s |
| pip-audit | 11s |

**고친 방법.** `ci.yml`이 Dockerfile과 같은 순서로 깐다 — CPU 인덱스에서 `torch==2.7.0`을 먼저
고정하면 `sentence-transformers`의 `torch>=1.11`이 이미 충족돼 CUDA 휠을 안 끌어온다.
`cache-dependency-path`에 `ci.yml`도 넣었다. 설치 명령이 바뀌면 캐시 내용도 바뀌는데
requirements 해시만 키로 쓰면 옛 3 GB 캐시가 계속 복원되기 때문이다.

- **남은 빚 하나.** torch 버전이 `ci.yml`과 `backend/Dockerfile` 두 곳에 적힌다. 한쪽만 올리면
  다시 갈라진다(이 PR에서 지운 루트 Dockerfile이 정확히 그 실패였다). 양쪽 주석이 서로를
  가리키게 해 뒀지만, 근본은 아래 B다 — **감사 대상을 빌드한 이미지의 `pip freeze`로 바꾸면**
  CI가 이미지를 흉내 낼 필요 자체가 없어진다.

### B. 배포 산출물 자체를 검사하지 않는다

검사 대상이 전부 소스다. 이미지 SBOM도, 이미지 취약점 스캔도 없다. A가 보여주듯 소스 감사가
통과해도 이미지 내용은 다를 수 있다.

- 고치는 방향: CD가 만든 이미지에 SBOM 생성과 스캔을 붙이고, 예외로 승인되지 않은
  High/Critical은 배포를 막는다. Artifact Registry의 컨테이너 스캔을 켜는 것이 가장 싼
  출발점이다. CD가 무엇을 어떻게 빌드하는지는 [GCP 배포](../../guide/gcp-instance.md)의
  「CD가 무엇을 빌드하나」가 단일 출처다.

### C. ignore 목록에 소유자와 만료일이 없다

`ci.yml`의 `--ignore-vuln` 7건은 위 6절에 근거가 적혀 있으므로 "설명 없는 예외"는 아니다.
그러나 **언제까지인지가 없다.** FastAPI 대규모 업그레이드가 미뤄지는 동안 이 목록은 조용히
영구화된다. 지금 CI의 의미는 "알려진 취약점 0"이 아니라 "예외로 뺀 것 말고는 0"이다.

- 고치는 방향: 예외를 CI YAML에서 떼어 별도 파일로 옮기고 항목마다 소유자·근거·만료일·추적
  이슈를 둔다. 만료 검사를 CI 단계로 넣으면 만료가 곧 빌드 실패가 된다.

```yaml
security_exceptions:
  - id: PYSEC-2026-1941
    package: starlette
    owner: backend
    rationale: "fastapi 0.115가 starlette<0.47을 핀한다"
    fixed_in: 0.47.2
    expires: 2026-11-30
    tracking: "FastAPI+starlette 동반 업그레이드(위 6절)"
```

### 곁들여 — 운영 Dockerfile이 두 벌이었다

루트 `Dockerfile`이 지워졌다 되살아나 있었고 base image digest가 고정돼 있지 않았다. 실제
CD 트리거를 조회해 빌드 컨텍스트가 `backend`임을 확인한 뒤 지웠다. **콘솔에만 있는 설정은
저장소와 함께 움직이지 않는다** — 그래서 지금은 [GCP 배포](../../guide/gcp-instance.md)에
트리거가 도는 명령과 재확인 방법을 적어 뒀다.

## 참고

- 원문서 23페이지 "6. 보안·공급망 점검"(6.1, 6.2).
- 이 문서는 8개 작업 중 마지막으로, 앞선 항목들이 이미 안정화된 뒤 진행해도 무방하다(의존성이 없다면 더 일찍 병렬로 진행해도 됨).
