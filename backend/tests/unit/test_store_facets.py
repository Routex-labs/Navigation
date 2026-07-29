"""store_facets 순수 함수 단위 테스트.

이 모듈은 DB·시드를 모르는 순수 함수라서 db_session fixture가 필요 없다.
파일 I/O가 필요한 load_overlay 테스트만 tmp_path로 임시 디렉터리를 만든다.
"""

from __future__ import annotations

import json

from app.repositories import store_facets


# ── derive_facets ────────────────────────────────────────────────────────


# wave1/README.md에 확정된 5줄 매핑이 그대로 구현됐는지 하나씩 확인한다.
def test_소분류_5개가_각각_맞는_styles로_파생된다():
    assert store_facets.derive_facets("패션", "스포츠·아웃도어") == {"styles": ["스포츠"]}
    assert store_facets.derive_facets("패션", "캐주얼·스트리트") == {"styles": ["캐주얼"]}
    assert store_facets.derive_facets("패션", "컨템포러리") == {"styles": ["컨템포러리"]}
    assert store_facets.derive_facets("패션", "명품") == {"styles": ["명품"]}
    assert store_facets.derive_facets("패션", "골프") == {"styles": ["골프"]}


# 매핑에 없는 소분류(품목 축)는 styles 키 자체가 생기면 안 된다 — 빈 배열도 금지.
def test_매핑에_없는_소분류는_키가_안_생긴다():
    assert store_facets.derive_facets("패션", "슈즈") == {}
    assert store_facets.derive_facets("패션", "잡화·액세서리") == {}
    assert store_facets.derive_facets("패션", "시계·주얼리") == {}
    assert store_facets.derive_facets(None, None) == {}


def test_derive_facets는_category를_쓰지_않고_subcategory만_본다():
    # category가 달라도 subcategory가 같으면 같은 결과 — 함수가 category를 무시한다는
    # 계약을 문서화하는 회귀 테스트.
    assert store_facets.derive_facets("아무거나", "골프") == {"styles": ["골프"]}


# ── resolve_facets ───────────────────────────────────────────────────────


def test_오버레이가_없으면_파생값만_돌아온다():
    result = store_facets.resolve_facets("PO-1", "패션", "명품", overlay={})
    assert result == {"styles": ["명품"]}


# 오버레이가 파생을 이긴다 — 축 단위 병합(다른 축은 파생값을 유지).
def test_오버레이가_같은_축의_파생값을_이긴다():
    overlay = {"PO-1": {"name": "탠디", "styles": ["스포츠", "캐주얼"]}}
    result = store_facets.resolve_facets("PO-1", "패션", "슈즈", overlay=overlay)
    # 슈즈는 파생이 없으므로 오버레이 값이 그대로 최종 결과다.
    assert result == {"styles": ["스포츠", "캐주얼"]}


def test_오버레이는_축_단위로만_덮고_다른_축의_파생값은_보존한다():
    # cuisines처럼 아직 derive_facets가 모르는 축이라도, 오버레이가 그 축만 추가하면
    # styles 파생값은 그대로 남아야 한다(통째로 갈아치우지 않는다는 설계 근거).
    overlay = {"PO-1": {"cuisines": ["일식"]}}
    result = store_facets.resolve_facets("PO-1", "패션", "명품", overlay=overlay)
    assert result == {"styles": ["명품"], "cuisines": ["일식"]}


def test_오버레이가_빈_배열을_주면_해당_축을_제거한다():
    overlay = {"PO-1": {"styles": []}}
    result = store_facets.resolve_facets("PO-1", "패션", "명품", overlay=overlay)
    assert result == {}


def test_name은_facet_축으로_취급하지_않는다():
    overlay = {"PO-1": {"name": "탠디"}}
    result = store_facets.resolve_facets("PO-1", "패션", "슈즈", overlay=overlay)
    assert result == {}


# ── load_overlay ─────────────────────────────────────────────────────────


def test_파일도_디렉터리도_없으면_빈_dict를_돌려준다(tmp_path):
    missing = tmp_path / "does-not-exist"
    assert store_facets.load_overlay(missing) == {}


def test_밑줄로_시작하는_파일은_무시하고_나머지_json을_병합한다(tmp_path):
    (tmp_path / "_vocabulary.json").write_text(
        json.dumps({"version": 1, "vocabulary": {"styles": ["스포츠"]}}, ensure_ascii=False),
        encoding="utf-8",
    )
    (tmp_path / "fashion.json").write_text(
        json.dumps(
            {"version": 1, "stores": {"PO-1": {"name": "탠디", "styles": ["캐주얼"]}}},
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    (tmp_path / "food.json").write_text(
        json.dumps(
            {"version": 1, "stores": {"PO-2": {"name": "본가 스시", "cuisines": ["일식"]}}},
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    result = store_facets.load_overlay(tmp_path)

    assert result == {
        "PO-1": {"name": "탠디", "styles": ["캐주얼"]},
        "PO-2": {"name": "본가 스시", "cuisines": ["일식"]},
    }


def test_같은_store_id가_두_파일에_있으면_오류다(tmp_path):
    (tmp_path / "a.json").write_text(
        json.dumps({"version": 1, "stores": {"PO-1": {"styles": ["캐주얼"]}}}, ensure_ascii=False),
        encoding="utf-8",
    )
    (tmp_path / "b.json").write_text(
        json.dumps({"version": 1, "stores": {"PO-1": {"styles": ["명품"]}}}, ensure_ascii=False),
        encoding="utf-8",
    )

    try:
        store_facets.load_overlay(tmp_path)
        assert False, "중복 store_id는 예외를 던져야 한다"
    except ValueError as exc:
        assert "PO-1" in str(exc)


# ── validate_overlay ─────────────────────────────────────────────────────


VOCAB = {"styles": ["스포츠", "캐주얼", "컨템포러리", "명품", "골프"]}
KNOWN_IDS = {"PO-1", "PO-2"}
NAMES = {"PO-1": "탠디", "PO-2": "본가 스시"}


def _overlay(stores: dict) -> dict:
    return {"version": 1, "stores": stores}


def test_정상_오버레이는_오류가_없다():
    overlay = _overlay({"PO-1": {"name": "탠디", "styles": ["캐주얼"]}})
    assert store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES) == []


def test_version_미지원을_잡는다():
    overlay = {"version": 2, "stores": {}}
    errors = store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES)
    assert len(errors) == 1
    assert "version" in errors[0]


def test_고아_store_id를_잡는다():
    overlay = _overlay({"PO-999": {"styles": ["캐주얼"]}})
    errors = store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES)
    assert any("PO-999" in e and "존재하지 않는" in e for e in errors)


def test_name_불일치를_잡는다():
    overlay = _overlay({"PO-1": {"name": "완전 다른 이름", "styles": ["캐주얼"]}})
    errors = store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES)
    assert any("name" in e for e in errors)


def test_vocabulary_밖의_값을_잡는다():
    overlay = _overlay({"PO-1": {"styles": ["구두·정장"]}})
    errors = store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES)
    assert any("구두·정장" in e for e in errors)


def test_배열_내_중복_태그를_잡는다():
    overlay = _overlay({"PO-1": {"styles": ["캐주얼", "캐주얼"]}})
    errors = store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES)
    assert any("중복" in e for e in errors)


def test_문자열이_아닌_태그_값을_잡는다():
    overlay = _overlay({"PO-1": {"styles": ["캐주얼", 123]}})
    errors = store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES)
    assert any("문자열이 아닌" in e for e in errors)


def test_vocabulary에_없는_축_자체도_잡는다():
    overlay = _overlay({"PO-1": {"cuisines": ["일식"]}})
    errors = store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES)
    assert any("cuisines" in e for e in errors)


def test_한_매장에_여러_오류가_있으면_전부_모은다():
    overlay = _overlay(
        {
            "PO-999": {"styles": ["캐주얼"]},  # 고아
            "PO-1": {"styles": ["구두·정장", "구두·정장"]},  # vocab 밖 + 중복
        }
    )
    errors = store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES)
    assert len(errors) >= 2


# ── facet_coverage_report ────────────────────────────────────────────────


def test_커버리지_보고서는_건물별_대분류별_적용률을_센다():
    stores = [
        {
            "store_id": "PO-1",
            "building_id": "thehyundai-seoul",
            "category": "패션",
            "subcategory": "명품",
        },
        {
            "store_id": "PO-2",
            "building_id": "thehyundai-seoul",
            "category": "패션",
            "subcategory": "슈즈",  # 파생도 오버레이도 없음 → 태그 없음
        },
    ]
    report = store_facets.facet_coverage_report(stores, overlay={})

    assert report["by_building"]["thehyundai-seoul"] == {"total": 2, "tagged": 1}
    assert report["by_category"]["패션"] == {"total": 2, "tagged": 1}


def test_태그_없는_매장은_실패가_아니라_커버리지_분모에만_잡힌다():
    stores = [
        {"store_id": "PO-2", "building_id": "b1", "category": "패션", "subcategory": "슈즈"},
    ]
    report = store_facets.facet_coverage_report(stores, overlay={})
    assert report["by_building"]["b1"]["total"] == 1
    assert report["by_building"]["b1"]["tagged"] == 0
