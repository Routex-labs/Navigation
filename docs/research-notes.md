# Navigation 사전조사 노트

최종 갱신일: 2026-07-15

현재 사전조사는 구현 방향에 직접 필요한 내용만 유지한다.

## 현재 방향

> Flutter 클라이언트가 FastAPI API를 호출하고, FastAPI는 SQLite에 적재된 실내 지도·매장·경로
> 그래프 데이터를 제공한다.

PDR, Particle Filter, 실내/외 자동 전환, RAG는 초기 아이디어였지만 현재 필수 범위가 아니다.
관련 상세 조사 문서는 제거했고, 후속 후보로만 [research/06-tech-stack.md](research/06-tech-stack.md)에 남겼다.

## 남은 조사 문서

| 문서 | 내용 |
|---|---|
| [기술 스택과 데이터 포맷](research/06-tech-stack.md) | 현재 Flutter/FastAPI/SQLite 구조와 확장 후보 |

## 운영 기준

- 실행 방법은 루트 [README.md](../README.md)와 [로컬 개발 가이드](local-development-guide.md)를 따른다.
- 확정된 설계 결정은 [navigation-overview.md](navigation-overview.md)에 반영한다.
- 큰 방향 전환은 [../HISTORY.md](../HISTORY.md)에 남긴다.
