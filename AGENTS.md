# 작업 규칙

## 판단력 — 새 기능을 만들 때

새로운 기능을 만들 때는 다음을 지킨다.

- **AI 결과를 내 말로 풀어서 설명한다.** 생성된 코드/설계를 그대로 받아들이지 않고, 사용자가 자기 말로 이해하고 설명할 수 있도록 근거와 동작을 풀어 준다.
- **정상 동작보다 실패 조건을 먼저 생각한다.** "잘 되는 경우"가 아니라 어디서 깨지는지, 어떤 입력·상태에서 실패하는지를 먼저 짚는다.
- **AI보다 먼저 검증 기준을 정한다.** 구현에 들어가기 전에 "무엇이 충족되면 맞다고 볼지" 검증 기준을 먼저 합의하고, 그 기준으로 결과를 확인한다.

## 프로젝트 세션 규칙

이 저장소는 Flutter 클라이언트 + FastAPI·SQLAlchemy·SQLite 백엔드 데모다. 개발자는 Windows(PowerShell)와 macOS 양쪽에 있다.

- **백엔드는 배포된 Cloud Run에 붙고, 로컬에선 클라이언트만 띄운다.** 백엔드를 직접 고치지 않는 한 로컬 서버는 실행하지 않는다.
  - 최초 1회 `client/config.example.json`을 `config.local.json`으로 복사하고 배포 백엔드 주소(`API_BASE_URL`)·키를 채운다. (`config.local.json`은 `.gitignore`라 커밋되지 않는다.)
  - `client/` 폴더에서 실행한다. 창은 foreground로 띄우고(백그라운드로 숨기지 않는다), 명령은 체이닝하지 말고 한 줄씩 실행한다(쉘 버전에 따라 `&&`·`;`가 깨질 수 있음).
    ```powershell
    # Windows — UTF-8 콘솔 창에서. 로그는 패스스루로 frontend.log에 남긴다(PS 5.1 Tee-Object는 UTF-16).
    flutter run --dart-define-from-file=config.local.json 2>&1 | ForEach-Object { $_; $_ | Out-File frontend.log -Append -Encoding utf8 }
    ```
    ```bash
    # macOS
    flutter run --dart-define-from-file=config.local.json 2>&1 | tee frontend.log
    ```
  - 사용자는 창에서 실시간 로그를, 에이전트는 `frontend.log`(`.gitignore`)를 읽어 추적한다. 주입 값은 컴파일 타임에 박히므로 URL·키를 바꾸면 hot reload가 아니라 `flutter run`을 재시작한다.
  - 한글 로그가 깨지지 않게 Windows는 콘솔·출력 인코딩을 UTF-8로 고정한 창에서 실행하고, 소스·리소스 JSON도 UTF-8로 저장한다.

- **백엔드를 직접 수정·검증해야 할 때만** 로컬 Python으로 띄운다. venv·시드·uvicorn·로그 필터·Docker 절차는 [로컬 개발 가이드](docs/guide/local-development-guide.md)를, 실제 Cloud Run 배포는 [GCP 배포 문서](docs/guide/gcp-instance.md)를 따른다.

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
