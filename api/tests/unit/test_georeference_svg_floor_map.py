"""SVG 도면-실데이터 매장 매칭 및 좌표 앵커링 단위 테스트."""

import pytest

sys_path_added = False


def _import_module():
    # scripts/는 패키지가 아니라 sys.path 트릭으로 import한다(georeference_svg_floor_map.py 자체와 동일한 방식).
    import sys
    from pathlib import Path

    global sys_path_added
    scripts_dir = Path(__file__).resolve().parents[2] / "scripts"
    if not sys_path_added:
        sys.path.insert(0, str(scripts_dir))
        sys_path_added = True
    import georeference_svg_floor_map as module

    return module


# 공백 차이만 있는 이름("바이 레도" vs "바이레도")은 같은 매장으로 매칭돼야 한다.
def test_이름_정규화는_공백만_제거한다():
    module = _import_module()

    assert module._normalize_name("바이 레도") == module._normalize_name("바이레도")
    assert module._normalize_name("톰 포드 뷰티") == module._normalize_name("톰포드 뷰티")
    assert module._normalize_name("레페토") != module._normalize_name("리페토")


# SVG feature 중 store 종류이고 이름이 실데이터와 일치하는 것만 매칭 목록에 들어가야 한다.
def test_이름이_일치하는_매장만_매칭된다():
    module = _import_module()

    svg_features = [
        {
            "kind": "footprint",
            "name": None,
            "geometry": {"coordinates": []},
            "centroid": None,
        },
        {
            "kind": "store",
            "name": "발렌시아가",
            "geometry": {"coordinates": [{"x": 0, "y": 0}]},
            "centroid": {"x": 10.0, "y": 20.0},
        },
        {
            "kind": "store",
            "name": "존재하지않는매장",
            "geometry": {"coordinates": [{"x": 0, "y": 0}]},
            "centroid": {"x": 99.0, "y": 99.0},
        },
    ]
    real_lookup = {
        module._normalize_name("발렌시아가"): {
            "id": "store_1",
            "name": "발렌시아가",
            "local_m": {"x": 1.0, "y": 2.0},
            "wgs84": {"lat": 37.5, "lng": 127.0},
        }
    }

    matches = module._match_svg_stores(svg_features, real_lookup)

    assert len(matches) == 1
    assert matches[0]["real"]["id"] == "store_1"
    assert matches[0]["svg_feature"]["name"] == "발렌시아가"


# 대응점이 3개 미만이면(affine 6개 미지수를 결정할 수 없음) 명시적으로 에러를 낸다.
def test_매칭이_3개_미만이면_에러를_낸다(tmp_path):
    module = _import_module()
    import json

    svg_path = tmp_path / "floor.svg"
    svg_path.write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
        '<path id="building-footprint" d="M 0 0 L 100 0 L 100 100 L 0 100 Z"/>'
        '<path id="store-a" class="store" data-name="매장A" d="M 0 0 L 10 0 L 10 10 Z"/>'
        "</svg>",
        encoding="utf-8",
    )
    json_path = tmp_path / "data.json"
    json_path.write_text(
        json.dumps(
            {
                "stores": [
                    {
                        "id": "s1",
                        "name": "매장A",
                        "centroid": {
                            "local_m": {"x": 1.0, "y": 1.0},
                            "wgs84": {"lat": 37.0, "lng": 127.0},
                        },
                    }
                ]
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="3개 이상"):
        module.build_georeference(
            svg_path, json_path, building_id="b1", floor_id="f1"
        )
