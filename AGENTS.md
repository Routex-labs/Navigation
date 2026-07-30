# 작업 규칙

## 판단력 — 새 기능을 만들 때

새로운 기능을 만들 때는 다음을 지킨다.

- **AI 결과를 내 말로 풀어서 설명한다.** 생성된 코드/설계를 그대로 받아들이지 않고, 사용자가 자기 말로 이해하고 설명할 수 있도록 근거와 동작을 풀어 준다.
- **정상 동작보다 실패 조건을 먼저 생각한다.** "잘 되는 경우"가 아니라 어디서 깨지는지, 어떤 입력·상태에서 실패하는지를 먼저 짚는다.
- **AI보다 먼저 검증 기준을 정한다.** 구현에 들어가기 전에 "무엇이 충족되면 맞다고 볼지" 검증 기준을 먼저 합의하고, 그 기준으로 결과를 확인한다.

## 프로젝트 세션 규칙

이 저장소는 Flutter 클라이언트 + FastAPI·SQLAlchemy·SQLite 백엔드 데모다. 개발자는 Windows(PowerShell)와 macOS 양쪽에 있다. 작업할 때:

- **개발 실행은 사용자가 볼 수 있는 창 2개(백엔드·프론트)를 foreground로 띄우고, 동시에 로그를 파일로 tee 해서 에이전트도 추적한다.** 백그라운드로 숨기지 않는다.
  - 쉘 버전(PowerShell 5.1/7, bash/zsh)에 따라 `&&`·`;` 체이닝이 깨질 수 있으므로 **명령은 체이닝하지 말고 한 줄씩 순서대로 실행한다.** `cd A && B` 대신 창을 해당 폴더에서 연 뒤 명령만 실행한다. (파이프 `|`는 버전 무관하게 동작하므로 tee에는 파이프를 쓴다.)

  **1) 창 먼저 연다 (해당 작업 폴더에서 + UTF-8 고정)**
    - **저장소 위치를 하드코딩하지 않는다.** 먼저 현재 저장소의 루트를 찾아 이후 창의 작업 폴더 기준으로 쓴다. 다른 로컬에서는 이 값이 예를 들어 `C:\work\Navigation` 또는 `~/src/Navigation`일 수 있다.
    ```powershell
    # Windows PowerShell — 저장소 안에서 실행
    $repoRoot = git rev-parse --show-toplevel
    $backendRoot = Join-Path $repoRoot 'backend'
    $clientRoot = Join-Path $repoRoot 'client'
    ```
    ```bash
    # macOS/Linux shell — 저장소 안에서 실행
    repo_root="$(git rev-parse --show-toplevel)"
    backend_root="$repo_root/backend"
    client_root="$repo_root/client"
    ```
    - Python/flutter/uvicorn 출력에 한글이 섞이므로 **콘솔·출력·로그 인코딩을 UTF-8로 고정**한다. 안 하면 로그가 UTF-16이나 깨진 문자로 남는다. 창을 열 때 프렐류드로 박아 둔다.
    ```powershell
    # Windows — 백엔드 창(backend), 프론트 창(client). -Command로 UTF-8 고정 후 -NoExit로 남는다.
    Start-Process powershell -ArgumentList '-NoExit','-Command','[Console]::OutputEncoding=[Text.Encoding]::UTF8; $OutputEncoding=[Text.Encoding]::UTF8; $PSDefaultParameterValues[''Out-File:Encoding'']=''utf8''' -WorkingDirectory $backendRoot
    Start-Process powershell -ArgumentList '-NoExit','-Command','[Console]::OutputEncoding=[Text.Encoding]::UTF8; $OutputEncoding=[Text.Encoding]::UTF8; $PSDefaultParameterValues[''Out-File:Encoding'']=''utf8''' -WorkingDirectory $clientRoot
    ```
    ```bash
    # macOS — Terminal 창 2개 (macOS 터미널은 기본 UTF-8이라 별도 설정 불필요)
    osascript -e "tell app \"Terminal\" to do script \"cd '$backend_root'\""
    osascript -e "tell app \"Terminal\" to do script \"cd '$client_root'\""
    ```

  **2) 백엔드 창에서 순서대로 실행 — 로컬 Python이 기본**
    - Docker 이미지 콜드 빌드·기동 비용을 피하기 위해 **일상 개발과 기능 검증은 로컬 가상환경으로 실행한다.**
    - 최초 1회 또는 `requirements*.txt`가 바뀌었을 때:
    ```powershell
    # Windows (backend 폴더)
    py -3.12 -m venv .venv
    .\.venv\Scripts\Activate.ps1
    python -m pip install -r requirements.txt
    python -m scripts.warm_embedding_model
    ```
    ```bash
    # macOS (backend 폴더)
    python3 -m venv .venv
    source .venv/bin/activate
    python -m pip install -r requirements.txt
    python -m scripts.warm_embedding_model
    ```
    - `warm_embedding_model`은 `/query/ai`용 임베딩 모델(약 420MB)을 로컬 HF 캐시에 미리 받아 둔다. **빼먹으면 첫 AI 질의가 다운로드를 통째로 기다린다**(실측 3분 29초, 그동안 프론트는 "찾는 중…"만 돈다). 캐시가 이미 있으면 즉시 끝난다.
    - 검증할 때마다:
    ```powershell
    # Windows — 콘솔엔 전부, 파일엔 WARNING/ERROR + 트레이스백만. PS 5.1 Tee-Object는 UTF-16으로 쓰므로 패스스루로 tee한다.
    .\.venv\Scripts\Activate.ps1
    python -m scripts.seed.reset_and_seed
    $env:NAV_WARM_EMBEDDING = '1'
    python -m uvicorn app.main:app --reload --reload-dir app --host 0.0.0.0 --port 8001 2>&1 | ForEach-Object { $_; if ($_ -match '^(\d{4}-\d\d-\d\d|INFO:|WARNING:|ERROR:|CRITICAL:|DEBUG:)') { $keep = ($_ -cmatch 'ERROR|WARNING|CRITICAL') }; if ($keep) { $_ | Out-File ..\backend-local.log -Append -Encoding utf8 } }
    ```
    ```bash
    # macOS — tee로 콘솔엔 전부, awk로 파일엔 WARNING/ERROR + 트레이스백만
    source .venv/bin/activate
    python -m scripts.seed.reset_and_seed
    export NAV_WARM_EMBEDDING=1
    python -m uvicorn app.main:app --reload --reload-dir app --host 0.0.0.0 --port 8001 2>&1 | tee >(awk '/^([0-9]{4}-[0-9][0-9]-[0-9][0-9]|INFO:|WARNING:|ERROR:|CRITICAL:|DEBUG:)/{keep=/ERROR|WARNING|CRITICAL/} keep' > ../backend-local.log)
    ```
    - `NAV_WARM_EMBEDDING=1`은 기동 직후 백그라운드로 임베딩 모델을 올려 첫 `/query/ai`의 로드 대기(캐시 히트여도 약 6.5초)를 없앤다. 기본값이 꺼짐이라 **안 켜면 재시작할 때마다 첫 AI 질의가 그 시간을 뒤집어쓴다.** AI 질의를 안 건드리는 작업이면 생략해도 되지만, 켜 두면 400MB대 메모리를 상주시킨다는 점만 알아 둔다.
    - `--reload-dir app`으로 **감시 범위를 `app/` 코드로만 한정**한다. 안 그러면 `tests/`·`resources/` 편집도 리로드를 트리거해 서버가 리로드되다 죽는다(Windows에서 특히).

  **2') Docker는 배포 준비 때만 사용**
    - 배포 이미지·컨테이너 환경 호환성을 명시적으로 확인할 때만 저장소 루트에서 `docker compose up --build backend`를 실행한다.
    - 평소 기능 검증에서는 Docker 가용 여부를 확인하지 않고 위 로컬 Python 경로를 사용한다. 실제 Cloud Run 배포 절차는 `docs/guide/gcp-instance.md`를 따른다.

  **3) 프론트 창에서 실행 (client 폴더에서)**
    ```powershell
    # Windows — UTF-8 로그 패스스루
    flutter run -d chrome 2>&1 | ForEach-Object { $_; $_ | Out-File frontend.log -Append -Encoding utf8 }
    ```
    ```bash
    # macOS
    flutter run -d chrome 2>&1 | tee frontend.log
    ```

  - **백엔드·프론트 창 모두 UTF-8로 실행한다.** Windows는 (a) 창 프렐류드로 콘솔 인코딩을 UTF-8로 고정하고(콘솔 표시·네이티브 출력 디코딩), (b) 로그 파일은 `Tee-Object` 대신 **패스스루 `... | ForEach-Object { $_; ... | Out-File <log> -Append -Encoding utf8 }`** 로 쓴다(PS 5.1 Tee-Object는 파일을 UTF-16으로 씀). 소스 파일·리소스 JSON도 UTF-8로 저장한다. 한글 로그가 UTF-16/깨짐으로 남으면 에이전트가 로그를 못 읽는다.
  - 사용자는 창에서 실시간 로그를 보고, 에이전트는 `backend-local.log`·`frontend.log`를 읽어 추적한다. (두 로그 파일은 `.gitignore`에 둔다.)
  - **백엔드 로그는 콘솔엔 전부 남기고, 파일(`backend-local.log`)엔 `WARNING`/`ERROR`/`CRITICAL` 줄과 그 뒤 트레이스백만 남긴다.** uvicorn access 로그(요청·상태 코드)는 INFO라 파일엔 안 쌓이고 창에서만 실시간으로 본다 — 파일은 문제 상황만 모아 두는 용도다. 필터는 "새 로그 줄(타임스탬프/`INFO:`·`ERROR:` 등으로 시작)을 만나면 레벨을 다시 판정하고, 들여쓰기된 후속 줄(트레이스백 스택)은 직전 판정을 그대로 잇는" 방식이라 예외 스택이 잘리지 않는다. 파일에서도 요청 흐름까지 다 보고 싶으면 필터를 빼고 `... | Out-File ..\backend-local.log -Append -Encoding utf8`(mac은 `tee`)로 되돌린다.
  - 우리 코드(`app.*`)의 예외 로깅은 `app/core/logging.py`가 잡는다: 5xx는 `ERROR`, 4xx·422 검증 실패는 `WARNING`. 미처리 500은 uvicorn.error가 트레이스백을 남긴다. 파일 기반 SQL/요청 진단 캡처(옛 `NAV_SQL_ECHO`/`NAV_HTTP_CAPTURE`)는 제거됐다 — 요청 단위 상세 로그가 필요하면 `NAV_LOG_LEVEL=DEBUG`로 실행한다.

- **경로 계산은 클라이언트 온디바이스(Dijkstra, `client/lib/domain/dijkstra.dart`)가 담당한다.** 서버는 그래프(nodes·edges)만 제공하며, 최단 경로 로직을 서버로 옮기지 않는다.
- **API 계약(JSON)은 Flutter 클라이언트가 소비하는 형태를 우선으로 유지한다.** 백엔드 응답 스키마를 바꾸면 클라이언트의 모델·파싱도 함께 확인한다.
- **문서·커밋·PR은 한국어로 작성한다.** 기존 문서 톤을 따른다.

## 코드 검토 원칙 — 위험 기준으로 무게를 다르게

모든 코드를 똑같은 무게로 읽지 않는다. **피해 규모(blast radius)** 를 기준으로 판단한다.

- **낮은 위험 → 동작과 테스트 중심으로 확인.** 문구, 내부 정렬, 이미 검증된 패턴, 쉽게 롤백 가능한 변경 등은 테스트와 동작 결과로 확인하고 넘어간다.
- **높은 위험 → 핵심 코드를 직접 깊게 검토.** 결제, 권한, 인증, 개인정보, 삭제, 마이그레이션 등 되돌리기 어렵거나 피해가 큰 영역은 코드를 직접 정독한다.

## 커밋 규칙

- **논리적으로 관련된 작업 단위로 나누어 커밋한다.** 성격이 다른 변경(예: 기능·문서 정리·파일 이동·삭제)은 한 커밋에 섞지 않고 각각 분리한다.
- **제목은 한 줄**, `feat:`, `fix:`, `chore:`, `docs:`, `refactor:` 등 타입 접두사로 시작한다. 내용은 **한글**로 쓴다.
- 필요하면 제목 다음 줄(빈 줄 뒤)에 **1~2줄 정도 설명**을 덧붙인다. 불필요하면 제목만.
- **`Co-Authored-By` 및 협업자 Claude 태그는 붙이지 않는다.**

## PR 작성 규칙

PR을 만들 때 `.github/PULL_REQUEST_TEMPLATE.md`의 5섹션 형식을 따른다.

- Co-Authored-By 및 협업자 Claude 태그 금지 (PR·커밋 모두)
- 리뷰는 작성자 본인을 제외한 모든 참가자에게 요청
- 각 섹션은 간결하게. 팀원이 직접 설명할 수 있는 2~3줄 정도로 쓴다.
- "남은 위험" 섹션에서는 이번 변경으로 더 이상 참조되지 않는 코드나 노후화된 README.md 등 문서도 함께 찾아 적는다.
