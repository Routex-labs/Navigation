# 07. Dockerfile 단일화, 운영 seed 분리, readiness/liveness 정리

브랜치(제안): `chore/ops-docker-seed-cleanup`

## 배경

Dockerfile이 저장소 루트와 `backend/`에 유사한 내용으로 중복되어 있어 한쪽만 수정하면 배포 경로에 따라 다른
이미지가 생성될 수 있다. 문서상으로는 시드를 서버 실행과 분리한다고 되어 있지만, 실제 Dockerfile은 컨테이너
시작 때마다 `reset-and-seed`를 실행해 문서와 실행 정책이 어긋난다. 그 외에도 CORS/TrustedHost 설정, 개발
진단 로그와 운영 로그 분리, request body 크기 제한 등 운영 안정화 항목이 함께 남아 있다.

## 범위(백엔드만)

`Dockerfile`(루트/`backend/`), `docker-compose.yml`, FastAPI 설정(`backend/app/main.py`, 환경별 Settings).

## 작업 항목

1. 루트와 `backend/`의 Dockerfile 내용을 비교해 실제 배포에 쓰는 경로를 하나로 고정하고 나머지를 제거한다(`docs/guide/gcp-instance.md`의 실제 배포 절차와 대조).
2. 운영 컨테이너 시작 시 `reset-and-seed`를 제거하고, 별도 migration 또는 seed job(수동 실행 또는 1회성 Job)으로 옮긴다.
3. 로컬 개발용 seed(`AGENTS.md`의 `python -m scripts.seed.reset_and_seed`)는 그대로 유지하되, 운영 이미지 entrypoint와 분리되어 있음을 문서화한다.
4. 환경별 Settings(dev/staging/prod)를 도입하거나 기존 구조를 확인한다.
5. CORS·TrustedHost를 운영 환경 기준으로 설정한다(wildcard 금지).
6. 개발 진단 로그(`NAV_SQL_ECHO`, `NAV_HTTP_CAPTURE` 등 `backend/app/sql/`·`backend/app/args/` 산출물)가 운영 빌드에서 기본 비활성화되는지 확인한다.
7. request body 크기 제한을 추가한다.
8. `/health`의 readiness와 liveness를 분리한다(06번의 warm 상태 분리와 함께 정리).
9. 글리프(폰트) 엔드포인트의 path traversal 방어를 점검한다(`backend/app/routers/fonts.py`).
10. README와 실제 실행 명령이 일치하는지 확인하고, 불일치가 있으면 README를 갱신한다.

## 완료 기준

- [ ] 운영 이미지 생성 Dockerfile이 하나만 존재한다.
- [ ] 애플리케이션 컨테이너 재시작이 DB 초기화를 발생시키지 않는다.
- [ ] 운영에서 wildcard CORS를 사용하지 않는다.
- [ ] 운영에서 요청/SQL 본문이 평문 파일로 기록되지 않는다.
- [ ] 타일/그래프 요청 폭주가 무제한 메모리 증가를 만들지 않는다(06번과 연계 확인).
- [ ] README와 실제 실행 명령이 일치한다.

## 참고

- 원문서 22페이지 "P2-4. 테스트·Docker·실행 정책이 이중화됨"(백엔드 부분), 28~29페이지 "Phase 5. 운영 안정화와 보안".
- Flutter 테스트 경로 이중화(`client/test` vs `client/tests`)는 이 문서 범위가 아니다.
