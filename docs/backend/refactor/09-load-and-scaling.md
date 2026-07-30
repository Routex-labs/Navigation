# 09. 부하·동시성·로깅 검토

이 문서는 "실제 사용자가 몰릴 때 백엔드에 무엇이 먼저 터지는가"를 정리한 검토 노트다.
01~08과 달리 단일 작업 단위가 아니라, 실행 모델을 이해하고 우선순위를 잡기 위한 근거다.
관련 조치는 03(그래프 무결성/PRAGMA)·06(타일 캐시)·07(운영 설정)로 이어진다.

## 실행 모델 (현재)

- **uvicorn worker 1개** — `docker-compose.yml`이 `--workers`를 주지 않아 프로세스·이벤트 루프 1개.
- **라우트 핸들러가 전부 동기 `def`** — FastAPI가 anyio 스레드풀(기본 상한 40)에서 실행한다.
  즉 동시 요청은 최대 ~40개까지 병렬, 나머지는 큐에서 대기. GIL 때문에 순수 파이썬 CPU 구간은
  사실상 직렬(단, SQLite C확장·torch/faiss·I/O는 GIL을 놓아 실질 병렬).
- **길찾기는 서버가 계산하지 않는다** — 최단 경로는 클라이언트 온디바이스 Dijkstra. 서버는
  그래프·층 GeoJSON·타일만 제공한다. 그래서 "길찾기 부하" = 캐시 잘 되는 정적 데이터 전송.

## 요청 성격 3분류

| 사용자 행동 | 서버가 하는 일 | 무게 |
| --- | --- | --- |
| 길찾기 | 건물 그래프 + 층 GeoJSON + 타일 전송(계산 X) | 가벼움, 캐시 히트 |
| 검색(일반) `/query/destination` | SQL 조회 + 형태소 정규화 | 가벼움 |
| 검색(AI) `/query/ai` | 문장 임베딩 추론 + FAISS | **무거움, CPU 바운드** |

## 1000명 동시 사용 시 병목 (심각도 순)

1. **파일 기반 진단 로깅** — (해결됨) `NAV_SQL_ECHO`/`NAV_HTTP_CAPTURE`가 모든 SQL·요청을
   `app/sql/`·`app/args/`에 파일로 append 하던 구조. 부하에서 디스크 I/O로 서버가 먼저 죽는다.
   → **stdout 로깅으로 대체하고 파일 캡처는 제거했다**(아래 "로깅 변경" 참조).
2. **동기 핸들러 40스레드 천장 + GIL** — 느린 요청이 스레드를 오래 물면 가벼운 요청까지 큐에 갇힌다.
3. **`/query/ai` 임베딩 CPU 직렬화** — 질의마다 encode. 작은 인스턴스에선 초당 처리량이 한 자릿수~
   수십 건. 캐시 불가(질의가 매번 다름). → 수평 확장(인스턴스 다중화)이 사실상 필수.
4. **콜드 비용** — FAISS 인덱스 첫 빌드(매장 전체 임베딩)·MVT 타일 첫 인코딩. startup 워밍업이
   이미 있어 워밍만 확실히 돌면 대부분 캐시 히트. 단 오토스케일 새 인스턴스마다 반복.
5. **SQLite 락** — 런타임은 읽기 위주라 대체로 버티지만, WAL/`busy_timeout` 미적용이면 락 충돌 시
   즉시 `database is locked`. → 03의 PRAGMA로 완화.

참고: **타일 캐시 무제한(06)** 은 건물이 하나면 유한(사용자 수 무관)해서 단일 건물 데모에선 덜 급하다.
건물이 여러 개로 늘 때 급해진다.

## 시나리오별 결론

- 대부분 길찾기 + 일반 검색 → 로깅만 정리하고 워밍업 돌면 단일 인스턴스로도 상당히 버틴다.
- AI 검색을 적극 사용 → 단일 인스턴스로는 부족. Cloud Run min-instances + CPU boost로 다중화 필요.
- "1000 동시"가 아니라 시간에 걸친 1000명이면, 초당 수십 요청 수준이라 인스턴스 2~3개로 감당 가능.

## PostgreSQL / Redis 도입 여부

현재 규모(소수 인원~중간 트래픽, 단일 건물, 읽기 위주)에서는 **둘 다 오버스펙**이다.

- **DB는 SQLite 유지.** 03의 조치는 "DB를 바꿔라"가 아니라 "무결성을 DB가 강제하게 하라"이고,
  `CheckConstraint`·`PRAGMA(WAL/busy_timeout)`는 전부 SQLite에서 된다. PostgreSQL 전환 트리거는
  다중 writer 동시성·수평 확장·대용량 쓰기·PostGIS가 필요해질 때다.
- **캐시는 인프로세스 bounded LRU(06) 유지.** Redis는 여러 프로세스/인스턴스가 캐시를 공유해야 할
   때 값을 한다 — worker를 여러 개로 늘리거나 인스턴스를 다중화하면 그때 검토한다.

## 로깅 변경 (적용됨)

파일 기반 진단 캡처를 제거하고 stdout 로깅으로 통일했다.

- 제거: `NAV_SQL_ECHO`(→ `app/sql/queries.sql`), `NAV_HTTP_CAPTURE`(→ `app/args/*.json`),
  `request_capture.py`, `database.py`의 SQL echo 리스너, 관련 lifespan·설정·볼륨 마운트.
- 추가: `app/core/logging.py` — `configure_logging()`(uvicorn access/error + `app.*`를 stdout으로 통일),
  `install_exception_logging()`(4xx/422는 이유와 함께 `WARNING`, 5xx는 `ERROR`). 500 트레이스백은
  uvicorn이 담당. 레벨은 `NAV_LOG_LEVEL`(기본 `INFO`, `DEBUG`로 상세).
- 각 모듈의 `print()`는 `logging.getLogger(__name__)`으로 교체.

이유: 상태 코드는 uvicorn access 로그가 이미 남기고, 에러 상세는 예외 핸들러가 남긴다. Cloud Run 등이
stdout을 자동 수집하므로 파일이 필요 없고, 부하에서 디스크 I/O 병목(위 1위)도 사라진다.
