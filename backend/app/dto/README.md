# `app/dto` — API 요청/응답 계약 (Pydantic)

HTTP로 **오가는 데이터의 모양**을 Pydantic 모델로 정의한다. FastAPI가 이 모델로
응답을 직렬화(`response_model`)하고 요청 Body를 검증한다.

> Spring 대응: DTO + Jackson 직렬화 스키마.
> **`models/`(ORM)와 역할이 다르다** — 저장되는 모양이 아니라 클라이언트에 보이는 모양이다. dto는 models를 import하지 않는다.

---

## 구성 파일

| 파일 | 대상 응답 | 핵심 모델 |
|---|---|---|
| `building.py` | 건물 목록/상세 | `BuildingSummaryResponse`, `BuildingDetailResponse` |
| `floor_map.py` | 층 지도 화면 | `FloorMapResponse`, `StoreResponse`, `PoiResponse` |
| `route.py` | 길찾기 그래프 | `FloorGraphResponse`, `GraphNodeResponse`, `GraphEdgeResponse` |
| `health.py` | 헬스 체크 | `HealthResponse` |
| `__init__.py` | 패키지 표식 | — |

---

## 왜 ORM과 분리하는가

같은 "건물"이라도 계층마다 모양이 다르다.

```python
# models/building.py — 저장되는 모양
class Building(Base):
    floors: Mapped[list["Floor"]]      # Floor 객체(관계)

# dto/building.py — 나가는 모양
class BuildingSummaryResponse(BaseModel):
    floors: list[str]                  # 층 "이름" 문자열만
```

ORM을 그대로 반환하면 DB 컬럼을 바꾸는 순간 API가 깨지고 내부 구조가 샌다. dto로 끊으면
DB와 API 계약이 **독립적으로** 바뀐다.

## API 전용 표현들

- **키 이름 변경**: `GraphEdgeResponse`는 `from_node_id`를 `Field(alias="from")`으로 노출한다(내부 컬럼명 ≠ API 키).
- **계산 필드**: `StoreResponse.centroid_wgs84`, `polygon_wgs84`처럼 DB에 없고 변환으로만 만들어지는 값.
- **리터럴 제약**: `coordinate_system: Literal["local_m"]`, `path_found: Literal[True]`로 계약을 타입에 박아 둔다.

---

## 의존성 방향

```
dto/*  ──►  pydantic 만 (models·sqlalchemy import 안 함)

routers/*  ──►  dto (response_model=..., 요청 Body 타입)
```

- **dict를 실제로 조립하는 곳은 `repositories/`·`services/`다.** 그들은 기존 JSON 모양의 순수 dict를 만들고, FastAPI가 라우터의 `response_model`(=dto)로 그 dict를 검증·직렬화한다.
- 즉 dto는 "계약 선언"이고, 값 생성은 다른 계층이 한다.

---

## 자주 하는 작업

| 하고 싶은 것 | 방법 |
|---|---|
| 응답에 필드 추가 | 해당 dto에 필드 추가 + 값을 만드는 `repositories/`·`services/` dict도 수정 |
| API 키 이름만 바꾸기 | `Field(alias="...")` (DB/모델은 그대로) |
| 요청 Body 검증 | 라우터에서 Pydantic 모델을 파라미터로 받기(`query.py`의 `DestinationRequest` 참고) |
