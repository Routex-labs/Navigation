# 06. 기술 스택과 데이터 포맷

플랫폼: **Flutter(크로스플랫폼 클라이언트) + FastAPI(백엔드) + Python AI 레이어(RAG)** 풀스택.
핵심 측위 알고리즘(PDR·필터·지도매칭)은 **Dart로 직접 구현**하고, 자연어/RAG는 백엔드에서 처리한다.

> **스택 한 줄 요약**
> Flutter(Dart) 앱이 센서를 읽어 온디바이스 PDR을 돌리고, FastAPI가 평면도 GeoJSON과
> RAG 질의를 서빙한다. 추가 인프라(비콘·VPS)는 없다.

---

## 0. 전체 레이어 구조

```
┌─────────────────────────────────────────────────────────┐
│  CLIENT  (Flutter / Dart)                                │
│  - 센서 수집, 온디바이스 PDR/Particle Filter, 지도 렌더링 │
│  - 자연어 입력 UI → 백엔드 RAG 호출                       │
├─────────────────────────────────────────────────────────┤
│  API  (FastAPI / Python 3.12)                            │
│  - 평면도/건물 GeoJSON 서빙                              │
│  - RAG 엔드포인트 (목적지 파싱·정보 Q&A)                  │
├─────────────────────────────────────────────────────────┤
│  AI / RAG  (Python, FastAPI 내장)                        │
│  - 임베딩 + 벡터 검색(FAISS) + LLM 생성                   │
├─────────────────────────────────────────────────────────┤
│  DATA  (정적 GeoJSON 파일 → 확장 시 DB)                  │
└─────────────────────────────────────────────────────────┘
```

레이어별 상세 버전은 [VERSION.md](../../VERSION.md)에서 단일 출처로 관리한다.
아래 표의 버전은 **착수 시점 목표치**이며, 구현 시 `pubspec.yaml`·`requirements.txt`에 핀(pin)으로 고정한다.

---

## 1. 프론트엔드 (Flutter / Dart)

### 런타임

| 항목 | 목표 버전 | 메모 |
|---|---|---|
| Flutter SDK | 3.24+ | stable 채널 고정 |
| Dart | 3.5+ | Flutter SDK 동봉 버전 |
| 최소 OS | iOS 13+ / Android 8.0(API 26)+ | 센서 풀세트 보장 하한 |

### 핵심 패키지

| 역할 | 패키지 | 목표 버전 | 메모 |
|---|---|---|---|
| 센서 수집 | `sensors_plus` | ^6.0 | 가속도·자이로·지자기 스트림 |
| 기압계 | `sensors_plus` (`barometerEvents`) | ^6.0 | 미탑재 기기 폴백 필요 → [05](05-device-sensor-compatibility.md) |
| GPS | `geolocator` | ^13.0 | 야외 위치 + accuracy 스트림, 실내 전환 트리거 |
| 나침반 보조 | `flutter_compass` | ^0.8 | 플랫폼 fused heading 비교용(선택) |
| 지도 렌더링 | `flutter_map` | ^7.0 | OSM 어댑터, API 키 불필요. 평면도는 커스텀 레이어 |
| 좌표/기하 | `latlong2`, `vector_math` | ^0.9 / ^2.1 | 좌표 변환·행렬 연산 |
| HTTP 통신 | `dio` | ^5.0 | 백엔드/RAG 호출, 인터셉터·타임아웃 |
| 상태 관리 | `flutter_riverpod` | ^2.5 | 센서 스트림 다수 → 상태 관리 핵심 |
| 로컬 캐시 | `shared_preferences` | ^2.3 | 사용자 키·최근 건물 등 경량 저장 |
| 음성 입력(선택) | `speech_to_text` | ^7.0 | RAG 자연어 입력 음성화 → [09](09-rag-integration.md) |
| JSON 직렬화 | `json_serializable` + `freezed` | ^6.8 / ^2.5 | 모델 코드 생성, 불변 객체 |

> **중요**: `geolocator`·`sensors_plus` 같은 표준 패키지는 **PDR/dead reckoning 기능을 제공하지 않는다.**
> 걸음 감지·방향 융합·지도 매칭은 전부 직접 구현해야 한다. 이게 곧 프로젝트의 기술적 본체다.

### 클라이언트 디렉토리 구조

```
client/lib/
├─ main.dart
├─ core/
│   ├─ sensors/          # sensors_plus 래퍼, capability 점검 (05 문서)
│   ├─ math/             # 벡터·좌표 변환 유틸
│   └─ config/           # 상수, 환경값
├─ pdr/                  # 측위 알고리즘 본체 (아래 2장)
│   ├─ step_detector.dart
│   ├─ stride_estimator.dart
│   ├─ heading_filter.dart
│   ├─ pdr_engine.dart
│   └─ particle_filter.dart
├─ navigation/
│   ├─ io_transition.dart   # 실내/외 전환
│   └─ route_planner.dart   # A*/Dijkstra
├─ data/
│   ├─ models/          # freezed 모델 (Building, Floor, POI...)
│   └─ repositories/    # FastAPI 호출 (dio)
├─ features/
│   ├─ map/             # flutter_map 렌더링 + 마커/경로 레이어
│   └─ assistant/       # RAG 자연어 입력 UI
└─ state/               # Riverpod providers
```

### 백그라운드 위치 주의

- 장시간 센서·GPS 구독은 배터리 소모가 크다. 백그라운드 위치 플러그인은 배터리 영향이 크므로
  **데모는 포그라운드 동작 위주**로 설계하고, 배터리 이슈는 발표에서 "향후 최적화"로 언급.

---

## 2. 핵심 측위 알고리즘 (온디바이스 Dart)

전부 클라이언트에서 실행한다. **네트워크 없이 동작**하는 게 "인프라 0" 차별점의 핵심이다.

| 모듈 | 내용 | 참고 문서 |
|---|---|---|
| `step_detector` | 가속도 magnitude → LPF → peak detection | [01](01-pdr.md) |
| `stride_estimator` | Weinberg 보폭 모델 + 키 입력 | [01](01-pdr.md) |
| `heading_filter` | Complementary/Madgwick (자이로+지자기 융합) | [02](02-sensor-fusion-heading.md) |
| `pdr_engine` | 위 셋 통합 → 위치 델타 (dx, dy) | [01](01-pdr.md) |
| `particle_filter` | 평면도(벽) 제약 매칭으로 누적오차 보정 | [03](03-map-matching.md) |
| `io_transition` | GPS→실내 전환 감지·초기 위치 확정 | [04](04-indoor-outdoor-transition.md) |
| `route_planner` | 평면도 그래프 위 최단 경로(A*/Dijkstra) | [03](03-map-matching.md) |

**처리 주기 설계 메모**
- 센서 입력: 가속도/자이로 50~100Hz, 지자기 ~20Hz.
- PDR 갱신: 걸음 이벤트 기반(이벤트 드리븐) + heading은 고주파 적분.
- Particle Filter: 걸음마다 1회 update(수백~수천 파티클). UI는 별도 60fps로 분리.
- 무거운 연산은 Dart `Isolate`로 분리해 UI 스레드 블로킹을 막는다.

---

## 3. 백엔드 (FastAPI / Python)

### 런타임

| 항목 | 목표 버전 | 메모 |
|---|---|---|
| Python | 3.12 | |
| FastAPI | ^0.115 | REST 방식 엔드포인트 |
| ASGI 서버 | `uvicorn[standard]` ^0.32 | 개발/시연 |
| 데이터 검증 | `pydantic` ^2.9 | 요청/응답 스키마 |
| 지오메트리 | `shapely` ^2.0 | GeoJSON 검증·공간 연산(선택) |
| 테스트 | `pytest` ^8.3 + `httpx` | 엔드포인트 테스트 |

### 책임 범위

백엔드는 **무거운 측위 연산을 하지 않는다.** 측위는 전부 온디바이스다.
백엔드의 역할은 (1) 정적 평면도/건물 데이터 서빙, (2) RAG 질의 처리 두 가지로 한정한다.

### 엔드포인트

```
# --- 평면도 / 건물 ---
GET  /buildings                        # 건물 목록
GET  /buildings/{id}                   # 건물 메타 + 입구 좌표
GET  /buildings/{id}/floors/{floor}    # 해당 층 평면도 GeoJSON
GET  /buildings/{id}/status            # 현재 구간 상황(공사·폐쇄 등) → 09 문서

# --- RAG (09 문서) ---
POST /query/destination                # 자연어 → 목적지 POI 반환
POST /query/info                       # 건물 정보 Q&A
```

### 백엔드 디렉토리 구조

```
api/
├─ app/
│   ├─ main.py            # FastAPI 인스턴스, 라우터 등록
│   ├─ routers/
│   │   ├─ buildings.py
│   │   └─ query.py       # RAG 엔드포인트
│   ├─ services/
│   │   ├─ floor_store.py # GeoJSON 로딩/캐싱
│   │   └─ rag/           # 아래 4장
│   ├─ schemas/           # pydantic 모델
│   └─ data/              # 정적 GeoJSON (1차 데이터 소스)
├─ tests/
└─ requirements.txt
```

> FastAPI는 "도구(프레임워크)", REST는 "API 설계 방식"이라 레이어가 다르다.
> 이 규모에선 **FastAPI + REST** 조합 그대로면 충분(GraphQL 불필요).

---

## 4. AI / RAG 레이어 (Python, FastAPI 내장)

자연어 목적지 파싱과 건물 정보 Q&A를 담당한다. 상세 설계는 [09](09-rag-integration.md).

**데모용 권장 스택(옵션 A: 경량·로컬)** — API 키 의존 없이 오프라인 동작 → 시연 안정성.

| 레이어 | 패키지 | 목표 버전 | 메모 |
|---|---|---|---|
| 임베딩 | `sentence-transformers` | ^3.0 | 다국어 모델(예: `paraphrase-multilingual-MiniLM`) |
| 벡터 DB | `faiss-cpu` | ^1.8 | FastAPI 프로세스 내장, 별도 서버 불필요 |
| LLM | `anthropic` (Claude Haiku) 또는 로컬 | ^0.39 | 비용·지연 낮은 소형 모델 |
| 오케스트레이션 | 직접 구현 또는 `langchain` | ^0.3 | 규모 작으면 직접 구현이 가볍다 |

> 서버 배포·비용을 감수할 수 있으면 옵션 B(Qdrant + OpenAI/Claude API)로 확장. → [09](09-rag-integration.md) 참고.

---

## 5. 평면도 데이터 포맷

평면도는 **벽(통과 불가) + 보행가능 영역 + 문 + 관심지점(POI) + 경로 그래프**를 담아야 한다.
표준 GeoJSON Feature로 표현하고, `properties.type`으로 의미를 구분한다.

```
building/
├─ meta: { id, name, entrances: [ {lat, lng, floor, heading_hint} ] }
└─ floors/
   ├─ floor_1.geojson
   │   features:
   │     - type: "wall"      geometry: LineString   # Particle Filter 벽 제약
   │     - type: "corridor"  geometry: Polygon       # 보행가능 영역
   │     - type: "door"      geometry: Point         # 문 통과 관측
   │     - type: "poi"       geometry: Point  name:  # 목적지 후보 (RAG 인덱싱 대상)
   │     - type: "node"/"edge"                        # 경로 그래프(최단경로용)
   └─ floor_2.geojson
```

좌표계 메모: 실내는 보통 **건물 로컬 좌표(미터)** 로 다루는 게 PDR 적분과 잘 맞는다.
GPS(위경도)와의 정합은 입구 좌표를 기준점(anchor)으로 변환한다.

POI의 `name`·태그는 그대로 RAG 임베딩 입력이 되므로, **동의어·다국어 별칭**을 properties에
넣어두면 자연어 검색 정확도가 올라간다. (예: `aliases: ["화장실","restroom","WC"]`)

---

## 6. 개발 · 빌드 · 배포 도구

| 영역 | 도구 | 메모 |
|---|---|---|
| 버전 관리 | Git + GitHub Flow | [navigation-overview](../navigation-overview.md) 운영 방식 |
| CI | GitHub Actions | `flutter test`, `pytest`, lint 게이트 ([prompt/](../../prompt) 자동화) |
| Dart 린트 | `flutter_lints` | `analysis_options.yaml` |
| Python 린트/포맷 | `ruff` + `black` | |
| 컨테이너 | Docker | API/RAG 이미지화 → [VERSION.md](../../VERSION.md) 태그 규칙 |
| 백엔드 배포 | Railway / Fly.io | 시연용 경량 배포 |
| 앱 배포 | TestFlight / APK 직접 배포 | 데모는 빌드 APK·시뮬레이터로 충분 |

---

## 7. 전체 데이터 흐름

```
[휴대폰 센서] ── sensors_plus ──┐
[GPS] ── geolocator ───────────┤
                                ▼
                  io_transition (실내 진입 감지·초기화)
                                ▼
              pdr_engine (걸음·보폭·heading)        ← 전부 온디바이스 Dart
                                ▼
        particle_filter (평면도 제약 매칭)  ◄── 평면도 GeoJSON (FastAPI)
                                ▼
                  현재 위치 추정 (x, y, floor)
                                ▼
          flutter_map 평면도 위 실시간 마커 + 경로

[사용자 자연어] ── dio ──► FastAPI /query ──► RAG(임베딩+FAISS+LLM)
                                ▼
                  목적지 POI / 안내 문장 ──► route_planner
```

---

## 8. 구현 우선순위 (경진대회)

1. **PDR 동작** — 없으면 프로젝트 자체가 성립 안 함.
2. **평면도 렌더링** — 시각적으로 심사위원 눈에 바로 보임.
3. **Particle Filter** — 차별점, 완성도 급상승.
4. **자동 전환** — 시연 임팩트.
5. **RAG 자연어 목적지** — 두 번째 차별점(자연어 UX). → [09](09-rag-integration.md)
6. **백엔드** — 데모용이면 정적 GeoJSON 서빙으로 최소화하고 알고리즘에 집중.

> 1~4가 코어(측위), 5가 차별화(UX), 6은 얇게. 측위가 흔들리면 RAG는 후순위로 미룬다.

## 참고 자료

- [sensors_plus | Flutter package](https://pub.dev/packages/sensors_plus)
- [geolocator | Flutter package](https://pub.dev/packages/geolocator)
- [flutter_map | Flutter package](https://pub.dev/packages/flutter_map)
- [Riverpod | State management](https://riverpod.dev/)
- [FastAPI](https://fastapi.tiangolo.com/)
- [FAISS - Facebook AI Similarity Search](https://github.com/facebookresearch/faiss)
- [sentence-transformers](https://www.sbert.net/)
- [Top Flutter Map and Geolocation Utility packages | Flutter Gems](https://fluttergems.dev/geolocation-utilities/)
