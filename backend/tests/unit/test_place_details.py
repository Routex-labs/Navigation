"""매장 상세 오버레이 로더 단위 테스트.

로더의 계약은 "디렉터리가 없어도 조용히 빈 dict"다. 데이터 작성이 API보다 늦게
끝나는 순서를 전제로 하기 때문이고, 이게 깨지면 데이터가 없는 동안 상세 API 전체가
500을 내며 클라이언트 작업이 막힌다.
"""

import json

from app.repositories.place_details import load_overlays, validate_overlay

# 실제 스키마 선언과 같은 모양의 최소 스키마. 값 자체를 여기 박아 두는 이유는
# 리소스 파일이 바뀌어도 이 테스트가 "검사 로직"만 보게 하기 위해서다.
#
# 다만 **모양**은 리소스 파일과 같아야 한다. 검증기가 필수·선택 키를 스키마에서 읽기
# 때문에, 여기에 `required_keys`를 빼 두면 검증기는 "필수 키가 없는 필드"로 읽고
# 아무것도 잡지 않는다 — 테스트는 전부 통과하면서 검사는 사라진다.
SCHEMA = {
    "fields": {
        "summary": {"max_length": 60},
        "source": {"max_length": 300},
        "tags": {"max_items": 6},
        "hero": {"required_keys": ["local_asset"], "max_items": 6},
        "menu": {
            "required_keys": ["name", "image_asset"],
            "optional_keys": ["category", "price", "description", "volume", "allergens"],
            "string_array_keys": ["badges"],
            "max_items": 12,
        },
        "businessInfo": {"required_keys": ["label", "value"], "max_items": 8},
        "links": {"required_keys": ["label", "url"], "max_items": 6},
        "demoInfo": {
            "required_keys": ["label", "value", "source", "confirmed_at"],
            "max_items": 8,
        },
        "hours": {
            "required_keys": ["weekly", "source", "confirmed_at"],
            "optional_keys": ["exceptions", "utc_offset_minutes"],
        },
    },
    "forbidden_labels": ["영업시간", "전화번호"],
    "demo_allowlist": ["PO-a"],
}
KNOWN_IDS = {"PO-a", "PO-b"}
NAMES = {"PO-a": "가게A", "PO-b": "가게B"}
TODAY = "2026-07-30"


def _validate(payload):
    return validate_overlay(payload, KNOWN_IDS, NAMES, SCHEMA, TODAY)


def test_디렉터리가_없으면_빈_dict를_반환한다(tmp_path):
    assert load_overlays(tmp_path / "없는폴더") == {}


def test_파일이_없어도_빈_dict를_반환한다(tmp_path):
    assert load_overlays(tmp_path) == {}


def test_오버레이_파일을_id로_병합한다(tmp_path):
    (tmp_path / "b1-food.json").write_text(
        json.dumps(
            {
                "PO-a": {"name": "가게A", "summary": "한 줄 소개"},
                "PO-b": {"name": "가게B", "tags": ["포장"]},
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    overlays = load_overlays(tmp_path)

    assert set(overlays) == {"PO-a", "PO-b"}
    assert overlays["PO-a"]["summary"] == "한 줄 소개"


# "_"로 시작하는 파일은 스키마 선언 같은 메타데이터다. 오버레이로 읽으면
# 스키마의 최상위 키가 매장 id로 둔갑한다.
def test_언더스코어로_시작하는_파일은_읽지_않는다(tmp_path):
    (tmp_path / "_schema.json").write_text(json.dumps({"sections": ["summary"]}), encoding="utf-8")

    assert load_overlays(tmp_path) == {}


# --- 검증 ----------------------------------------------------------------
# 데이터가 원본과 어긋나는 4가지 경우를 시드가 실패로 잡아야 한다. 하나라도
# 통과시키면 틀린 정보가 사용자에게 한 번은 보인다.


def test_정상_오버레이는_오류가_없다():
    assert (
        _validate(
            {
                "PO-a": {
                    "name": "가게A",
                    "updated_at": "2026-07-01",
                    "summary": "한 줄 소개",
                    "tags": ["포장"],
                    "keyValue": [{"label": "위치", "value": "B2 서편"}],
                    "notice": {"text": "팝업 운영", "until": "2026-08-31"},
                }
            }
        )
        == []
    )


# 원본에 없는 id. 매장이 사라졌거나 오타다.
def test_고아_id를_잡는다():
    errors = _validate({"PO-없음": {"summary": "소개"}})

    assert len(errors) == 1
    assert "원본에 없는 매장 id" in errors[0]


# 이름 드리프트. 이름이 바뀌었으면 내용도 낡았을 가능성이 크다.
def test_이름_불일치를_잡는다():
    errors = _validate({"PO-a": {"name": "예전이름", "summary": "소개"}})

    assert any("이름 불일치" in error for error in errors)


# 출처가 없어 검증할 수 없는 항목. 리뷰어 눈이 아니라 코드가 막는다.
def test_출처_없는_항목을_잡는다():
    errors = _validate({"PO-a": {"keyValue": [{"label": "영업시간", "value": "10:30~20:00"}]}})

    assert any("출처가 없어" in error for error in errors)


# 만료된 고지. 지난 팝업을 계속 안내하게 된다.
def test_만료된_고지를_잡는다():
    errors = _validate({"PO-a": {"notice": {"text": "지난 팝업", "until": "2026-07-01"}}})

    assert any("만료" in error for error in errors)


# 기한 없는 고지는 시간이 지나면 조용히 거짓이 되므로 애초에 막는다.
def test_기한_없는_고지를_잡는다():
    errors = _validate({"PO-a": {"notice": {"text": "상시 안내"}}})

    assert any("until" in error for error in errors)


def test_스키마에_없는_키를_잡는다():
    errors = _validate({"PO-a": {"phone": "02-0000-0000"}})

    assert any("스키마에 없는 키" in error for error in errors)


# 길이는 막지 않는다. 60자 상한을 걸었을 때 브랜드 공식 문구를 몇 글자 차이로 버리고
# 뜻이 옅은 문장을 싣는 일이 생겼다 — 짧게 쓰는 것은 쓰는 사람의 판단이고, 검증기가
# 막을 것은 틀린 값이지 긴 값이 아니다.
def test_긴_summary도_통과한다():
    assert _validate({"PO-a": {"summary": "가" * 200}}) == []


# 빈 문자열은 여전히 막는다. 화면에 빈 소개 섹션이 생긴다.
def test_빈_summary를_잡는다():
    errors = _validate({"PO-a": {"summary": "   "}})

    assert any("summary가 비어" in error for error in errors)


# 공식 사이트에서 옮겨 온 문구는 **그 문구가 있던 페이지**가 근거다. 다시 열어 볼 수
# 없는 값이면 확인일(updated_at)이 뜻을 잃는다.
def test_출처는_http_주소여야_한다():
    errors = _validate({"PO-a": {"summary": "한 줄 소개", "source": "브랜드 공식 사이트"}})

    assert any("http(s) 주소" in error for error in errors)


def test_http_출처는_통과한다():
    assert (
        _validate(
            {
                "PO-a": {
                    "summary": "한 줄 소개",
                    "source": "https://example.com/about-us.html",
                }
            }
        )
        == []
    )


def test_빈_출처를_잡는다():
    errors = _validate({"PO-a": {"summary": "한 줄 소개", "source": "   "}})

    assert any("source가 비어" in error for error in errors)


def test_리치_상세_오버레이는_검증을_통과한다():
    assert (
        _validate(
            {
                "PO-a": {
                    "name": "가게A",
                    "updated_at": "2026-07-30",
                    "hero": [{"local_asset": "assets/place_details/store.jpg"}],
                    "menu": [
                        {
                            "name": "카페 아메리카노",
                            "price": "4,700원",
                            "description": "에스프레소와 물을 더한 커피",
                            "image_asset": "assets/place_details/menu.jpg",
                        }
                    ],
                    "businessInfo": [{"label": "주차", "value": "주차 지원 불가"}],
                }
            }
        )
        == []
    )


def test_리치_상세_필수_필드가_없는_메뉴를_잡는다():
    errors = _validate({"PO-a": {"menu": [{"name": "카페 아메리카노"}]}})

    assert any("menu 항목에 name/image_asset가 필요" in error for error in errors)


# 가격은 선택 항목이다. 스타벅스 코리아 공식 사이트처럼 가격을 공개하지 않는 출처가
# 있어서, 필수로 두면 지어낸 값을 채우는 것 말고는 통과할 방법이 없어진다.
def test_가격_없는_메뉴도_통과한다():
    assert (
        _validate(
            {
                "PO-a": {
                    "menu": [
                        {
                            "name": "리저브 콜드 브루",
                            "image_asset": "assets/place_details/menu.jpg",
                            "category": "리저브",
                            "volume": "355ml",
                        }
                    ]
                }
            }
        )
        == []
    )


# 선택 키를 **선언한 것만** 허용하는 이유. `image_assset` 같은 오타는 필수 키 검사에
# 걸리지만, 선택 키 쪽 오타(`calorie`)는 값이 조용히 사라질 뿐 아무 데서도 실패하지
# 않는다. 화면에는 칼로리 없는 카드가 뜨고 데이터는 멀쩡해 보인다.
def test_선택_키_오타를_잡는다():
    errors = _validate(
        {
            "PO-a": {
                "menu": [
                    {
                        "name": "리저브 콜드 브루",
                        "image_asset": "assets/place_details/menu.jpg",
                        "calorie": "5kcal",
                    }
                ]
            }
        }
    )

    assert any("스키마에 없는 키" in error and "calorie" in error for error in errors)


# 알레르기·배지는 메뉴 전량(316종)을 담으면서 연 두 필드다. 알레르기는 음료 122종에만
# 있고 푸드에는 아예 없으며, 배지는 316종 중 32종에만 붙는다 — 둘 다 없어도 통과해야
# 한다.
def test_알레르기와_배지가_있는_메뉴도_통과한다():
    assert (
        _validate(
            {
                "PO-a": {
                    "menu": [
                        {
                            "name": "시솔트 카라멜 콜드 브루",
                            "image_asset": "assets/place_details/starbucks_menu_9200000004544.jpg",
                            "allergens": "우유",
                            "badges": ["NEW", "시즌 한정"],
                        },
                        {
                            "name": "블루베리 베이글",
                            "image_asset": "assets/place_details/starbucks_menu_9300000004823.jpg",
                        },
                    ]
                }
            }
        )
        == []
    )


# 배지는 문자열 배열이다. `"badges": "NEW"`를 통과시키면 검증·시드는 멀쩡히 지나가고
# 응답을 만들 때 pydantic에서 터진다 — 메뉴 한 건 때문에 상세 API가 통째로 500이 된다.
def test_배지가_문자열이면_잡는다():
    errors = _validate(
        {
            "PO-a": {
                "menu": [
                    {
                        "name": "시솔트 카라멜 콜드 브루",
                        "image_asset": "assets/place_details/menu.jpg",
                        "badges": "NEW",
                    }
                ]
            }
        }
    )

    assert any("badges는 문자열 배열" in error for error in errors)


# 링크는 값이 문장이 아니라 주소다. 열리지 않는 주소는 화면에서 아무 일도 일어나지
# 않는 버튼이 되므로, 최소한 형식이 주소인지는 시드가 막는다.


def test_링크의_url은_http_주소여야_한다():
    errors = _validate({"PO-a": {"links": [{"label": "공식 사이트", "url": "starbucks.co.kr"}]}})

    assert any("http(s) 주소" in error for error in errors)


def test_정상_링크는_통과한다():
    assert (
        _validate({"PO-a": {"links": [{"label": "공식 사이트", "url": "https://www.starbucks.co.kr/index.do"}]}}) == []
    )


# --- demoInfo (소개 영상용 예외) ---
#
# forbidden_labels를 적용하지 않는 유일한 자리다. 예외를 열었으므로 "누가 쓸 수
# 있나"와 "언제 확인한 값인가"를 대신 검사하고, 아래 네 건이 그 두 가지를 본다.


def test_demoInfo는_허용_목록에_있는_매장만_쓴다():
    errors = _validate(
        {
            "PO-b": {
                "name": "가게B",
                "demoInfo": [
                    {
                        "label": "영업시간",
                        "value": "10:30~20:00",
                        "source": "https://example.com/store",
                        "confirmed_at": "2026-07-30",
                    }
                ],
            }
        }
    )

    assert any("demo_allowlist" in error for error in errors)


def test_demoInfo는_금지_라벨을_쓸_수_있다():
    assert (
        _validate(
            {
                "PO-a": {
                    "demoInfo": [
                        {
                            "label": "영업시간",
                            "value": "월~목 10:30~20:00",
                            "source": "https://example.com/store",
                            "confirmed_at": "2026-07-30",
                        }
                    ]
                }
            }
        )
        == []
    )


def test_demoInfo의_출처는_http_주소여야_한다():
    errors = _validate(
        {
            "PO-a": {
                "demoInfo": [
                    {
                        "label": "영업시간",
                        "value": "월~목 10:30~20:00",
                        "source": "매장 방문 확인",
                        "confirmed_at": "2026-07-30",
                    }
                ]
            }
        }
    )

    assert any("http(s) 주소" in error for error in errors)


def test_demoInfo의_확인일_형식을_잡는다():
    errors = _validate(
        {
            "PO-a": {
                "demoInfo": [
                    {
                        "label": "영업시간",
                        "value": "월~목 10:30~20:00",
                        "source": "https://example.com/store",
                        "confirmed_at": "2026년 7월",
                    }
                ]
            }
        }
    )

    assert any("confirmed_at" in error for error in errors)


# --- hours (요일별 영업시간 구조체) ---
#
# `demoInfo`와 달리 허용 목록이 없다. 대신 구조가 전부 검사되고, "영업 중/영업 종료"
# 판정 문자열은 아예 저장하지 않는다. 아래는 그 검사들이 실제로 도는지를 본다 —
# 검증이 비어 있으면 화면 계산이 아무리 맞아도 틀린 규칙 위에서 도는 셈이다.


def _hours(**overrides):
    payload = {
        "weekly": {
            "mon": [],
            "tue": [{"open": "10:30", "close": "20:00"}],
            "wed": [{"open": "10:30", "close": "20:00"}],
            "thu": [{"open": "10:30", "close": "20:00"}],
            "fri": [{"open": "10:30", "close": "20:30"}],
            "sat": [{"open": "10:30", "close": "20:30"}],
            "sun": [{"open": "10:30", "close": "20:30"}],
        },
        "confirmed_at": "2026-07-30",
        "source": "https://example.com/store",
    }
    payload.update(overrides)
    return {"PO-b": {"name": "가게B", "hours": payload}}


# 허용 목록에 없는 매장(PO-b)도 쓸 수 있다. hours는 자유 문자열이 아니라 검증된
# 구조체라 demoInfo와 같은 이유로 가둘 필요가 없다 — 애초에 B안의 목적이 전 매장
# 확대다.
def test_hours는_허용_목록_없이도_쓸_수_있다():
    assert _validate(_hours()) == []


def test_요일이_하나라도_빠지면_잡는다():
    weekly = _hours()["PO-b"]["hours"]["weekly"]
    del weekly["mon"]

    errors = _validate(_hours(weekly=weekly))

    assert any("요일" in error for error in errors)


def test_브레이크_타임_구간_배열을_받는다():
    weekly = _hours()["PO-b"]["hours"]["weekly"]
    weekly["tue"] = [{"open": "11:00", "close": "14:00"}, {"open": "17:00", "close": "21:00"}]

    assert _validate(_hours(weekly=weekly)) == []


def test_겹치는_구간을_잡는다():
    weekly = _hours()["PO-b"]["hours"]["weekly"]
    weekly["tue"] = [{"open": "11:00", "close": "15:00"}, {"open": "14:00", "close": "21:00"}]

    errors = _validate(_hours(weekly=weekly))

    assert any("겹치거나" in error for error in errors)


def test_자정을_넘긴_구간을_받는다():
    weekly = _hours()["PO-b"]["hours"]["weekly"]
    weekly["tue"] = [{"open": "22:00", "close": "02:00"}]

    assert _validate(_hours(weekly=weekly)) == []


# 자정을 넘긴 구간 뒤에 같은 날 구간이 또 오면 반드시 겹친다.
def test_자정_넘김은_그날의_마지막_구간이어야_한다():
    weekly = _hours()["PO-b"]["hours"]["weekly"]
    weekly["tue"] = [{"open": "22:00", "close": "02:00"}, {"open": "23:00", "close": "23:30"}]

    errors = _validate(_hours(weekly=weekly))

    assert any("마지막이어야" in error for error in errors)


# 금 22:00–03:00 뒤에 토 02:00 개점이 오면 토 02:30에 어느 규칙이 이기는지가
# 데이터가 아니라 구현 순서로 정해진다.
def test_자정_넘김이_다음_날_첫_구간과_겹치면_잡는다():
    weekly = _hours()["PO-b"]["hours"]["weekly"]
    weekly["fri"] = [{"open": "22:00", "close": "03:00"}]
    weekly["sat"] = [{"open": "02:00", "close": "20:00"}]

    errors = _validate(_hours(weekly=weekly))

    assert any("다음 날" in error or "sat 첫 구간" in error for error in errors)


# 종일 영업은 00:00–24:00이다. open == close를 24시간으로 읽으면 "0분 영업"과
# 구분할 수 없다.
def test_종일_영업은_00시부터_24시까지다():
    weekly = {key: [{"open": "00:00", "close": "24:00"}] for key in ("mon", "tue", "wed", "thu", "fri", "sat", "sun")}

    assert _validate(_hours(weekly=weekly)) == []


def test_open과_close가_같으면_잡는다():
    weekly = _hours()["PO-b"]["hours"]["weekly"]
    weekly["tue"] = [{"open": "10:00", "close": "10:00"}]

    errors = _validate(_hours(weekly=weekly))

    assert any("같습니다" in error for error in errors)


def test_시각_형식을_잡는다():
    weekly = _hours()["PO-b"]["hours"]["weekly"]
    weekly["tue"] = [{"open": "10시 30분", "close": "20:00"}]

    errors = _validate(_hours(weekly=weekly))

    assert any("HH:MM" in error for error in errors)


def test_예외_휴점일을_받는다():
    exceptions = [{"date": "2026-09-17", "closed": True, "note": "백화점 정기 휴점"}]

    assert _validate(_hours(exceptions=exceptions)) == []


def test_예외_단축영업을_받는다():
    exceptions = [{"date": "2026-09-18", "intervals": [{"open": "10:30", "close": "18:00"}]}]

    assert _validate(_hours(exceptions=exceptions)) == []


# 예외의 출처는 섹션의 출처와 다를 수 있다 — 요일 규칙은 매장이 공지하지만 정기
# 휴점일은 건물(백화점)이 공지한다. 어느 페이지를 다시 열어 봐야 하는지가 날짜마다
# 다르므로, 섹션 하나의 source로는 그 질문에 답할 수 없다.
def test_예외에_자기_출처를_달_수_있다():
    exceptions = [
        {
            "date": "2026-09-17",
            "closed": True,
            "note": "백화점 정기 휴점",
            "source": "https://www.ehyundai.com/newPortal/NS/NS000002_V.do?seq=2092964",
        }
    ]

    assert _validate(_hours(exceptions=exceptions)) == []


def test_예외의_출처가_주소가_아니면_잡는다():
    exceptions = [{"date": "2026-09-17", "closed": True, "source": "백화점 공지"}]

    errors = _validate(_hours(exceptions=exceptions))

    assert any("source는 http(s)" in error for error in errors)


def test_예외에_closed와_intervals를_함께_쓰면_잡는다():
    exceptions = [{"date": "2026-09-17", "closed": True, "intervals": [{"open": "10:30", "close": "18:00"}]}]

    errors = _validate(_hours(exceptions=exceptions))

    assert any("함께 쓸 수 없습니다" in error for error in errors)


def test_아무것도_말하지_않는_예외를_잡는다():
    errors = _validate(_hours(exceptions=[{"date": "2026-09-17", "note": "확인 필요"}]))

    assert any("closed 또는 intervals" in error for error in errors)


# 2026-02-30은 형식만 보면 통과한다. 그 예외는 영원히 걸리지 않으므로 휴점일을
# 적어 둔 사람은 적용됐다고 믿는다.
def test_없는_날짜의_예외를_잡는다():
    errors = _validate(_hours(exceptions=[{"date": "2026-02-30", "closed": True}]))

    assert any("없는 날짜" in error for error in errors)


def test_예외_날짜_중복을_잡는다():
    exceptions = [
        {"date": "2026-09-17", "closed": True},
        {"date": "2026-09-17", "intervals": [{"open": "10:30", "close": "18:00"}]},
    ]

    errors = _validate(_hours(exceptions=exceptions))

    assert any("두 번" in error for error in errors)


# 지난 예외는 아무것도 표시하지 않아 거짓을 만들지 않는다. 오류로 만들면 데이터를
# 아무도 건드리지 않은 날 시드가 죽는다(notice와 다른 점).
def test_지난_예외는_통과한다():
    assert _validate(_hours(exceptions=[{"date": "2026-01-01", "closed": True}])) == []


def test_hours의_출처는_http_주소여야_한다():
    errors = _validate(_hours(source="스타벅스 공식 사이트"))

    assert any("hours.source" in error for error in errors)


def test_hours의_확인일_형식을_잡는다():
    errors = _validate(_hours(confirmed_at="2026년 7월"))

    assert any("confirmed_at" in error for error in errors)


# 미래 확인일은 오타다. 그대로 두면 낡음 판정이 영영 걸리지 않는다.
def test_미래_확인일을_잡는다():
    errors = _validate(_hours(confirmed_at="2027-01-01"))

    assert any("미래" in error for error in errors)


def test_hours의_모르는_키를_잡는다():
    errors = _validate(_hours(timezone="Asia/Seoul"))

    assert any("스키마에 없는 키" in error and "timezone" in error for error in errors)


# --- hours 섹션 조립 ---


def test_hours_섹션은_요일_7개를_모두_싣는다():
    from app.repositories.place_detail_queries import _sections

    overlay = {"hours": _hours()["PO-b"]["hours"]}

    section = next(s for s in _sections(_StubStore(), "store", overlay) if s["type"] == "hours")

    assert set(section["weekly"]) == {"mon", "tue", "wed", "thu", "fri", "sat", "sun"}
    assert section["weekly"]["mon"] == []
    assert section["weekly"]["tue"] == [{"open": "10:30", "close": "20:00"}]
    assert section["utc_offset_minutes"] == 540


# 서버가 "영업 중"을 계산해 넣으면 그 값은 응답을 만든 순간부터 틀리기 시작하고,
# ETag 캐시가 걸려 있어 더 오래 살아남는다.
def test_hours_섹션에_판정_문자열이_없다():
    from app.repositories.place_detail_queries import _sections

    overlay = {"hours": _hours()["PO-b"]["hours"]}

    section = next(s for s in _sections(_StubStore(), "store", overlay) if s["type"] == "hours")

    assert "영업" not in json.dumps(section, ensure_ascii=False)
    assert set(section) == {"type", "weekly", "exceptions", "utc_offset_minutes", "confirmed_at", "source"}


# 요일이 빠진 데이터가 검증을 우회해 들어와도 화면에 "모르는 요일 = 휴무"가 뜨지
# 않게 하는 두 번째 문이다.
def test_요일이_빠진_hours는_섹션을_만들지_않는다():
    from app.repositories.place_detail_queries import _sections

    weekly = _hours()["PO-b"]["hours"]["weekly"]
    del weekly["sun"]
    overlay = {"hours": {**_hours()["PO-b"]["hours"], "weekly": weekly}}

    assert [s for s in _sections(_StubStore(), "store", overlay) if s["type"] == "hours"] == []


# 영업시간은 소개·메뉴보다 위다 — 상세를 연 사람이 가장 먼저 정하는 것이
# "지금 갈 수 있나"이기 때문이다.
def test_hours는_소개보다_먼저_온다():
    from app.repositories.place_detail_queries import _sections

    overlay = {"summary": "한 줄 소개", "hours": _hours()["PO-b"]["hours"]}

    types = [section["type"] for section in _sections(_StubStore(), "store", overlay)]

    assert types == ["hours", "summary"]


# --- businessInfo 금지 라벨 (회귀 방지) ---
#
# businessInfo는 한동안 금지 라벨 검사를 통째로 건너뛰었고, 그 상태로 출처 없는
# `영업시간`·`대표번호`가 응답에 실려 나갔다. 검증기·시드·테스트가 전부 통과하는
# 채로였다. 아래 두 건이 그 구멍이 다시 열리는지를 본다.


def test_businessInfo의_금지_라벨을_잡는다():
    errors = _validate({"PO-a": {"businessInfo": [{"label": "영업시간", "value": "월~목 10:30~20:00"}]}})

    assert any("넣을 수 없는 항목" in error for error in errors)


def test_businessInfo의_정상_항목은_통과한다():
    assert _validate({"PO-a": {"businessInfo": [{"label": "주차", "value": "주차 지원 불가"}]}}) == []


# 섹션 순서는 서버가 고정한다. 사진 → 소개 → 메뉴 → 주소 순이고, 건물 안에서
# 길을 찾는 사용자에게 이미 아는 정보인 주소는 맨 아래다.
def test_섹션_순서를_서버가_고정한다():
    from app.repositories.place_detail_queries import _sections

    overlay = {
        "summary": "한 줄 소개",
        "hero": [{"local_asset": "assets/a.jpg", "source": "촬영"}],
        "menu": [
            {
                "name": "라떼",
                "price": "5,200원",
                "description": "에스프레소와 우유",
                "image_asset": "assets/latte.jpg",
                "source": "매장",
            }
        ],
        "demoInfo": [
            {
                "label": "영업시간",
                "value": "월~목 10:30~20:00",
                "source": "https://example.com/store",
                "confirmed_at": "2026-07-30",
            }
        ],
        "businessInfo": [{"label": "주소", "value": "여의대로 108", "source": "매장"}],
        "tags": ["포장"],
        "notice": {"text": "팝업", "until": "2099-01-01"},
    }

    types = [section["type"] for section in _sections(_StubStore(), "store", overlay)]

    # demoInfo가 businessInfo보다 위인 이유: 영업시간은 매장을 고르는 데 실제로
    # 쓰이고, 아래 주소는 건물 주소라 이미 아는 정보다.
    assert types == ["hero", "notice", "tags", "summary", "menu", "demoInfo", "businessInfo"]


# 값이 없는 선택 키를 빈 문자열로 채워 내려보내지 않는다. 빈 값이 실려 나가면
# 클라이언트가 "있는데 비었다"와 "없다"를 구분하는 분기를 갖게 되고, 그 분기가
# 카드마다 다른 높이로 새어 나온다(계약 4-2 규칙 1과 같은 이유).
def test_비어_있는_선택_키는_아예_내려보내지_않는다():
    from app.repositories.place_detail_queries import _sections

    overlay = {
        "menu": [
            {
                "name": "리저브 콜드 브루",
                "image_asset": "assets/reserve.jpg",
                "category": "리저브",
                "price": "   ",
            }
        ]
    }

    menu = next(s for s in _sections(_StubStore(), "store", overlay) if s["type"] == "menu")

    assert menu["items"] == [
        {
            "name": "리저브 콜드 브루",
            "image_asset": "assets/reserve.jpg",
            "category": "리저브",
        }
    ]


# 배지도 같은 규칙을 따른다. 문자열이 아니라 배열이라 "빈 값"의 모양만 다르다 —
# `[]`나 공백만 든 배열이 실려 나가면 클라이언트가 "배지가 없다"와 "배지 목록이
# 비었다"를 구분하는, 화면에서는 결과가 같은 분기를 갖게 된다.
def test_빈_배지_배열은_내려보내지_않는다():
    from app.repositories.place_detail_queries import _sections

    overlay = {
        "menu": [
            {"name": "라떼", "image_asset": "assets/latte.jpg", "badges": []},
            {"name": "콜드 브루", "image_asset": "assets/cb.jpg", "badges": ["  ", "NEW"]},
        ]
    }

    menu = next(s for s in _sections(_StubStore(), "store", overlay) if s["type"] == "menu")

    assert menu["items"] == [
        {"name": "라떼", "image_asset": "assets/latte.jpg"},
        {"name": "콜드 브루", "image_asset": "assets/cb.jpg", "badges": ["NEW"]},
    ]


class _StubStore:
    """폴리곤이 없는 매장. map 섹션은 오버레이가 아니라 도형에서 파생된다."""

    polygon = None


# --- 실제 오버레이 ↔ 실제 asset 대조 -------------------------------------
#
# 위 테스트들은 전부 검사 **로직**을 본다. 이 아래 두 개만 저장소에 실제로 들어 있는
# 오버레이와 사진을 맞춰 본다.
#
# 검증기가 이걸 대신 못 하는 이유: 오버레이는 백엔드에 있고 사진은 클라이언트 번들에
# 있어서, `image_asset`은 백엔드 입장에서 그냥 문자열이다. 경로가 틀려도 시드·API·
# 클라이언트 파싱이 전부 통과하고 **화면에서만** 깨진다 — 그것도 예외가 아니라
# 회색 상자로. 316종을 손으로 넣은 다음이라 한 건이 조용히 어긋나기 딱 좋은 자리다.


def _asset_root():
    from pathlib import Path

    return Path(__file__).resolve().parents[3] / "client"


def _referenced_assets():
    from app.repositories.place_details import load_overlays

    referenced = set()
    for overlay in load_overlays().values():
        for field, key in (("hero", "local_asset"), ("menu", "image_asset")):
            for item in overlay.get(field) or []:
                if isinstance(item, dict) and isinstance(item.get(key), str):
                    referenced.add(item[key])
    return referenced


def test_오버레이가_참조하는_사진이_전부_번들에_있다():
    root = _asset_root()
    missing = sorted(path for path in _referenced_assets() if not (root / path).is_file())

    assert missing == []


# 반대 방향. 지운 메뉴의 사진이 남아 있으면 APK만 무거워지고, 다음 사람은 그게 쓰이는
# 사진인지 확인할 방법이 없다. 매장 사진(`*_store_*`)은 대상이 아니다 — 이름 규칙이
# 없어 사람이 골라 넣고 골라 빼는 자산이다.
#
# 브랜드 이름을 박지 않고 `*_menu_*`로 보는 이유: 한때 `starbucks_menu_*`만 훑었는데,
# 그러면 브랜드가 늘어난 날 새 사진들은 **가드 밖에서** 쌓인다. 감시 대상을 늘리는
# 일을 사람이 기억해야 하는 구조는 반드시 한 번은 잊힌다.
def test_참조되지_않는_메뉴_사진이_없다():
    referenced = _referenced_assets()
    menu_dir = _asset_root() / "assets" / "place_details"

    orphans = sorted(
        path.name for path in menu_dir.glob("*_menu_*") if f"assets/place_details/{path.name}" not in referenced
    )

    assert orphans == []
