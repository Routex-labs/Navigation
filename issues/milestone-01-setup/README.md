# Milestone 1 · 프로젝트 초기 설정 (Project Setup)

실제 코드가 0인 현재 상태에서 **Flutter 클라이언트 + FastAPI 백엔드 골격**을 세우고,
둘이 서로 통신하는 것까지 확인하는 마일스톤이다.
측위 알고리즘(PDR·Particle Filter)이나 RAG 같은 본 기능은 **이 마일스톤 범위가 아니다.**
목표는 "팀원 누구나 clone 후 앱과 서버를 띄우고, 앱이 서버 응답을 화면에 찍는다"까지다.

## 목표 (Definition of Done)

- `client/`에서 `flutter run`으로 앱이 실행되고 지도(빈 평면도)가 뜬다.
- `api/`에서 `uvicorn`으로 서버가 뜨고 `/health`, `/buildings`가 응답한다.
- 앱이 서버의 `/buildings`를 호출해 받은 데이터를 화면에 표시한다(end-to-end 연결 확인).
- README만 보고 새 팀원이 두 서비스를 모두 로컬에서 띄울 수 있다.

## 스택 근거

상세 스택·버전·디렉토리 구조는 [docs/research/06-tech-stack.md](../../docs/research/06-tech-stack.md)와
[VERSION.md](../../VERSION.md)를 단일 출처로 따른다. 이 마일스톤은 그 설계를 **실제 파일로 옮기는** 단계다.

## 이슈 목록

| ID | 컴포넌트 | 상태 | GitHub | 제목 |
|---|---|---|---|---|
| M1-001 | client | Draft | - | [Flutter 클라이언트 골격 생성](M1-001-frontend-flutter-scaffold.md) |
| M1-002 | api | Draft | - | [FastAPI 백엔드 골격 생성](M1-002-backend-fastapi-scaffold.md) |
| M1-003 | client / api | Draft | - | [프론트–백엔드 연동 스모크 테스트](M1-003-integration-smoke-test.md) |

## 진행 순서

```
M1-001 (Flutter 골격)  ─┐
                        ├─► M1-003 (연동 확인)
M1-002 (FastAPI 골격)  ─┘
```

M1-001과 M1-002는 병렬로 진행 가능하다. M1-003은 둘 다 끝나야 시작한다.

## 작성/관리 규칙

- 각 이슈 `.md`는 GitHub 이슈 본문으로 그대로 옮길 수 있게 작성한다.
- 상태는 `Draft → Ready → Created → Done` 순으로 갱신한다.
- GitHub 이슈로 만든 뒤 `GitHub` 칸에 번호를 적는다.
- 식별자는 마일스톤 단위로 `M1-NNN` 형식을 쓴다(마일스톤마다 001부터 독립).
  전역 목록은 [issues/issue.md](../issue.md)에서 마일스톤 디렉토리로 링크해 관리한다.
