# 01. 백엔드 테스트/린트 CI 게이트 복구

브랜치(제안): `chore/backend-ci-gate`

## 배경

감사 문서(Phase 0)는 "테스트가 작성되어 있어도 CI에서 실행되지 않을 수 있다"는 문제를 Flutter 쪽에서
지적하지만, 백엔드도 동일한 위험이 있다 — 이후 작업(02~08)이 회귀 없이 진행되려면 먼저 백엔드 테스트·린트가
GitHub Actions에서 실제로 강제되는지 확인하고, 기준선(baseline)을 남겨야 한다.

## 범위(백엔드만)

- `backend/` 디렉터리의 pytest, ruff, (mypy 또는 pyright), pip-audit 실행 여부 점검
- 지정 기준 커밋 시점 테스트 결과를 기준선으로 저장 (테스트 파일 수, 케이스 수)
- 라우팅·PDR 관련 회귀 테스트는 클라이언트 영역이므로 이 작업 범위에서 제외한다

## 작업 항목

1. 현재 `.github/workflows/`에서 백엔드 관련 job이 `backend/tests/`(또는 실제 테스트 루트)를 빠짐없이 실행하는지 확인한다.
2. 다음 게이트를 CI에 추가하거나 확인한다.
   - `ruff check`
   - `ruff format --check` (또는 프로젝트가 쓰는 포매터)
   - `mypy` 또는 `pyright` (아직 없다면 도입 여부를 먼저 결정 — 기존 타입 힌트 커버리지에 따라 범위를 좁게 시작해도 됨)
   - `pytest`
   - `pip-audit`
3. 테스트 케이스 수를 CI 로그에 출력하고, 기준선 대비 급감 시 실패하는 간단한 카운트 체크를 추가한다(선택 사항 — 과하면 스킵 가능).
4. 지정 커밋(`3b2a5cb` 또는 현재 `main`)에서 백엔드 pytest 전체 실행 결과를 로컬로 확인해 PR 설명에 통과 로그를 남긴다.
5. 실패한 테스트를 임시로 skip하거나 CI 경로에서 제외하지 않는다 — 실패하면 원인을 고쳐서 통과시킨다.

## 완료 기준

- [x] `backend/` 테스트 전체가 CI에서 실행된다(하위 폴더 누락 없음).
- [x] ruff·mypy·pytest·pip-audit이 PR 체크로 노출된다.
- [ ] 필수 상태 체크 없이 `main`에 머지할 수 없도록 브랜치 보호 설정을 확인한다 —
      **GitHub 저장소 설정 권한이 필요해 코드로는 못 한다. 사람이 Settings → Branches에서
      `Backend (FastAPI)`·`Frontend (Flutter)`를 required status check로 지정해야 한다.**
- [x] 기준선 테스트 통과 로그가 PR에 남는다.

## 적용 결과 (2026-07-30)

### 실제로 있던 문제

CI가 `pytest tests/unit`·`pytest tests/integration`으로 **하위 폴더를 하드코딩**하고 있었다.
지금은 모든 테스트가 그 두 폴더에 있어 증상이 없지만, `tests/e2e/`나 `tests/` 바로 아래에
파일을 추가하면 조용히 실행에서 빠진다. 임시 파일로 재현해 확인했다 — 새 방식 357개 수집,
옛 방식 356개(누락). 감사 문서가 지적한 "테스트는 있는데 CI가 안 돌린다"와 같은 구조다.

### 도입한 게이트 (`.github/workflows/ci.yml`의 backend job)

| 게이트 | 명령 | 설정 |
| --- | --- | --- |
| lint | `ruff check` | `pyproject.toml` — E/F/I/UP/B, line-length 120 |
| format | `ruff format --check` | 전체 적용 완료(38파일 기계적 변경) |
| 타입 | `mypy` | `app/` 대상 점진 도입 |
| 테스트 | `pytest` | `testpaths = ["tests"]`로 경로 드리프트 차단 |
| 취약점 | `pip-audit -r requirements.txt` | 알려진 7건만 제외, 새 항목은 실패 |

### 기준선 (커밋 `1522958` 기준, 로컬 실측)

```
ruff check          : All checks passed!
ruff format --check : 78 files already formatted
mypy                : Success: no issues found in 33 source files
pytest              : 353 passed, 3 skipped
pip-audit           : No known vulnerabilities found, 9 ignored
```

### 판단이 필요했던 항목

- **B008(FastAPI `Depends()` 기본 인자)** — 10건 전부 오탐. FastAPI 정상 사용법이라
  `extend-immutable-calls`로 제외.
- **B905(`zip(strict=)`)·UP042(`StrEnum`)** — 런타임 의미가 바뀐다(조용한 절단 → 예외,
  `str()` 출력 변경). 근거를 남기고 제외했고, 필요하면 별도 작업으로 다룬다.
- **starlette 취약점 9건(고유 7 ID)** — `fastapi 0.115`가 `starlette<0.47`을 요구하는데
  수정본은 `0.47.2`부터라 FastAPI를 함께 올려야 해소된다. 이 작업 범위를 넘어
  [08번](08-dependency-model-supply-chain.md)으로 넘긴다. 그동안 게이트가 무력해지지 않도록
  `--ignore-vuln`으로 **해당 ID만** 제외해, 새 취약점은 여전히 CI를 실패시킨다.
- **CI 도구 위치** — `requirements-ci.txt`로 분리했다. 운영 이미지에 lint·타입 도구를
  넣지 않기 위해서이며, 08번의 requirements 분리 방향과 같다.

## 참고

- 원문서 3페이지 "Phase 0. 기준선과 테스트 게이트 복구" 중 백엔드 해당 부분.
- 클라이언트 테스트 구조 통합(`client/test/` vs `client/tests/`)은 이 작업 범위가 아니다.
