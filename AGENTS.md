# AGENTS.md

이 리포지토리의 CI/CD 자동화 작업은 `prompt/` 디렉토리에 작업별 프롬프트로 정의되어 있다.
에이전트는 아래 작업 중 하나를 요청받으면 **해당 프롬프트 파일을 먼저 읽고**, 그 안의
Role / Task / Execution Logic / Constraints를 그대로 따른다.

## 프롬프트 라우팅 표

| 요청 의도 | 읽을 프롬프트 파일 | 요약 |
|---|---|---|
| CI 관련 라벨 생성/업데이트 (`ci`, `testing`, `static-analysis`) | [prompt/label-ci.md](prompt/label-ci.md) | `gh label`로 CI 라벨 일괄 생성/수정 |
| CD 관련 라벨 생성/업데이트 (`cd`, `docker`, `e2e-testing`, `infrastructure`) | [prompt/label-cd.md](prompt/label-cd.md) | `gh label`로 CD 라벨 일괄 생성/수정 |
| GitHub Actions CI/CD 파이프라인 설계 -> `cicd-issues.md` 작성 | [prompt/design-cicd-issues.md](prompt/design-cicd-issues.md) | 아키텍처 분석 후 CI/CD 이슈 명세를 파일로 발행 |
| `cicd-issues.md` -> GitHub 이슈 자동 생성 + Kanban `Todo` 할당 | [prompt/create-issues.md](prompt/create-issues.md) | 이슈 파일 파싱 후 `gh issue create`로 순차 생성 |
| Projects 보드 최우선 이슈를 GitHub Flow로 구현 | [prompt/implement-issue.md](prompt/implement-issue.md) | `Todo` 최상단 이슈를 골라 PR까지 완료 |

## 권장 실행 순서

`label-ci` / `label-cd`로 라벨을 준비한 뒤, `design-cicd-issues`로 CI/CD 작업을 쪼개고,
`create-issues`로 이슈를 발행한 다음 `implement-issue`로 하나씩 구현한다.

## Projects 보드 자동화

이슈/PR 이벤트에 맞춰 Projects 보드(#2 · Navigation 개발 보드)의 Status를 옮기는 작업은
[.github/workflows/project-automation.yml](.github/workflows/project-automation.yml)이 **결정형(에이전트 없이 GraphQL)**으로 처리한다.

- 이슈 열림/재오픈 → `Todo`, 이슈 닫힘 → `Done`
- PR 열림/ready/재오픈 → (PR이 `Closes #N`으로 닫는 이슈를) `Review (PR)`
- PR 머지 → (닫는 이슈를) `Done`

최초 1회 설정:

- `PROJECT_PAT`: `project` + `repo` 스코프 classic PAT. **저장소(Repository) 시크릿**으로 등록한다.
  (Navigation은 private이라 조직 시크릿은 현재 플랜에서 적용되지 않는다.)
- 시크릿이 없으면 워크플로는 경고만 남기고 무동작(no-op)한다.

## 마일스톤 이슈 초안

마일스톤별로 만들 GitHub 이슈의 초안과 설명은 `issues/` 디렉토리에 기록한다.
각 이슈는 왜 필요한지, 어떤 작업을 포함하는지, 어떤 기준이면 완료인지까지 적는다.

- 작성 규칙과 템플릿은 [issues/issue.md](issues/issue.md)를 따른다.
- 식별자는 `ISSUE-NNN` 형식, 상태는 `Draft / Ready / Created / Done` 중 하나로 기록한다.

## 사용 규칙

- 작업 시작 전 라우팅 표에서 의도에 맞는 파일을 찾아 전문을 읽는다.
- 프롬프트 파일의 지시가 이 문서와 충돌하면 프롬프트 파일을 우선한다.
- 새 자동화 프롬프트를 추가할 때는 `prompt/`에 파일을 만들고 위 표에 한 줄을 추가한다.
- 설명과 커밋 메시지는 한국어, 코드와 식별자는 영어로 작성한다.
