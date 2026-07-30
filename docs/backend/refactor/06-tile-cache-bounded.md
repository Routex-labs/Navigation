# 06. MVT 타일 캐시 bounded LRU + single-flight

브랜치(제안): `perf/tile-cache-bounded`

## 배경

백엔드 MVT(벡터 타일) 캐시가 프로세스 전역 `dict`에 모든 타일 바이트를 무제한 저장한다. 최대 항목 수, 최대
byte 수, TTL, 건물별 quota, 키 단위 동시 작업 제어가 전혀 없다. 워밍업 스레드와 실제 요청이 같은 타일을
동시에 인코딩할 수도 있고, 건물·층이 늘어나면 시작 시 전체 워밍업 정책이 CPU·메모리를 크게 증가시킬 수 있다.

## 범위(백엔드만)

`backend/app/repositories/tile_queries.py`(또는 실제 MVT 캐시 구현) 및 관련 라우터.

## 작업 항목

1. byte 크기 기반 LRU 캐시로 교체한다(`max_entries`, `max_bytes` 설정 가능).
2. 키 단위 single-flight를 적용해 동일 타일의 동시 인코딩을 한 번으로 합친다.
3. 캐시 접근 인터페이스를 통일한다(get/set/invalidate 공통 함수).
4. 캐시 키에 03번에서 만든 데이터 revision을 포함해, revision 변경 시 기존 타일이 자동 무효화되게 한다.
5. 시작 시 전체 워밍업 대신 기본 층·인기 층 중심의 선택적 워밍업으로 바꾼다.
6. readiness와 warm 상태를 분리한다(워밍업 실패가 `/health`의 readiness 실패로 오인되지 않게).
7. hit/miss/eviction/current bytes 메트릭을 추가한다.
8. 다중 worker(uvicorn 여러 프로세스) 환경에서 프로세스별 중복 캐시 비용을 측정하고 문서화한다.

## 완료 기준

- [ ] 캐시가 설정된 최대 메모리(byte)를 초과하지 않는다.
- [ ] 동일 키에 대한 동시 요청이 한 번만 인코딩을 실행한다.
- [ ] 데이터 revision 변경 시 기존 타일이 무효화된다.
- [ ] 워밍업 실패가 readiness 실패로 오인되지 않는다.

## 참고

- 원문서 13~14페이지 "P1-5. 무제한 타일 캐시와 중복 인코딩".
- 03번에서 만든 graph revision을 캐시 키로 재사용한다.
