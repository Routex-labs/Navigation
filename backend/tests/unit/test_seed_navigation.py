"""Studio 간선 입력 보완 로직 단위 테스트."""

import pytest

from scripts.seed.seed_navigation import edge_geometry_and_length


# 간선 경로선이 생략되면 양 끝 노드 좌표로 보완하는지 검증한다.
def test_간선_경로선이_없으면_노드_좌표로_보완한다():
    geometry, length_m = edge_geometry_and_length(
        {"id": "AB", "from": "A", "to": "B"},
        {
            "A": {"x": 0.0, "y": 0.0},
            "B": {"x": 3.0, "y": 4.0},
        },
    )

    assert length_m == pytest.approx(5.0)
    assert geometry == [
        {"x": 0.0, "y": 0.0},
        {"x": 3.0, "y": 4.0},
    ]


# 간선 거리가 생략되면 경로선의 구간별 길이 합을 계산하는지 검증한다.
def test_간선_거리가_없으면_경로선_전체_길이를_계산한다():
    _, length_m = edge_geometry_and_length(
        {
            "id": "AB",
            "from": "A",
            "to": "B",
            "geometry_local_m": [
                {"x": 0.0, "y": 0.0},
                {"x": 3.0, "y": 4.0},
                {"x": 6.0, "y": 4.0},
            ],
        },
        {},
    )

    assert length_m == pytest.approx(8.0)
