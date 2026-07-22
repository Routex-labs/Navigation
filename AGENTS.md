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
    - **저장소 위치를 하드코딩하지 않는다.** 먼저 현재 저장소의 루트를 찾아 이후 창의 작업 폴더와 `sql/`·`args/` 로그 위치의 기준으로 쓴다. 다른 로컬에서는 이 값이 예를 들어 `C:\work\Navigation` 또는 `~/src/Navigation`일 수 있다.
    ```powershell
    # Windows PowerShell — 저장소 안에서 실행
    $repoRoot = git rev-parse --show-toplevel
    $clientRoot = Join-Path $repoRoot 'client'
    ```
    ```bash
    # macOS/Linux shell — 저장소 안에서 실행
    repo_root="$(git rev-parse --show-toplevel)"
    client_root="$repo_root/client"
    ```
    - docker/flutter/uvicorn 출력에 한글이 섞이므로 **콘솔·출력·로그 인코딩을 UTF-8로 고정**한다. 안 하면 로그가 UTF-16이나 깨진 문자로 남는다. 창을 열 때 프렐류드로 박아 둔다.
    ```powershell
    # Windows — 백엔드 창(저장소 루트), 프론트 창(client). -Command로 UTF-8 고정 후 -NoExit로 남는다.
    Start-Process powershell -ArgumentList '-NoExit','-Command','[Console]::OutputEncoding=[Text.Encoding]::UTF8; $OutputEncoding=[Text.Encoding]::UTF8; $PSDefaultParameterValues[''Out-File:Encoding'']=''utf8''' -WorkingDirectory $repoRoot
    Start-Process powershell -ArgumentList '-NoExit','-Command','[Console]::OutputEncoding=[Text.Encoding]::UTF8; $OutputEncoding=[Text.Encoding]::UTF8; $PSDefaultParameterValues[''Out-File:Encoding'']=''utf8''' -WorkingDirectory $clientRoot
    ```
    ```bash
    # macOS — Terminal 창 2개 (macOS 터미널은 기본 UTF-8이라 별도 설정 불필요)
    osascript -e "tell app \"Terminal\" to do script \"cd '$repo_root'\""
    osascript -e "tell app \"Terminal\" to do script \"cd '$client_root'\""
    ```

  **2) 백엔드 창에서 순서대로 실행 — Docker (`docker info`가 정상일 때)**
    - SQL·HTTP JSON 진단은 개발 실행의 기본값이다. Compose가 `NAV_SQL_ECHO=1`·`NAV_HTTP_CAPTURE=1`과 `sql/`·`args/` 볼륨을 자동 설정하므로, 사람이 환경변수를 따로 입력하지 않는다.
    ```powershell
    # Windows — UTF-8 로그. PS 5.1의 Tee-Object는 파일을 UTF-16으로 쓰므로 패스스루로 tee한다.
    docker compose up --build backend 2>&1 | ForEach-Object { $_; $_ | Out-File backend.log -Append -Encoding utf8 }
    ```
    ```bash
    # macOS — tee는 UTF-8
    docker compose up --build backend 2>&1 | tee backend.log
    ```

  **2') Docker가 없거나 실행 중이 아니면 — 로컬 Python 대체 (백엔드 폴더에서 한 줄씩)**
    ```powershell
    # Windows (backend 폴더로 연 창에서)
    python -m venv .venv
    .\.venv\Scripts\Activate.ps1
    python -m pip install -r requirements.txt
    python -m scripts.seed.reset_and_seed
    $env:NAV_SQL_ECHO = '1'
    $env:NAV_HTTP_CAPTURE = '1'
    uvicorn app.main:app --reload --reload-dir app --host 0.0.0.0 --port 8001 2>&1 | ForEach-Object { $_; $_ | Out-File ..\backend.log -Append -Encoding utf8 }
    ```
    ```bash
    # macOS (backend 폴더로 연 창에서)
    python3 -m venv .venv
    source .venv/bin/activate
    pip install -r requirements.txt
    python -m scripts.seed.reset_and_seed
    export NAV_SQL_ECHO=1
    export NAV_HTTP_CAPTURE=1
    uvicorn app.main:app --reload --reload-dir app --host 0.0.0.0 --port 8001 2>&1 | tee ../backend.log
    ```
    - `--reload-dir app`으로 **감시 범위를 `app/` 코드로만 한정**한다. 안 그러면 `tests/`·`resources/` 편집도 리로드를 트리거해 서버가 리로드되다 죽는다(Windows에서 특히). Docker 백엔드는 `--reload`가 없어 이 문제가 없다.

  **3) 프론트 창에서 실행 (client 폴더에서)**
    ```powershell
    # Windows — UTF-8 로그 패스스루
    flutter run -d chrome 2>&1 | ForEach-Object { $_; $_ | Out-File frontend.log -Append -Encoding utf8 }
    ```
    ```bash
    # macOS
    flutter run -d chrome 2>&1 | tee frontend.log
    ```

  - Docker 사용 가능 여부는 `docker info`가 정상 응답하는지로 판단한다. 실패하면 위 로컬 Python 대체 경로로 백엔드를 띄운다.
  - **백엔드·프론트 창 모두 UTF-8로 실행한다.** Windows는 (a) 창 프렐류드로 콘솔 인코딩을 UTF-8로 고정하고(콘솔 표시·네이티브 출력 디코딩), (b) 로그 파일은 `Tee-Object` 대신 **패스스루 `... | ForEach-Object { $_; $_ | Out-File <log> -Append -Encoding utf8 }`** 로 쓴다(PS 5.1 Tee-Object는 파일을 UTF-16으로 씀). 소스 파일·리소스 JSON도 UTF-8로 저장한다. 한글 로그가 UTF-16/깨짐으로 남으면 에이전트가 로그를 못 읽는다.
  - 사용자는 창에서 실시간 로그를 보고, 에이전트는 `backend.log`·`frontend.log`를 읽어 추적한다. (두 로그 파일은 `.gitignore`에 둔다.)
  - 백엔드 개발 실행 뒤에는 에이전트가 `sql/queries.sql`과 `args/*.json`도 함께 확인한다. 두 디렉터리도 `.gitignore`에 두며, 로그를 위한 파일/환경변수를 사용자에게 수동으로 만들거나 설정하게 하지 않는다.

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
