"""폴리곤 라벨 점(pole of inaccessibility) 계산 단위 테스트.

여기서 지키려는 것은 **좌표값이 아니라 성질**이다. 격자 탐색이라 소수점 아래는
반복 횟수에 따라 흔들리는데, 라벨 위치에서 그건 중요하지 않다. 중요한 것은
"항상 폴리곤 안", "무게중심보다 경계에서 멀다", "직사각형에서는 가운데" 셋이다.
"""

from math import cos, hypot, radians, sin

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


# --- 볼록 4각형 조기 탈출 ---
#
# 주차구역형 4꼭짓점 사각형(B3~B6에 층당 150~220개)은 격자 탐색 없이 무게중심을
# 바로 돌려준다. 아래는 그 지름길이 격자 탐색과 유의미하게 다른 답을 내지 않는지
# 고정하는 테스트다. 같은 도형의 변 위에 일직선 꼭짓점 하나를 끼우면 꼭짓점이
# 5개가 되어 조기 탈출을 비켜가므로, 동일한 도형에 대한 격자 탐색 결과를 비교
# 기준으로 쓸 수 있다(일직선 점은 도형·무게중심·경계 거리를 바꾸지 않는다).


def _with_collinear_midpoint(quad: list[tuple[float, float]]) -> list[tuple[float, float]]:
    (x0, y0), (x1, y1) = quad[0], quad[1]
    return [quad[0], ((x0 + x1) / 2, (y0 + y1) / 2), *quad[1:]]


# 주차구역 실측 크기(2.5×5m)의 직사각형부터 기울어진 사각형까지. 격자 탐색도
# 무게중심에서 출발해 strictly better일 때만 옮기므로 직사각형·평행사변형은
# 완전히 같은 점이 나오고, 사다리꼴류도 어긋남이 라벨에서 의미 없는 수준이어야 한다.
@pytest.mark.parametrize(
    "quad",
    [
        [(0.0, 0.0), (2.5, 0.0), (2.5, 5.0), (0.0, 5.0)],  # 주차구역형 직사각형
        [(0.0, 0.0), (5.0, 0.0), (6.0, 2.5), (1.0, 2.5)],  # 평행사변형
        [(0.0, 0.0), (6.0, 0.0), (5.0, 2.5), (1.0, 2.5)],  # 사다리꼴
        [(0.0, 0.0), (10.0, 1.0), (11.0, 6.0), (2.0, 4.0)],  # 기울어진 볼록 4각형
    ],
)
def test_볼록_4각형_조기_탈출은_격자_탐색과_유의미하게_다르지_않다(quad):
    early = label_point(quad)
    grid = label_point(_with_collinear_midpoint(quad))

    assert _contains(early, quad)
    # 어긋남은 1m 미만(실측: 위 도형들에서 최대 0.55m) — 도면에서 아이콘 폭 수준.
    assert hypot(early[0] - grid[0], early[1] - grid[1]) < 1.0


# 오목한 4각형(화살촉꼴)은 무게중심이 폴리곤 밖이다 — 조기 탈출 대상이 아니어야
# 하고, 격자 탐색이 안쪽 점을 골라야 한다.
def test_오목한_4각형은_조기_탈출하지_않고_안쪽_점을_고른다():
    dart = [(0.0, 0.0), (10.0, 0.0), (2.0, 2.0), (0.0, 10.0)]

    assert not _contains(polygon_centroid(dart), dart)
    assert _contains(label_point(dart), dart)


# 실제 입력은 local_m가 아니라 WGS84 경위도다(tiling.py가 변환 후 호출한다).
# 절대 좌표(~127, ~37)로 외적을 계산하면 몇 미터짜리 폴리곤의 면적(~10⁻⁹ deg²)이
# 큰 항들의 상쇄에 묻혀 무게중심이 수 km 벗어난다 — 상대 좌표 계산이 이를 막는다.
# 예전 코드는 그 오답이 내부 점 검사에 걸러져 시드가 무력화됐고, 시드 없는 격자
# 탐색이 동률 능선 위 임의 점을 골라 최대 25m 이탈이 실제 배포에 있었다(207개
# 매장). 조기 탈출은 무게중심을 그대로 반환하므로 이 정밀도가 계약이 된다.
def test_무게중심은_wgs84_규모_좌표에서도_무너지지_않는다():
    # 서울 근처 약 4.4×5m짜리 매장.
    rect = [
        (127.0, 37.5),
        (127.00005, 37.5),
        (127.00005, 37.500045),
        (127.0, 37.500045),
    ]

    cx, cy = polygon_centroid(rect)
    assert cx == pytest.approx(127.000025, abs=1e-9)
    assert cy == pytest.approx(37.5000225, abs=1e-9)

    # 조기 탈출 경로(label_point)도 같은 점을 돌려준다.
    lx, ly = label_point(rect)
    assert lx == pytest.approx(127.000025, abs=1e-9)
    assert ly == pytest.approx(37.5000225, abs=1e-9)


# --- 동률 타이브레이크 — 길쭉한 직사각형의 능선 ---
#
# 길쭉한 직사각형에서는 경계 최원점이 한 점이 아니라 긴 축 위 선분(능선) 전체로
# 동률이다. 순수 `>` 갱신은 부동소수점 반올림 차이만으로 능선을 타고 시드에서
# 멀어질 수 있고, 실제 배포에서 시드가 무력화됐을 때 최대 25m 이탈로 나타났다
# (루이비통(남) 8.55m 등 207개 매장). 지금은 "유의미한 이득이 없으면 무게중심에
# 머문다"가 계약이라, 근사가 아니라 **정확히** 무게중심이어야 한다.

# 루이비통(남) 실치수(33.4×9.75m)의 축정렬 직사각형.
ELONGATED_RECT = [(0.0, 0.0), (33.4, 0.0), (33.4, 9.75), (0.0, 9.75)]


def test_길쭉한_직사각형은_정확히_무게중심을_반환한다():
    x, y = label_point(ELONGATED_RECT)

    assert (x, y) == polygon_centroid(ELONGATED_RECT)
    assert x == pytest.approx(16.7)
    assert y == pytest.approx(4.875)


# 볼록 4각형은 조기 탈출로 무게중심을 돌려주니 위 테스트만으로는 격자 탐색의
# 동률 고정을 못 본다. 변 중간점을 일직선 꼭짓점으로 끼워 5각형을 만들면 도형은
# 같은데 조기 탈출을 비켜가므로, 격자 탐색 경로에서도 동률 능선이 시드를 밀어
# 내지 않음을 고정할 수 있다.
def test_길쭉한_5각형도_격자_탐색_경로에서_정확히_무게중심에_머문다():
    pentagon = _with_collinear_midpoint(ELONGATED_RECT)

    x, y = label_point(pentagon)

    assert (x, y) == polygon_centroid(pentagon)
    assert x == pytest.approx(16.7)
    assert y == pytest.approx(4.875)


# 축정렬에서는 거리 계산이 정확히 떨어져 순수 `>` 비교도 우연히 고정된다.
# 회전을 주면 사영 계산에 반올림 노이즈가 끼어, 상대 여유 없는 갱신은 능선 위
# 후보가 시드를 1e-15 차이로 밀어낸다(41° 등에서 실측) — 이 테스트가 그 회귀를
# 실제로 무는 케이스다. 회전해도 도형은 볼록이 아닌 5각형이라 격자 탐색을 탄다.
def test_회전된_길쭉한_5각형도_반올림_노이즈에_시드를_뺏기지_않는다():
    angle = radians(41.0)
    cos_a, sin_a = cos(angle), sin(angle)
    rotated = [(x * cos_a - y * sin_a, x * sin_a + y * cos_a) for x, y in ELONGATED_RECT]
    pentagon = _with_collinear_midpoint(rotated)

    point = label_point(pentagon)

    assert point == polygon_centroid(pentagon)
    assert _contains(point, pentagon)


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
