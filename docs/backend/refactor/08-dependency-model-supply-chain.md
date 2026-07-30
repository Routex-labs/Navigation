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

- [ ] 운영 이미지에 테스트 전용 패키지가 포함되지 않는다.
- [ ] 같은 소스로 동일 dependency와 model artifact를 재현할 수 있다(HF revision 고정, base image digest 고정).
- [ ] `pip-audit` 결과에 처리되지 않은 높은 심각도 취약점이 없다.
- [ ] 외부 API 키 보호 방안(proxy 이전 또는 quota/분리)이 결정되고 문서화된다.

## 참고

- 원문서 23페이지 "6. 보안·공급망 점검"(6.1, 6.2).
- 이 문서는 8개 작업 중 마지막으로, 앞선 항목들이 이미 안정화된 뒤 진행해도 무방하다(의존성이 없다면 더 일찍 병렬로 진행해도 됨).
