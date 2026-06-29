# Navigation

> 경진대회용 Navigation 프로젝트 - 경로 안내, 사용자 흐름, 데모 구현을 한 저장소에서 관리한다.

## 디렉토리 구조

```text
.
|-- .gitignore
|-- .github/
|   `-- workflows/
|       `-- project-automation.yml   # 이슈/PR 이벤트 -> Projects 보드 Status 자동 이동
|-- docs/
|   |-- navigation-overview.md        # 프로젝트 개요와 결정 기록
|   `-- research-notes.md             # 조사/근거/레퍼런스 정리
|-- prompt/                           # CI/CD 자동화 작업별 프롬프트
|   |-- create-issues.md              # cicd-issues.md -> GitHub 이슈 생성
|   |-- design-cicd-issues.md         # CI/CD 파이프라인 설계 -> 이슈 명세
|   |-- implement-issue.md            # 보드 최우선 이슈를 GitHub Flow로 구현
|   |-- label-cd.md                   # CD 라벨 생성/업데이트
|   `-- label-ci.md                   # CI 라벨 생성/업데이트
|-- issues/
|   `-- issue.md                      # 마일스톤별 이슈 초안과 설명
|-- AGENTS.md                         # 에이전트 작업 라우팅 / 규칙
|-- HISTORY.md                        # 변경 이력
|-- VERSION.md                        # 버전 정보
`-- README.md                         # 이 문서
```

## 초기 운영 규칙

- 프로젝트 기획, 기술 선택, 일정 변경은 `docs/navigation-overview.md`에 먼저 남긴다.
- 자동화 작업은 `AGENTS.md`의 라우팅 표를 기준으로 `prompt/`의 전문을 먼저 읽고 수행한다.
- 큰 병합이나 버전 변경은 `HISTORY.md`와 `VERSION.md`를 함께 갱신한다.
- 마일스톤별 GitHub 이슈 초안과 설명은 `issues/issue.md`에 먼저 정리한다.
