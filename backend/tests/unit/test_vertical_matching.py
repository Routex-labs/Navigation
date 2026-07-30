"""결정적 최소비용 이분 매칭(vertical_matching) 단위 테스트.

검증 기준:
    (1) 총비용이 최소가 되는 1:1 짝을 고른다(순차 탐욕이 놓치는 최적).
    (2) 입력 순서를 어떻게 섞어도 같은 짝이 나온다(결정성).
    (3) 금지 쌍(cost=None)은 매칭에서 빠진다.
"""

from __future__ import annotations

import itertools

from scripts.transform.vertical_matching import min_cost_matching


def _dist_cost(coords):
    def cost(a, b):
        (ax, ay), (bx, by) = coords[a], coords[b]
        return abs(ax - bx) + abs(ay - by)

    return cost


def test_최적_짝을_고른다_교차가_최적인_경우():
    # a1은 b2 자리에, a2는 b1 자리에 겹친다 → 교차 매칭(a1-b2, a2-b1)이 총비용 0으로 최적.
    coords = {"a1": (0, 0), "a2": (10, 0), "b1": (10, 0), "b2": (0, 0)}
    result = dict(min_cost_matching(["a1", "a2"], ["b1", "b2"], _dist_cost(coords)))
    assert result == {"a1": "b2", "a2": "b1"}


def test_입력_순서를_섞어도_결과가_같다():
    coords = {
        "a1": (0, 0),
        "a2": (5, 5),
        "a3": (10, 0),
        "b1": (0, 1),
        "b2": (5, 6),
        "b3": (10, 1),
    }
    cost = _dist_cost(coords)
    a_ids = ["a1", "a2", "a3"]
    b_ids = ["b1", "b2", "b3"]
    baseline = min_cost_matching(a_ids, b_ids, cost)

    for a_perm in itertools.permutations(a_ids):
        for b_perm in itertools.permutations(b_ids):
            assert min_cost_matching(list(a_perm), list(b_perm), cost) == baseline


def test_금지_쌍은_제외된다():
    # b2는 a1과만 이어질 수 있고 a2와는 금지(None). a2는 b1과만.
    def cost(a, b):
        allowed = {("a1", "b1"): 1.0, ("a1", "b2"): 5.0, ("a2", "b1"): 2.0}
        return allowed.get((a, b))  # 정의 안 된 쌍은 None(금지)

    result = dict(min_cost_matching(["a1", "a2"], ["b1", "b2"], cost))
    # a2-b2는 금지라 없다. 최적: a1-b2(5)+a2-b1(2)=7 vs a1-b1(1)+a2-?(a2-b2 금지) → a1-b1,a2 미매칭.
    # 전역 최소비용은 a1-b2, a2-b1 (둘 다 유효, 총 7)로 둘 다 매칭된다.
    assert result == {"a1": "b2", "a2": "b1"}


def test_짝이_없으면_빈_결과다():
    assert min_cost_matching([], ["b1"], lambda a, b: 1.0) == []
    assert min_cost_matching(["a1"], [], lambda a, b: 1.0) == []


def test_한쪽이_남으면_매칭된_것만_반환한다():
    coords = {"a1": (0, 0), "b1": (0, 0), "b2": (100, 0)}
    result = min_cost_matching(["a1"], ["b1", "b2"], _dist_cost(coords))
    assert result == [("a1", "b1")]  # 가까운 b1과만
