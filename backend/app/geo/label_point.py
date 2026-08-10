# 폴리곤 안에서 **라벨을 놓기 가장 좋은 점**을 고른다.
#
# ## 왜 무게중심이 아닌가
#
# MapLibre는 폴리곤 feature에 심볼(아이콘+이름)을 얹을 때 **면적 무게중심**에
# 찍는다. 직사각형 매장에서는 그게 곧 눈에 보이는 가운데지만, ㄱ자로 꺾이거나
# 한쪽이 길게 뻗은 매장에서는 무게중심이 실제로 넓은 쪽을 벗어나 구석이나
# 좁은 목에 걸린다.
#
# 실측(데이터셋 1F 매장 60개): 무게중심과 아래 계산의 차이가 중앙값 0.22m로
# 대부분은 같지만, **13개가 1m 넘게, 6개가 2m 넘게, 최대 8.77m 어긋난다.**
# 도면에서 1m는 아이콘 몇 개 폭이라 "저 아이콘이 어느 매장 것인지" 판단이
# 흔들리기 충분하다.
#
# ## 무엇을 계산하나 — pole of inaccessibility
#
# 폴리곤 내부에서 **경계로부터 가장 멀리 떨어진 점**이다. 가장 넓게 트인 자리를
# 고르는 것이라 라벨·아이콘을 놓기에 알맞고, 오목한 폴리곤에서도 항상 내부에
# 있다는 성질이 있다(무게중심은 그 보장이 없다).
#
# 정확한 해를 구하는 대신 **격자를 좁혀 가며 탐색**한다. 라벨 위치는 소수점
# 아래를 다툴 문제가 아니고(1px도 안 되는 차이는 화면에서 구분되지 않는다),
# 이 함수가 타일 요청마다 매장 수만큼 돌기 때문이다. 반복 횟수를 상수로
# 고정해 최악의 경우에도 시간이 예측 가능하게 둔다.
#
# 외부 지오 라이브러리(shapely 등)를 쓰지 않는 이유는 [tiling.py] 상단 규칙과
# 같다 — 이 계층은 순수 좌표 계산만 하고 포맷·ORM·프레임워크를 모른다.

from __future__ import annotations

from math import hypot

Point = tuple[float, float]

# 격자를 몇 단계나 좁힐지. 단계마다 셀이 1/3로 줄어드는데, 폴리곤 지름의
# 1/16에서 시작하므로 5단계면 지름의 약 1/4000까지 내려간다. 10m 매장이면
# 2.5mm — 화면에서 의미가 사라지는 선을 한참 지난다.
_REFINE_STEPS = 5

# 첫 격자를 폴리곤 bbox의 긴 변 기준 몇 등분으로 시작할지. 너무 성기면
# 좁은 통로형 매장에서 내부 점을 하나도 못 찍고 시작한다.
_INITIAL_DIVISIONS = 16


# 폴리곤 링(닫히지 않아도 됨)의 면적 무게중심. 면적이 0에 가까우면(선분처럼
# 납작한 폴리곤) 꼭짓점 평균으로 떨어진다 — 0으로 나누지 않기 위해서다.
def polygon_centroid(ring: list[Point]) -> Point:
    count = len(ring)
    doubled_area = 0.0
    cx = 0.0
    cy = 0.0
    for index in range(count):
        x0, y0 = ring[index]
        x1, y1 = ring[(index + 1) % count]
        cross = x0 * y1 - x1 * y0
        doubled_area += cross
        cx += (x0 + x1) * cross
        cy += (y0 + y1) * cross
    if abs(doubled_area) < 1e-12:
        return (
            sum(x for x, _ in ring) / count,
            sum(y for _, y in ring) / count,
        )
    area = doubled_area * 0.5
    return (cx / (6 * area), cy / (6 * area))


# 점이 링 내부인지(짝수-홀수 규칙). 경계 위 점의 판정은 정의하지 않는다 —
# 탐색 격자가 경계에 정확히 얹히는 경우는 아래에서 거리로 다시 걸러진다.
def _contains(point: Point, ring: list[Point]) -> bool:
    x, y = point
    inside = False
    count = len(ring)
    for index in range(count):
        x0, y0 = ring[index]
        x1, y1 = ring[(index + 1) % count]
        if (y0 > y) != (y1 > y):
            crossing_x = (x1 - x0) * (y - y0) / (y1 - y0) + x0
            if x < crossing_x:
                inside = not inside
    return inside


# 점에서 링의 가장 가까운 변까지의 거리.
def _distance_to_boundary(point: Point, ring: list[Point]) -> float:
    x, y = point
    best = float("inf")
    count = len(ring)
    for index in range(count):
        x0, y0 = ring[index]
        x1, y1 = ring[(index + 1) % count]
        dx = x1 - x0
        dy = y1 - y0
        length_squared = dx * dx + dy * dy
        if length_squared == 0:
            best = min(best, hypot(x - x0, y - y0))
            continue
        # 변 위로 정사영한 위치를 [0,1]로 자른다(끝점 밖이면 끝점이 최근접).
        t = ((x - x0) * dx + (y - y0) * dy) / length_squared
        t = max(0.0, min(1.0, t))
        best = min(best, hypot(x - (x0 + t * dx), y - (y0 + t * dy)))
    return best


# 링 안에서 라벨을 놓을 점을 고른다.
#
# 꼭짓점이 3개 미만이면 계산할 폴리곤이 아니므로 꼭짓점 평균으로 떨어진다.
# 탐색이 내부 점을 하나도 못 찾는 경우(면적이 사실상 0인 납작한 폴리곤)도
# 무게중심으로 떨어진다 — 라벨을 안 그리는 것보다 낫다.
def label_point(ring: list[Point]) -> Point:
    if len(ring) < 3:
        if not ring:
            return (0.0, 0.0)
        return (
            sum(x for x, _ in ring) / len(ring),
            sum(y for _, y in ring) / len(ring),
        )

    xs = [x for x, _ in ring]
    ys = [y for _, y in ring]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    span = max(max_x - min_x, max_y - min_y)
    if span <= 0:
        return polygon_centroid(ring)

    # 무게중심이 내부라면 그것을 출발점으로 삼는다. 직사각형처럼 무게중심이
    # 이미 답인 폴리곤에서 탐색이 그보다 나쁜 점을 고르는 일을 막는다.
    best = polygon_centroid(ring)
    best_distance = _distance_to_boundary(best, ring) if _contains(best, ring) else -1.0

    step = span / _INITIAL_DIVISIONS
    for _ in range(_REFINE_STEPS):
        y = min_y
        while y <= max_y:
            x = min_x
            while x <= max_x:
                candidate = (x, y)
                if _contains(candidate, ring):
                    distance = _distance_to_boundary(candidate, ring)
                    if distance > best_distance:
                        best_distance = distance
                        best = candidate
                x += step
            y += step
        # 다음 단계는 지금 최선 주변만 더 촘촘히 본다.
        min_x, max_x = best[0] - step, best[0] + step
        min_y, max_y = best[1] - step, best[1] + step
        step /= 3

    return best
