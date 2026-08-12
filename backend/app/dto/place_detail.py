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
    # 출처의 **종류**다. 어디서 왔는지(주소)는 아래 url이 따로 들고 있다 — 둘을 한
    # 필드에 담으면 "manual인지 URL인지"를 소비자가 매번 분기해야 한다.
    source: Literal["studio", "manual", "derived"]
    updated_at: str | None = None  # ISO 날짜. 오버레이가 적어 준 최종 확인일

    # 공식 사이트에서 옮겨 온 문구라면 그 문구가 실제로 있던 페이지 주소. 직접 적은
    # 내용이면 null이다. updated_at(확인일)은 이 주소를 다시 열어 봤다는 뜻이므로
    # 둘은 짝으로 읽는다.
    url: str | None = None


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


class HeroItem(BaseModel):
    # Flutter 자산 경로. 원격 URL을 내려 보내지 않아도 앱에 포함한 사진을 안전하게
    # 참조할 수 있다.
    local_asset: str


class HeroSection(BaseModel):
    type: Literal["hero"] = "hero"
    items: list[HeroItem]


class MenuItem(BaseModel):
    name: str
    image_asset: str

    # 아래는 전부 선택 항목이다. 출처마다 갖고 있는 것이 다르기 때문이다 —
    # 스타벅스 코리아 공식 사이트는 가격을 공개하지 않는 대신 용량·칼로리·카페인을
    # 주고, 푸드에는 영양정보가 없다. 없는 값을 채우려면 지어내는 수밖에 없으므로
    # 필수로 만들지 않는다. 무엇이 비었는지에 따라 카드가 무엇을 보여줄지는
    # 클라이언트가 정한다(계약 4-2 규칙 3).
    # group은 화면 위쪽 갈래(음료·푸드), category는 그 안의 탭이다. 둘 다 순서는
    # items에 처음 등장하는 순서다.
    group: str | None = None
    category: str | None = None
    name_en: str | None = None
    description: str | None = None
    price: str | None = None
    volume: str | None = None
    calories: str | None = None
    caffeine: str | None = None

    # 알레르기 유발 성분. `"대두 / 우유"`처럼 공식 사이트가 쓰는 문장 그대로 싣는다 —
    # 배열로 쪼개려면 구분자를 우리가 정해야 하는데, 원본이 `/`와 `,`를 섞어 쓰고
    # 항목 안에 공백이 들어간 이름(`알류`·`오징어`)도 있어 쪼개는 순간 틀릴 자리가
    # 생긴다. 화면은 이 값을 한 줄로 보여 주기만 하므로 쪼갤 이유가 없다.
    allergens: str | None = None

    # NEW·시즌 한정 같은 표시. 문자열 하나가 아니라 배열인 이유는 두 개가 함께
    # 붙는 항목이 실제로 있기 때문이다.
    #
    # **빈 배열이 아니라 None이 기본값이다.** 라우터가 `exclude_none`으로 직렬화하는데
    # 기본값을 `[]`로 두면 배지가 없는 284종에 `"badges": []`가 그대로 실려 나간다.
    # 값이 없으면 키를 아예 빼는 규칙(계약 4-2 규칙 1)이 이 필드에서만 새는 셈이다.
    # 클라이언트는 없는 키를 빈 목록으로 읽으므로 화면에는 차이가 없다.
    badges: list[str] | None = None


class MenuSection(BaseModel):
    type: Literal["menu"] = "menu"
    items: list[MenuItem]


class BusinessInfoItem(BaseModel):
    label: str
    value: str


class BusinessInfoSection(BaseModel):
    type: Literal["businessInfo"] = "businessInfo"
    items: list[BusinessInfoItem]


class DemoInfoItem(BaseModel):
    label: str
    value: str
    # businessInfo와 달리 출처를 항목마다 들고 간다. 이 섹션에는 영업시간·대표번호처럼
    # 시간이 지나면 낡는 값이 들어오기 때문에, 화면이 확인일을 함께 보여 줄 수 있어야 한다.
    source: str
    confirmed_at: str


# 소개 영상 촬영용 매장에만 붙는 운영 정보.
#
# `businessInfo`와 모양이 거의 같은데 굳이 섹션을 나눈 이유는, 두 섹션이 **다른 규칙을
# 따르기** 때문이다. businessInfo는 forbidden_labels가 조건 없이 막고, 이쪽은 막지 않는
# 대신 오버레이 검증기의 demo_allowlist에 id가 있어야 한다. 같은 섹션 안에서 항목별로
# 규칙이 갈리면 그 분기가 곧 Wave 3.5에서 겪은 우회 경로가 된다.
class DemoInfoSection(BaseModel):
    type: Literal["demoInfo"] = "demoInfo"
    items: list[DemoInfoItem]


class LinkItem(BaseModel):
    label: str
    url: str


# 공식 채널 링크. 화면에서 누르면 외부 브라우저로 열린다.
#
# `businessInfo`·`demoInfo`와 달리 값이 사람이 읽는 문장이 아니라 **주소**다. 낡으면
# 거짓이 되는 것이 아니라 아예 열리지 않으므로, 검증기는 형식(http(s))만 보고 살아
# 있는지는 보지 않는다 — 그건 사람이 확인할 일이다.
class LinksSection(BaseModel):
    type: Literal["links"] = "links"
    items: list[LinkItem]


# --- 영업시간 ---------------------------------------------------------
#
# 이 섹션만 값이 "사람이 읽는 문장"이 아니라 **계산 대상**이다. 다른 섹션은 서버가
# 보낸 문자열을 그대로 그리면 끝이지만, 영업시간은 클라이언트가 지금 시각과 비교해
# "지금 영업 중인지"를 계산한다. 그래서 문자열 한 줄이 아니라 구조체로 내려보낸다
# (설계 9-1 · 지도·상세 UI 개선 계획 「보류 항목」 B안).
#
# **판정 문자열("영업 중"/"영업 종료")을 서버가 만들지 않는다.** 저장하는 순간 그 값은
# 저장 시점부터 틀리기 시작한다. 서버가 내려보내는 것은 규칙뿐이고 판정은 화면이 한다.


class HoursInterval(BaseModel):
    """하루 안의 영업 구간 하나. `"HH:MM"` 24시간 표기."""

    open: str
    # close < open이면 **자정을 넘긴다**(예: 22:00–02:00은 다음 날 새벽 2시까지).
    # 하루 종일 영업은 "00:00"–"24:00"으로 적는다 — close == open을 24시간으로
    # 읽으면 "0분 영업"과 구분할 수 없어 검증기가 거부한다.
    close: str


class HoursException(BaseModel):
    """특정 날짜에만 요일 규칙을 덮어쓴다. 백화점 정기 휴점일·명절이 여기 온다.

    요일 규칙만으로는 이런 날을 표현할 수 없고, 표현하지 못하면 화면이 휴점일에
    "영업 중"이라고 말한다 — 이 계약에서 가장 비싼 거짓말이다.
    """

    date: str  # YYYY-MM-DD
    closed: bool = False  # 종일 휴무
    intervals: list[HoursInterval] = []  # 단축·연장 영업. closed와 동시에 못 쓴다
    note: str | None = None  # "백화점 정기 휴점" 같은 사유. 화면에 함께 그린다

    # 이 날짜를 확인한 페이지. 섹션의 source와 **다를 수 있어서** 따로 둔다 —
    # 요일 규칙은 매장이 공지하지만 정기 휴점일은 건물(백화점)이 공지하고, 그 공지는
    # 한 달치씩만 올라왔다 내려간다. 어느 쪽을 다시 열어 봐야 하는지가 날짜마다
    # 다르므로 섹션 하나의 source로는 답이 안 나온다. 화면에는 그리지 않는다.
    source: str | None = None


class HoursSection(BaseModel):
    type: Literal["hours"] = "hours"

    # 요일 → 그날의 영업 구간 목록. 키는 mon·tue·wed·thu·fri·sat·sun 7개가 **전부**
    # 있어야 한다. 빈 배열은 "그 요일은 휴무"라는 명시이고, 키가 빠진 상태는 휴무인지
    # 모르는 것인지 구분할 수 없어 검증기가 거부한다 — 모르는 것을 "휴무"로 그리면
    # 그것도 거짓이다.
    #
    # 값이 배열인 이유는 **브레이크 타임** 때문이다. 요일당 구간이 하나라고 가정하면
    # 11:00–14:00 · 17:00–21:00로 나뉘는 음식점에서 곧바로 깨진다.
    weekly: dict[str, list[HoursInterval]]

    exceptions: list[HoursException] = []

    # 매장이 있는 지역의 UTC 오프셋(분). 한국은 서머타임이 없어 고정값 540으로
    # 정확하다. 기기 시계가 다른 시간대일 수 있어서(여행 중이거나 설정이 틀린 기기)
    # 클라이언트는 이 값으로 매장 현지 시각을 만든 뒤 비교한다.
    utc_offset_minutes: int = 540

    # 이 규칙을 실제로 확인한 날. 영업시간은 낡으면 저절로 거짓이 되므로 화면이
    # 일정 기간을 넘긴 값의 **판정을 거둔다**(요일 표는 남기고 "지금 영업 중"만
    # 말하지 않는다). 임계값과 근거는 클라이언트의 store_hours.dart에 있다.
    confirmed_at: str

    # 그 규칙이 실제로 적혀 있던 페이지. 화면에 그리지 않고 데이터를 고치는 사람이
    # 쓴다(설계 7-A-3). demoInfo가 항목마다 출처를 받는 것과 같은 이유다.
    source: str


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
    | HeroSection
    | MenuSection
    | BusinessInfoSection
    | DemoInfoSection
    | LinksSection
    | HoursSection
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
