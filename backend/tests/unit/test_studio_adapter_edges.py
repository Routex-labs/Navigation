import pytest

from scripts.seed.studio_adapter import _scope_edges


def test_scope_edges_preserves_polyline_and_recomputes_length():
    edges = [{
        "id": "edge-1",
        "from": "a",
        "to": "b",
        "length_m": 999,  # Studio가 준 값은 버리고 geometry로 다시 잰다
        "geometry": {
            "source": [{"x": 1, "y": 1}, {"x": 2, "y": 2}],
            "local_m": [{"x": 0, "y": 0}, {"x": 3, "y": 0}, {"x": 3, "y": 4}],
        },
    }]

    result = _scope_edges("floor", edges)[0]

    assert result["id"] == "floor:edge-1"
    assert result["from"] == "floor:a"
    # 꺾인 복도의 중간점까지 모두 보존된다(양 끝점만 남기면 경로·길이가 유실된다).
    assert result["geometry_local_m"] == [
        {"x": 0, "y": 0},
        {"x": 3, "y": 0},
        {"x": 3, "y": 4},
    ]
    assert result["length_m"] == pytest.approx(7)


# --- 시드 facet 검증 (설계 문서 5-2: 시드가 실패로 처리) ---
# 이 검증이 붙기 전에는 store_facets.validate_*를 단위 테스트만 불렀고 시드는
# 검증 없이 적재했다 — 고아 store_id나 vocabulary 밖 값이 있어도 시드가 성공했다.
def test_배포된_facet_리소스는_검증을_통과한다():
    from scripts.seed import studio_adapter

    assert studio_adapter.validate_facet_resources() == []


@pytest.mark.parametrize(
    ("깨뜨리기", "기대_메시지"),
    [
        (
            lambda payload: payload["stores"].update(
                {"PO-없는매장": {"name": "유령매장", "styles": ["명품"]}}
            ),
            "존재하지 않는 store_id",
        ),
        (
            lambda payload: payload["stores"]["PO-SZt1uLq2l0305"].update(
                {"styles": ["없는스타일"]}
            ),
            "vocabulary에 없는 값",
        ),
        (
            lambda payload: payload["stores"]["PO-SZt1uLq2l0305"].update(
                {"name": "이름이 다른 매장"}
            ),
            "이름",
        ),
    ],
    ids=["고아_store_id", "vocabulary_밖_값", "이름_불일치"],
)
def test_깨진_오버레이는_검증에서_잡힌다(tmp_path, monkeypatch, 깨뜨리기, 기대_메시지):
    """실제 리소스를 건드리지 않고 임시 디렉터리 사본으로 검증한다."""
    import json
    import shutil

    from scripts.seed import studio_adapter

    사본 = tmp_path / "store_search_facets"
    shutil.copytree(studio_adapter.STORE_SEARCH_FACETS_DIR, 사본)
    대상 = 사본 / "shoes.json"
    payload = json.loads(대상.read_text(encoding="utf-8"))
    깨뜨리기(payload)
    대상.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

    monkeypatch.setattr(studio_adapter, "STORE_SEARCH_FACETS_DIR", 사본)
    errors = studio_adapter.validate_facet_resources()

    assert errors, "깨진 오버레이인데 검증이 통과했다"
    assert any(기대_메시지 in message for message in errors), errors


def test_검증_실패하면_시드가_예외로_멈춘다(tmp_path, monkeypatch):
    """반쯤 시드된 DB가 남지 않도록 적재 전에 멈춰야 한다."""
    from scripts.seed import studio_adapter

    monkeypatch.setattr(
        studio_adapter, "validate_facet_resources", lambda *a, **kw: ["일부러 만든 오류"]
    )
    with pytest.raises(ValueError, match="검색 facet 리소스 검증 실패"):
        studio_adapter.seed_studio()
