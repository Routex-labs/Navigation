"""매장·건물 상세 API 응답 모델.

건물과 매장에 각각 다른 스키마를 두지 않는다. 둘은 정보의 종류가 아니라 범위만
다르고(건물에는 자식 목록이 더 붙을 뿐), 스키마를 쪼개면 화면도 두 벌이 된다.
그래서 `PlaceDetailResponse` 하나를 건물·매장·시설이 함께 구현한다. 근거는
`docs/backend/place-detail/place-detail-interface.md` 4절.

## 왜 optional 필드가 아니라 섹션 배열인가

매장 1,640건 중 표시할 내용이 있는 건 539건뿐이고(같은 문서의 조사 보고서 1절),
그 539건 안에서도 무엇이 채워지는지가 제각각이다. 표시 가능한 항목을 전부
optional 필드로 열면 클라이언트가 매장마다 "이건 있나?"를 스무 번 분기하게 되고,
그 분기 조합이 그대로 레이아웃 흔들림이 된다. 섹션 배열이면 클라이언트는
`for section in sections: render(section)` 하나이고, "무엇을 보여줄지"의 판단이
서버 한 곳에 모인다.

대가는 서버가 표시 순서를 쥔다는 것이다. 이를 완화하는 규칙 세 가지를 계약에
못박는다.

1. 값이 없으면 **섹션을 아예 내려보내지 않는다.** 빈 문자열·null 섹션을 만들지
   않는다 — 클라이언트가 "빈 섹션" 분기를 갖게 되면 위의 이점이 사라진다.
2. 클라이언트는 **모르는 `type`을 조용히 건너뛴다.** 서버가 섹션을 추가해도
   구버전 앱이 깨지지 않는다.
3. 순서만 서버가 정하고 **스타일(폰트·색·간격·아이콘)은 클라이언트가 갖는다.**
"""

from typing import Literal

from pydantic import BaseModel

from app.dto.floor_map import PointResponse


# 상세 대상의 종류. 클라이언트가 아이콘과 기본 액션을 고르는 키이자,
# 상세 시트를 열지 말지 판단하는 근거다 — 주차구역·에스컬레이터·엘리베이터
# 1,007건은 "설명"이라는 개념이 없어 excluded로 내려간다.
PlaceKind = Literal["building", "store", "facility", "excluded"]


# 상세의 위치. 길찾기 가능 여부까지 여기서 판별된다.
class PlaceLocationResponse(BaseModel):
    building_id: str
    floor_label: str | None = None  # 사람이 보는 층 라벨(예: B2). 건물이면 None
    position_local_m: PointResponse | None = None  # 지도 미리보기 앵커
    # 온디바이스 다익스트라의 도착 노드. null이면 길찾기 액션을 내리지 않는다.
    # 원본 데이터에는 이 값이 전부 비어 있고 시드가 최근접 노드로 스냅해 채우므로,
    # 길찾기 가능 여부는 시드 결과를 봐야만 알 수 있다.
    entrance_node_id: str | None = None


# 시트에 띄울 액션 버튼 하나. 서버가 "가능한 것"만 내려보낸다.
class PlaceActionResponse(BaseModel):
    type: Literal["directions", "favorite", "share"]
    label: str


# 표시된 값의 출처. 화면 하단에 "정보 출처·최종 확인일"로 노출한다.
# 출처 없는 값(영업시간·전화·평점)을 넣지 않겠다는 결정을 스키마로 강제하는
# 장치이기도 하다 — 오버레이가 붙으면 source가 manual로 바뀌므로, 사람이 쓴
# 내용인지 파생인지를 응답만 보고 구분할 수 있다.
class ProvenanceResponse(BaseModel):
    source: Literal["studio", "manual", "derived"]
    updated_at: str | None = None  # ISO 날짜. 오버레이가 적어 준 최종 확인일


# --- 섹션 -------------------------------------------------------------
# 각 섹션은 자기 렌더링에 필요한 데이터를 전부 들고 있다. 클라이언트가 다른
# 섹션이나 코어 필드를 참조해야 그릴 수 있는 섹션은 만들지 않는다.


class SummarySection(BaseModel):
    type: Literal["summary"] = "summary"
    text: str  # 한 줄 소개


class KeyValueItem(BaseModel):
    label: str
    value: str


class KeyValueSection(BaseModel):
    type: Literal["keyValue"] = "keyValue"
    items: list[KeyValueItem]


class TagsSection(BaseModel):
    type: Literal["tags"] = "tags"
    tags: list[str]


class NoticeSection(BaseModel):
    type: Literal["notice"] = "notice"
    text: str
    # 기간이 명시된 고지만 허용한다. 영업시간을 넣지 않는 이유와 같은 규칙 —
    # 기한이 없는 문구는 시간이 지나면 조용히 거짓이 되고, 기한이 있으면
    # 검증 스크립트가 만료를 잡아낼 수 있다.
    until: str | None = None  # ISO 날짜


class MapSection(BaseModel):
    type: Literal["map"] = "map"
    # 폴리곤이 없는 매장이 14건 있어 이 필드는 비어 있을 수 있다.
    polygon_local_m: list[PointResponse] = []


class ChildListItem(BaseModel):
    place_id: str
    name: str
    category: str | None = None
    floor_label: str | None = None


class ChildListSection(BaseModel):
    type: Literal["childList"] = "childList"
    total: int
    category_counts: dict[str, int]
    items: list[ChildListItem]


DetailSection = (
    SummarySection
    | KeyValueSection
    | TagsSection
    | NoticeSection
    | MapSection
    | ChildListSection
)


# 상세 응답 본체. sections가 비어 있어도 이 응답만으로 화면이 성립해야 한다 —
# 그것이 "정보 없음 카드"를 만들지 않기 위한 조건이다.
class PlaceDetailResponse(BaseModel):
    kind: PlaceKind
    id: str
    name: str
    subtitle: str  # 예: "B2 · 카페·베이커리"
    category: str | None = None
    subcategory: str | None = None

    location: PlaceLocationResponse
    actions: list[PlaceActionResponse]
    sections: list[DetailSection] = []
    provenance: ProvenanceResponse
