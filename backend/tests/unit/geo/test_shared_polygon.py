# 나눠 쓰는 폴리곤의 칸 계산. 왜 이렇게 나누는지는 docs/backend/shared-polygon-split.md.

from __future__ import annotations

import pytest

from app.geo.shared_polygon import split_shared_polygons
from app.models import Store


# 오설록·일상다완의 실제 모양을 축소한 것: 같은 폴리곤·같은 centroid, 입구 핀만 다르다.
# 긴 축은 x(가로 9.6m > 세로 6.0m).
def _shared_store(store_id: str, entrance_x: float) -> Store:
    return Store(
        id=store_id,
        floor_id="f1",
        name=store_id,
        centroid_x_m=4.8,
        centroid_y_m=3.0,
        entrance_x_m=entrance_x,
        entrance_y_m=3.0,
        polygon=[
            {"x": 0.0, "y": 0.0},
            {"x": 9.6, "y": 0.0},
            {"x": 9.6, "y": 6.0},
            {"x": 0.0, "y": 6.0},
        ],
    )


def _x_range(points: list[dict]) -> tuple[float, float]:
    xs = [point["x"] for point in points]
    return min(xs), max(xs)


# 강조 오버레이가 이 값을 쓴다. 나뉘지 않으면 한 매장을 눌러도 옆 매장 자리까지 덮인다.
def test_두_곳이_나눠_쓰면_각자_반쪽을_받는다():
    stores = [_shared_store("ilsang", 7.0), _shared_store("osulloc", 2.0)]

    split = split_shared_polygons(stores)

    assert set(split) == {"ilsang", "osulloc"}
    # 입구 핀이 왼쪽인 오설록이 왼쪽 칸이다.
    assert _x_range(split["osulloc"]) == pytest.approx((0.0, 4.8))
    assert _x_range(split["ilsang"]) == pytest.approx((4.8, 9.6))


def test_혼자_쓰는_폴리곤은_나누지_않는다():
    assert split_shared_polygons([_shared_store("alone", 2.0)]) == {}


# 세 곳 이상은 칸이 줄무늬처럼 갈라져 도면이 표처럼 보였다(실기기 확인). 그 자리는
# 묶음 라벨 하나로 접고 폴리곤은 원본 그대로 둔다.
def test_세_곳_이상은_나누지_않는다():
    stores = [_shared_store("a", 1.0), _shared_store("b", 5.0), _shared_store("c", 8.0)]

    assert split_shared_polygons(stores) == {}


# 그룹은 centroid가 같은 매장이 2곳 이상일 때만 생긴다. 이름으로 거른 부분 집합을 주면
# 짝을 못 찾아 아무것도 나누지 않는다 — 매장 검색에 이 계산을 걸지 않는 이유다.
def test_짝이_빠진_부분_집합은_나누지_않는다():
    assert split_shared_polygons([_shared_store("osulloc", 2.0)]) == {}


# 묶음 매장(다른 매장 이름을 이어 붙인 항목)이 같은 centroid에 있으면 정상 매장 둘의
# 칸이 3등분으로 쪼그라든다. 묶음을 빼야 반씩 나뉜다.
def test_묶음_매장은_칸_배치에서_빠진다():
    stores = [
        _shared_store("오설록", 2.0),
        _shared_store("일상다완", 7.0),
        _shared_store("오설록 일상다완", 4.0),
    ]

    split = split_shared_polygons(stores)

    assert "오설록 일상다완" not in split
    assert _x_range(split["오설록"]) == pytest.approx((0.0, 4.8))
    assert _x_range(split["일상다완"]) == pytest.approx((4.8, 9.6))
