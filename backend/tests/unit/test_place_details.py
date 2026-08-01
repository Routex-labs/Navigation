"""매장 상세 오버레이 로더 단위 테스트.

로더의 계약은 "디렉터리가 없어도 조용히 빈 dict"다. 데이터 작성이 API보다 늦게
끝나는 순서를 전제로 하기 때문이고, 이게 깨지면 데이터가 없는 동안 상세 API 전체가
500을 내며 클라이언트 작업이 막힌다.
"""

import json

from app.repositories.place_details import load_overlays, validate_overlay

# 실제 스키마 선언과 같은 모양의 최소 스키마. 값 자체를 여기 박아 두는 이유는
# 리소스 파일이 바뀌어도 이 테스트가 "검사 로직"만 보게 하기 위해서다.
SCHEMA = {
    "fields": {
        "summary": {"max_length": 60},
        "tags": {"max_items": 6},
        "hero": {"max_items": 6},
        "menu": {"max_items": 12},
        "businessInfo": {"max_items": 8},
    },
    "forbidden_labels": ["영업시간", "전화번호"],
}
KNOWN_IDS = {"PO-a"}
NAMES = {"PO-a": "가게A"}
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


def test_summary_길이_초과를_잡는다():
    errors = _validate({"PO-a": {"summary": "가" * 61}})

    assert any("60자" in error for error in errors)


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
    errors = _validate(
        {
            "PO-a": {
                "menu": [
                    {
                        "name": "카페 아메리카노",
                        "price": "4,700원",
                        "image_asset": "assets/place_details/menu.jpg",
                    }
                ]
            }
        }
    )

    assert any("menu 항목에 name/price/description/image_asset가 필요" in error for error in errors)


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


# 섹션 순서는 서버가 고정한다. 사진·메뉴로 매장을 먼저 판단하고, 소개는 매장 정보
# 바로 앞에 와야 클라이언트가 둘을 하나의 `매장 정보` 묶음으로 그릴 수 있다.
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
        "businessInfo": [{"label": "주소", "value": "여의대로 108", "source": "매장"}],
        "tags": ["포장"],
        "notice": {"text": "팝업", "until": "2099-01-01"},
    }

    types = [section["type"] for section in _sections(_StubStore(), "store", overlay)]

    assert types == ["hero", "notice", "menu", "tags", "summary", "businessInfo"]
    assert types.index("summary") + 1 == types.index("businessInfo")


class _StubStore:
    """폴리곤이 없는 매장. map 섹션은 오버레이가 아니라 도형에서 파생된다."""

    polygon = None
