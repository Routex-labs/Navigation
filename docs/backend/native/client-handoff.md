# [인수인계] AI 자연어 질의(`/query/ai`) 클라이언트 연동

클라이언트 개발자에게 전달하는 요청서. 백엔드의 FAISS 하이브리드 자연어 질의
([FAISS.md](FAISS.md))는 구현·서빙까지 끝났으나 **클라이언트가 아직 소비하지 않는다.**
이 문서는 그 연동 작업을 정리한다.

## 배경

- 백엔드는 `POST /query/ai`로 **경량 1차 + FAISS 의미 검색 2차 하이브리드**를 제공한다.
  사전에 없는 표현("밥 먹을 곳", "애들 신발")도 의미가 가장 가까운 **매장 1건**과 그
  **입구 노드**를 돌려준다. 설계·임계값은 [FAISS.md](FAISS.md), 경량 1차는 [query.md](query.md).
- 현재 클라이언트가 호출하는 질의 엔드포인트는 `POST /query/destination`(경량 검색) **하나뿐**이다.
  `/query/ai`는 호출하지 않는다. `widgets/rag_chat_panel.dart`는 "건물 정보 Q&A" UI로 있으나
  **하드코딩된 샘플 대화만** 보여주는 껍데기다(백엔드 미연결).
- 주의: `/query/ai`는 **검색(retrieval)** 이다. 대화형 생성 응답이 아니라 **매장 1건을 반환**한다.
  즉 "질문에 문장으로 답하는" RAG가 아니라 **똑똑한 목적지 검색**으로 붙여야 한다.

## API 계약

`POST /query/ai` — 요청/응답 계약은 `/query/destination`과 **동일**하다(하이브리드 경로만 다름).

요청 Body:

```json
{ "text": "밥 먹을 곳", "building_id": "thehyundai-seoul", "current_floor_id": "B2" }
```

- `current_floor_id` (선택): 층 라벨("B2")·내부 id 모두 허용. 주면 그 층으로 스코프.
- `text`: 1~200자, 공백만이면 422.

응답(200, `DestinationResponse`):

```json
{
  "status": "ok",
  "query": "밥 먹을 곳",
  "match": {
    "store_id": "...",
    "name": "스시코우지",
    "category": "음식점", "subcategory": "일식",
    "floor_id": "FL-...", "floor_name": "B1",
    "entrance_node_id": "FL-...:ND-...",
    "centroid_local_m": { "x": 12.3, "y": 45.6 },
    "centroid_wgs84": { "lat": 37.52, "lng": 126.92 }
  }
}
```

`status` 의미:

| status | 뜻 | 클라이언트 처리 |
|---|---|---|
| `ok` | 매장 찾음 + 입구 노드 있음 | 경로 안내 가능(`entrance_node_id`로 Dijkstra) |
| `ok_no_route` | 매장 찾음, 입구 노드 없음 | 위치는 표시하되 "경로 안내 불가" 안내 |
| `no_match` | 임계값 미달·못 찾음 | `match`는 `null` → "결과 없음" 안내 |

에러: 건물 없음 404, 빈/공백 `text` 또는 200자 초과 422.

## 핵심 주의점

- **응답은 단일 `match` 객체다(리스트 아님).** 현재 `repositories/place/http_destination_repository.dart`는
  `/query/destination` 응답을 **`body['result']` 리스트**로 파싱하는데(주석엔 "백엔드는 아직 스텁"),
  실제 백엔드는 `{status, query, match}`를 반환한다 — **낡은 파서라 항상 빈 결과가 된다.**
  `/query/ai` 연동과 함께 이 파싱을 현재 계약(`match` 단일 객체)에 맞춰 고쳐야 한다.
- **첫 `/query/ai`는 임베딩 모델 로드로 지연될 수 있다(CPU ~6초).** 백엔드가 기동 시 백그라운드로
  워밍하지만(Cloud Run에선 startup CPU boost/min-instances 없으면 즉시 끝나지 않을 수 있음),
  클라이언트는 **로딩 상태**를 반드시 노출한다.
- **경량 1차로 확정되는 질의(정확 이름·동의어)는 torch 로드 없이 즉시** 온다. 2차(의미 검색)로
  넘어가는 자연어만 모델을 탄다.
- `/query/destination`(경량)과 `/query/ai`(하이브리드)는 **응답 계약이 같다.** 파싱 코드를 공유할 수 있다.

## 작업 항목(파일별)

- `repositories/place/destination_repository.dart` + `http_destination_repository.dart`:
  - `/query/destination` 파서를 현재 계약(`{status, query, match}`)으로 교정.
  - `/query/ai`를 호출하는 메서드(또는 별도 repository) 추가 — 반환은 **단일 match**(store + `entrance_node_id` + 좌표).
- AI 질의 진입점(상단 검색의 "AI 쿼리" 버튼 또는 전용 입력)에서 `/query/ai`를 호출하고, 결과 매장을
  기존 **목적지/경로 안내 플로우**로 넘긴다.
- `widgets/rag_chat_panel.dart`: 하드코딩 샘플을 실제 `/query/ai` 결과로 대체하거나, Q&A 껍데기를
  검색형 진입점으로 대체(생성형 답변이 아니라 매장 안내임을 UI에 반영).
- 로딩·`no_match`·`ok_no_route` 상태별 UI 처리.

## 완성 기준

**연동 완료.** 아래 항목은 모두 충족했다(구현 위치는 "연동 결과" 참고).

- [x] `POST /query/ai`를 `{text, building_id, current_floor_id?}`로 호출한다.
- [x] 응답을 **단일 `match` 객체**로 파싱한다(`store_id`·`name`·`floor_name`·`entrance_node_id`·좌표).
- [x] 사전에 없는 자연어("밥 먹을 곳", "애들 신발")로도 관련 매장이 안내된다.
- [x] `status`별 처리: `ok`=경로 안내, `ok_no_route`=위치만+안내, `no_match`=결과 없음.
- [x] 첫 질의의 모델 로드 지연 동안 **로딩 상태**가 표시되고 UI가 멈추지 않는다.
- [x] 빈/공백 질의(422)·건물 없음(404)에서 앱이 크래시하지 않고 사용자에게 안내한다.
- [x] ~~기존 `/query/destination` 경량 검색의 낡은 `result` 리스트 파서 교정~~ —
      **이 항목은 문서가 낡았다.** 확인해 보니 `http_destination_repository.dart`는
      이미 현재 계약(`{status, query, match}`)으로 파싱하고 있었다.
- [x] `rag_chat_panel`이 하드코딩 샘플이 아니라 실제 백엔드 결과로 동작한다.

## 연동 결과

- **진입점은 별도 "AI 쿼리" 버튼이 아니라 상단 검색의 2차 폴백으로 붙였다.**
  `map_shell_screen._onSearch`가 경량(`/query/destination`)을 먼저 태우고, 빈손일
  때만 `/query/ai`를 부른다. 사용자가 "결과 없음"을 볼 상황에서만 타므로 잘 되던
  검색은 그대로 빠르고, 못 찾던 자연어만 건진다. 사용자가 "이건 AI로 찾아야 하는
  질의"라고 미리 판단할 필요가 없다.
- `rag_chat_panel.dart`는 하드코딩 Q&A 껍데기에서 **실제 `/query/ai` 검색 패널**로
  교체했다. 생성형 답변이 아니라 매장 1건 안내임을 UI 문구로 반영했다.
- `DestinationRepository.searchDestinationsAi`를 추가하고, 두 엔드포인트의 응답
  계약이 같으므로 파싱은 경로만 바꿔 공유한다.

## 실측(로컬 CPU, 2026-07-27)

| 질의 | `/query/destination` | `/query/ai` |
|---|---|---|
| `MLB` | ok · MLB(B2) | ok · MLB(B2), 0.3초 |
| `밥 먹을 곳` | **no_match** | ok · 요즘김밥(B1) |
| `애들 신발` | **no_match** | ok · 탠디(3F) |
| `asdfqwerzxcv` | no_match | no_match |

- 경량이 못 찾는 자연어를 AI가 실제로 건진다는 것이 폴백 설계의 근거다.
- **첫 질의(모델 콜드 스타트)는 20.8초 걸렸다.** 이 문서가 적어 둔 "CPU ~6초"보다
  훨씬 길다. 워밍 후에는 0.3~0.5초. 로딩 표시가 필수인 이유이며, 20초대는 SnackBar
  스피너만으로 버티기엔 길어 배포 전 워밍 전략(min-instances·startup CPU boost)을
  다시 볼 것.

## 검증 방법

- 로컬 백엔드 기동 후 Swagger(`http://127.0.0.1:8001/docs`)에서 `POST /query/ai`로
  `{"text":"밥 먹을 곳","building_id":"thehyundai-seoul"}` 응답 확인.
- 정확 이름(예: "MLB")은 즉시(경량 1차), 자연어("애들 신발")는 2차(모델 로드 후) 응답 확인.
- 무의미 문자열("asdfqwerzxcv")이 `no_match`로 걸러지는지 확인(유사도 임계값 미달 컷).

## 참고

- 설계·임계값·실패 조건: [FAISS.md](FAISS.md), 경량 1차·형태소 정규화: [query.md](query.md), [KIWI.md](KIWI.md)
- 응답 계약: `backend/app/dto/query.py`(`DestinationResponse`·`QueryMatch`)
- 백엔드 동작 예시: `backend/tests/unit/test_query_ai.py`, `backend/tests/integration/test_query_semantic_smoke.py`
