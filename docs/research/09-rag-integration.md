# 09. RAG 통합 설계

실내 내비게이션에 **RAG(Retrieval-Augmented Generation)** 를 결합해 자연어 인터페이스와
건물 정보 Q&A를 제공하는 방안을 정리한다.

## 왜 RAG인가

기존 시스템은 목적지를 **정형 입력**(지도 터치, 드롭다운 선택)으로만 받는다.
RAG를 붙이면:

- 사용자가 자연어로 목적지를 말할 수 있음 ("화장실 어디야?")
- 건물 운영 정보(시간, 접근성 등)를 LLM이 실시간으로 답변
- 인프라 추가 없이 UX 차별점 확보 → 경진대회 심사위원 임팩트

---

## 적용 지점 4가지

### 1. 자연어 목적지 파싱 (핵심)

사용자 발화 → RAG로 POI DB 검색 → 목적지 좌표 반환 → 기존 경로 플래너에 전달.

```
사용자: "3층 카페 가고 싶어"
         ↓
  Query Embedding
         ↓
  POI 벡터 DB 검색  ← 건물 내 모든 POI (이름, 층, 위치, 태그)
         ↓
  Top-k 후보 → LLM 재랭킹
         ↓
  { name: "스타벅스", floor: 3, x: 42.1, y: 18.7 }
         ↓
  route_planner 에 전달 (기존 A*/Dijkstra 그대로 사용)
```

**구현 포인트:**
- POI GeoJSON의 `properties`(이름, 태그, 층)를 텍스트로 변환해 임베딩
- 동의어 처리: "화장실"="restroom"="WC", "편의점"="CU"="GS25" 등
- 애매한 경우 LLM이 후보 2~3개를 사용자에게 재확인

---

### 2. 건물 정보 Q&A

건물 운영 정보를 문서 형태로 인덱싱, 사용자 질문에 즉시 답변.

```
RAG 문서 예시:
  - 건물_운영시간.md  → "본관은 평일 09:00~22:00 운영"
  - 편의시설.md       → "수유실: B1 101호, 수동 휠체어 접근 가능"
  - 공사안내.md       → "2025-07-01 ~ 07-15, A동 3층 복도 공사 중"

사용자: "수유실 어디야?" → 문서 검색 → "B1 101호에 있으며 휠체어도 가능합니다"
```

**운영 정보 업데이트가 쉬운 게 장점** — 코드 수정 없이 문서만 교체.

---

### 3. 실시간 상황 반영 경로 우회

공사, 혼잡, 폐쇄 같은 **일시적 제약**을 텍스트 DB로 관리하고 경로에 반영.

```
상황 DB (실시간 업데이트):
  { zone: "A동 3층 복도", status: "공사중", until: "2025-07-15" }
  { zone: "B동 1층 출입구", status: "폐쇄", reason: "행사" }

경로 요청 시:
  1. 출발→목적지 경로상의 구간을 RAG로 조회
  2. 제약 구간 감지 → Particle Filter / 경로 그래프에서 해당 edge 가중치 상승
  3. 우회 경로 자동 생성 + "현재 A동 3층 복도가 공사 중이라 우회합니다" 안내
```

---

### 4. 다국어 자동 안내

POI·운영 정보를 한국어로 저장, 외국인 사용자에게는 LLM이 실시간 번역 답변.

```
저장: "스타벅스 / 3층 / 음료"
      ↓ RAG 검색 후 LLM
영어: "Starbucks is on the 3rd floor. Head straight and take a right."
일어: "スターバックスは3階にあります。"
```

별도 다국어 DB 불필요 — LLM이 번역을 담당.

---

## 시스템 아키텍처

```
[사용자 발화 / 텍스트 입력]
        ↓
  [Embedding 모델]  ← 경량 모델 권장 (text-embedding-3-small 등)
        ↓
  [벡터 DB 검색]  ← FAISS (로컬) 또는 Qdrant (서버)
  ┌─────────────────────────────┐
  │  POI DB       건물 문서 DB  │
  │  (GeoJSON→텍스트 변환)      │
  └─────────────────────────────┘
        ↓ Top-k 청크
  [LLM 생성]  ← Claude Haiku / GPT-4o-mini (비용 절감)
        ↓
  [목적지 좌표 / 안내 문장]
        ↓
  [기존 route_planner / flutter_map]
```

---

## 기술 스택 옵션

| 레이어 | 옵션 A (경량·로컬) | 옵션 B (서버·확장) |
|--------|-------------------|--------------------|
| 임베딩 | `sentence-transformers` (Python) | OpenAI `text-embedding-3-small` |
| 벡터 DB | FAISS (FastAPI 내장) | Qdrant Cloud (무료 티어) |
| LLM | Claude Haiku 4.5 | GPT-4o-mini |
| 인터페이스 | Flutter 텍스트 입력 | Flutter + STT (speech_to_text 패키지) |

> **경진대회 데모용 추천: 옵션 A**
> 서버 비용 없이 FastAPI 안에 FAISS + sentence-transformers로 전부 넣을 수 있음.
> API 키 의존성 없이 오프라인 동작 가능 → 시연 안정성 확보.

---

## FastAPI 엔드포인트 추가

기존 [`06-tech-stack.md`](06-tech-stack.md) 엔드포인트에 다음 추가:

```
POST /query/destination          # 자연어 → 목적지 POI 반환
POST /query/info                 # 건물 정보 Q&A
GET  /buildings/{id}/status      # 현재 구간 상황 조회 (공사·폐쇄 등)
```

요청/응답 예시:

```json
// POST /query/destination
{ "text": "3층 화장실 어디야", "building_id": "b001", "current_floor": 2 }

// 응답
{
  "poi": { "name": "남자화장실", "floor": 3, "x": 12.4, "y": 33.1 },
  "candidates": [ ... ],   // 애매할 경우 후보 목록
  "message": "3층 남자화장실로 안내합니다."
}
```

---

## 구현 우선순위 (경진대회 맥락)

| 순위 | 기능 | 이유 |
|------|------|------|
| 1 | 자연어 목적지 파싱 | UX 차별점 1순위, 시연 임팩트 가장 큼 |
| 2 | 건물 정보 Q&A | 구현 쉬움, 완성도 인상 |
| 3 | 실시간 상황 반영 | 기술 깊이, 심사위원 호감 |
| 4 | 다국어 | 시간 남으면 |

> RAG 없이 PDR + Particle Filter만으로도 프로젝트는 성립한다.
> RAG는 **"인프라 0 + 자연어 UX"** 라는 두 번째 차별점으로 포지셔닝.

---

## 참고 자료

- [FAISS - Facebook AI Similarity Search](https://github.com/facebookresearch/faiss)
- [sentence-transformers](https://www.sbert.net/)
- [Qdrant - Vector Database](https://qdrant.tech/)
- [LangChain RAG 가이드](https://python.langchain.com/docs/tutorials/rag/)
- [Claude Haiku 4.5 — Anthropic](https://www.anthropic.com/claude/haiku)
