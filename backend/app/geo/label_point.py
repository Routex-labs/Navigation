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

# 격자 후보가 현 최선을 대체하려면 넘어야 하는 **상대 여유**. 길쭉한 직사각형류
# 에서는 경계 최원점이 한 점이 아니라 긴 축 위 선분(능선) 전체로 동률인데, 순수
# `>` 비교는 부동소수점 반올림(상대 ~1e-16) 차이만으로도 능선을 타고 시드
# (무게중심)에서 멀어진다 — 실제로 시드가 무력화됐던 배포에서 이 동률 표류가
# 최대 25m 라벨 이탈로 나타났다(아래 polygon_centroid 주석 참고).
#
# 절대값이 아니라 상대 여유인 이유: 입력이 WGS84 경위도라 거리 규모가 ~1e-5 deg
# 수준까지 내려가므로, 규모에 비례해야 한계가 일관된다. 1e-9는 반올림 노이즈
# (상대 ~1e-16)보다 7자리 크고, 도형 차이에서 오는 진짜 개선(격자 셀 폭 이상)
# 보다는 한참 작다 — 10m 매장 기준 5nm라 라벨 위치로는 0이다. 결과적으로
# "유의미한 이득이 없으면 무게중심에 머문다"가 보장된다.
_IMPROVEMENT_MARGIN = 1e-9


# 폴리곤 링(닫히지 않아도 됨)의 면적 무게중심. 면적이 0에 가까우면(선분처럼
# 납작한 폴리곤) 꼭짓점 평균으로 떨어진다 — 0으로 나누지 않기 위해서다.
#
# 계산은 첫 꼭짓점 기준 **상대 좌표로 옮겨서** 한다. 무게중심은 평행이동에
# 불변이라 수학적으로 같은 값인데, 절대 좌표로 계산하면 수치가 무너진다:
# WGS84 경위도(~127, ~37)에서 몇 미터짜리 매장의 외적 항은 ~10³인데 진짜
# 면적은 ~10⁻⁹ deg²라, 큰 항들의 상쇄(catastrophic cancellation)에서 살아남는
# 유효자리가 모자라 무게중심이 폴리곤에서 수 km 벗어난 값으로 나온다(실데이터
# 실측). 예전 코드는 그 오답이 _contains에 걸러져 **시드가 무력화**됐고, 시드를
# 잃은 격자 탐색이 동률 능선 위 임의 점을 고르면서 최대 25m 라벨 이탈이 실제
# 배포에 있었다(전수 조사 1,626개 매장 중 207개 — 루이비통(남) 8.55m 등).
# 즉 시드 무력화가 곧 라벨 이탈의 원인이었다. 상대 좌표에서는 외적 항 자체가
# 면적 크기라 상쇄가 없다.
def polygon_centroid(ring: list[Point]) -> Point:
    count = len(ring)
    origin_x, origin_y = ring[0]
    doubled_area = 0.0
    cx = 0.0
    cy = 0.0
    for index in range(count):
        x0 = ring[index][0] - origin_x
        y0 = ring[index][1] - origin_y
        x1 = ring[(index + 1) % count][0] - origin_x
        y1 = ring[(index + 1) % count][1] - origin_y
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
    return (origin_x + cx / (6 * area), origin_y + cy / (6 * area))


# 꼭짓점 4개짜리 링이 볼록(convex)인지. 네 모서리의 외적 부호가 전부 같으면
# 볼록이다. 외적 0(일직선·중복 꼭짓점)은 퇴화로 보고 볼록으로 치지 않는다 —
# 그런 링은 아래 격자 탐색 경로가 원래 하던 대로 처리한다.
def _is_convex_quadrilateral(ring: list[Point]) -> bool:
    sign = 0
    for index in range(4):
        x0, y0 = ring[index]
        x1, y1 = ring[(index + 1) % 4]
        x2, y2 = ring[(index + 2) % 4]
        cross = (x1 - x0) * (y2 - y1) - (y1 - y0) * (x2 - x1)
        if cross == 0:
            return False
        current = 1 if cross > 0 else -1
        if sign == 0:
            sign = current
        elif current != sign:
            return False
    return True


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

    # **볼록 4각형 조기 탈출** — 격자 탐색 없이 무게중심을 바로 돌려준다.
    #
    # 이 함수는 타일 요청마다 매장 수만큼 돌고, 격자 탐색은 폴리곤당 후보를
    # ~485개 평가한다. 그런데 실데이터의 B3~B6는 주차구역형 4꼭짓점 사각형이
    # 층당 150~220개라, 이 조합이 타일 생성 비용의 대부분을 차지했다(실측:
    # 무거운 층 한 패스가 1F의 2.4~2.7배).
    #
    # 볼록 4각형이면 무게중심으로 즉시 끝내도 되는 근거:
    #   - 볼록 폴리곤의 무게중심은 항상 내부다(pole of inaccessibility를 쓰는
    #     이유였던 "무게중심이 밖으로 나가는" 문제가 애초에 없다).
    #   - 직사각형·평행사변형에서는 무게중심이 곧 경계에서 가장 먼 점이라
    #     격자 탐색과 결과가 같다(탐색도 무게중심에서 출발해 strictly better일
    #     때만 옮기므로 그대로 남는다).
    #   - 일반 볼록 4각형(사다리꼴 등)에서도 어긋남은 격자 탐색 결과 대비
    #     수십 cm 수준으로, 라벨 위치에서 화면상 의미가 없다
    #     (tests/unit/geo/test_label_point.py의 비교 테스트가 고정한다).
    # 오목하거나 퇴화한(일직선 꼭짓점) 4각형은 이 조건에 걸리지 않아 기존
    # 격자 탐색 경로를 그대로 탄다.
    vertices = ring
    if len(vertices) > 1 and vertices[0] == vertices[-1]:
        # 닫힘 중복(첫 점 = 끝 점)은 꼭짓점 수에서 뺀다.
        vertices = vertices[:-1]
    if len(vertices) == 4 and _is_convex_quadrilateral(vertices):
        return polygon_centroid(vertices)

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
                    # 유의미하게 나을 때만 옮긴다 — 순수 `>`는 동률 능선에서
                    # 반올림 노이즈로도 시드를 밀어낸다(_IMPROVEMENT_MARGIN 참고).
                    # 시드가 밖이라 best_distance가 -1.0이면 임계도 음수라
                    # 내부 후보가 항상 통과한다.
                    if distance > best_distance * (1.0 + _IMPROVEMENT_MARGIN):
                        best_distance = distance
                        best = candidate
                x += step
            y += step
        # 다음 단계는 지금 최선 주변만 더 촘촘히 본다.
        min_x, max_x = best[0] - step, best[0] + step
        min_y, max_y = best[1] - step, best[1] + step
        step /= 3

    return best
