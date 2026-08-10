"""폴리곤 라벨 점(pole of inaccessibility) 계산 단위 테스트.

여기서 지키려는 것은 **좌표값이 아니라 성질**이다. 격자 탐색이라 소수점 아래는
반복 횟수에 따라 흔들리는데, 라벨 위치에서 그건 중요하지 않다. 중요한 것은
"항상 폴리곤 안", "무게중심보다 경계에서 멀다", "직사각형에서는 가운데" 셋이다.
"""

import pytest

from app.geo.label_point import label_point, polygon_centroid


# 짝수-홀수 규칙. 테스트가 구현과 같은 함수를 쓰면 둘이 함께 틀려도 통과하므로
# 여기에 따로 둔다.
def _contains(point: tuple[float, float], ring: list[tuple[float, float]]) -> bool:
    x, y = point
    inside = False
    count = len(ring)
    for index in range(count):
        x0, y0 = ring[index]
        x1, y1 = ring[(index + 1) % count]
        if (y0 > y) != (y1 > y):
            if x < (x1 - x0) * (y - y0) / (y1 - y0) + x0:
                inside = not inside
    return inside


SQUARE = [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)]

# ㄱ자 매장. 무게중심이 꺾이는 목 근처로 끌려가 넓은 쪽을 벗어난다 — 실제
# 도면에서 아이콘이 구석에 붙어 보이던 형태다.
L_SHAPE = [
    (0.0, 0.0),
    (30.0, 0.0),
    (30.0, 6.0),
    (6.0, 6.0),
    (6.0, 30.0),
    (0.0, 30.0),
]

# 한쪽으로 길게 뻗은 통로형 매장.
CORRIDOR = [(0.0, 0.0), (40.0, 0.0), (40.0, 3.0), (0.0, 3.0)]


def test_직사각형은_한가운데를_고른다():
    x, y = label_point(SQUARE)

    assert x == pytest.approx(5.0, abs=0.1)
    assert y == pytest.approx(5.0, abs=0.1)


def test_ㄱ자_폴리곤에서도_점이_안쪽에_있다():
    point = label_point(L_SHAPE)

    assert _contains(point, L_SHAPE)


# **이 함수의 존재 이유.** 이 ㄱ자에서 무게중심은 두 팔 사이 빈 곳으로 끌려가
# 폴리곤 밖에 떨어진다 — MapLibre에 그대로 맡기면 아이콘이 매장 밖 복도에 뜬다.
def test_ㄱ자는_무게중심이_밖인데_라벨_점은_안이다():
    assert not _contains(polygon_centroid(L_SHAPE), L_SHAPE)
    assert _contains(label_point(L_SHAPE), L_SHAPE)


def test_통로형_매장도_안쪽에_있다():
    point = label_point(CORRIDOR)

    assert _contains(point, CORRIDOR)
    # 폭 3m짜리 띠라 세로로는 가운데를 벗어날 자리가 없다.
    assert point[1] == pytest.approx(1.5, abs=0.2)


# 실패 조건 — 계산할 폴리곤이 아닐 때 예외 대신 쓸 만한 점으로 떨어져야 한다.
# 타일 요청 하나가 통째로 500이 되는 것보다 라벨이 대충 찍히는 편이 낫다.
@pytest.mark.parametrize(
    "ring",
    [
        [],
        [(1.0, 2.0)],
        [(1.0, 2.0), (3.0, 4.0)],
        [(5.0, 5.0), (5.0, 5.0), (5.0, 5.0)],  # 넓이 0
    ],
)
def test_퇴화한_폴리곤도_예외를_내지_않는다(ring):
    x, y = label_point(ring)

    assert isinstance(x, float)
    assert isinstance(y, float)
