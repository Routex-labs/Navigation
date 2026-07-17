"""층별 local_m 프레임을 건물 공통 프레임으로 정규화한다.

왜 필요한가:
  Studio는 층마다 좌표 변환을 따로 피팅해 내보내므로 층별 local_m 스케일이 다르다.
  같은 건물인데 외곽 치수가 층마다 다르게 나온다(2F 111x94m · 3F 70x85m · 4F 67x102m).
  그런데 백엔드는 건물당 local_m->wgs84 변환을 **하나만** 피팅한다
  (app/queries/geo_transform.py:fit_building_geo_transform — 건물의 모든 층 Node를 모아서
  피팅). 층 프레임이 제각각이면 이 피팅이 무의미해지므로, 적재 전에 모든 층을
  기준층 프레임으로 맞춰야 한다.

어떻게:
  엘리베이터는 층이 달라도 물리적으로 같은 자리에 있다. 이 성질을 이용해
  기준층(1F)과 대상층의 엘리베이터를 대응점으로 삼아 2D 아핀(6-DOF)을 피팅한다.
  1F는 실측 wgs84 앵커를 가진 유일한 층이라 기준으로 삼는다.
"""

from __future__ import annotations

from math import hypot

Affine = tuple[tuple[float, float, float], tuple[float, float, float]]
IDENTITY: Affine = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0))

# 대응점으로 쓸 노드 타입. 엘리베이터는 층 간 위치가 고정이다.
ANCHOR_TYPE = "elevator"
MIN_ANCHORS = 3  # 아핀 6-DOF를 풀려면 최소 3점


def apply(affine: Affine, x: float, y: float) -> tuple[float, float]:
    (a, b, c), (d, e, f) = affine
    return a * x + b * y + c, d * x + e * y + f


def apply_point(affine: Affine, point: dict) -> dict:
    x, y = apply(affine, point["x"], point["y"])
    return {"x": round(x, 6), "y": round(y, 6)}


def fit_affine(pairs: list[tuple[float, float, float, float]]) -> Affine:
    """(sx, sy, tx, ty) 대응점들로 source->target 2D 아핀을 최소자승 피팅한다."""
    if len(pairs) < MIN_ANCHORS:
        raise ValueError(f"대응점이 {len(pairs)}개뿐입니다(최소 {MIN_ANCHORS}개 필요).")
    normal = [[0.0] * 3 for _ in range(3)]
    rhs_x, rhs_y = [0.0] * 3, [0.0] * 3
    for sx, sy, tx, ty in pairs:
        v = (sx, sy, 1.0)
        for i in range(3):
            for j in range(3):
                normal[i][j] += v[i] * v[j]
            rhs_x[i] += v[i] * tx
            rhs_y[i] += v[i] * ty

    def solve(matrix: list[list[float]], rhs: list[float]) -> tuple[float, float, float]:
        m = [row[:] + [rhs[i]] for i, row in enumerate(matrix)]
        for col in range(3):
            pivot = max(range(col, 3), key=lambda r: abs(m[r][col]))
            m[col], m[pivot] = m[pivot], m[col]
            if abs(m[col][col]) < 1e-12:
                raise ValueError("대응점이 일직선이라 아핀을 풀 수 없습니다.")
            for row in range(3):
                if row == col:
                    continue
                factor = m[row][col] / m[col][col]
                for k in range(col, 4):
                    m[row][k] -= factor * m[col][k]
        return tuple(m[i][3] / m[i][i] for i in range(3))  # type: ignore[return-value]

    return solve(normal, rhs_x), solve(normal, rhs_y)


def anchor_points(studio: dict) -> list[dict]:
    return [
        node["position"]["local_m"]
        for node in studio["nodes"]
        if node.get("type") == ANCHOR_TYPE
    ]


def _bbox_normalized(points: list[dict]) -> list[tuple[float, float]]:
    """대응점 짝짓기를 위해 각 층의 앵커를 자기 bbox 기준으로 0~1 정규화한다.

    층마다 local_m 스케일이 달라 절대 거리로는 짝지을 수 없기 때문이다.
    """
    xs = [p["x"] for p in points]
    ys = [p["y"] for p in points]
    width = max(max(xs) - min(xs), 1e-9)
    height = max(max(ys) - min(ys), 1e-9)
    return [((p["x"] - min(xs)) / width, (p["y"] - min(ys)) / height) for p in points]


def match_anchors(source: list[dict], target: list[dict]) -> list[tuple[float, float, float, float]]:
    """정규화 좌표상 거리가 가까운 순으로 source/target 앵커를 1:1 짝짓는다.

    한쪽을 순서대로 순회하며 탐욕적으로 고르면, 양쪽 개수가 다를 때(예: 1F는 5개인데
    3F는 4개) 짝이 밀려 엉뚱하게 매칭된다. 그래서 모든 조합을 거리순으로 정렬해
    전역적으로 가까운 쌍부터 확정한다.
    """
    if not source or not target:
        return []
    ns, nt = _bbox_normalized(source), _bbox_normalized(target)
    combos = sorted(
        (
            (hypot(ns[i][0] - nt[j][0], ns[i][1] - nt[j][1]), i, j)
            for i in range(len(ns))
            for j in range(len(nt))
        ),
    )
    pairs: list[tuple[float, float, float, float]] = []
    used_source: set[int] = set()
    used_target: set[int] = set()
    for _, i, j in combos:
        if i in used_source or j in used_target:
            continue
        used_source.add(i)
        used_target.add(j)
        pairs.append((source[i]["x"], source[i]["y"], target[j]["x"], target[j]["y"]))
    return pairs


def residuals(affine: Affine, pairs: list[tuple[float, float, float, float]]) -> list[float]:
    out = []
    for sx, sy, tx, ty in pairs:
        x, y = apply(affine, sx, sy)
        out.append(hypot(x - tx, y - ty))
    return out


def alignment_to_reference(studio: dict, reference: dict) -> tuple[Affine, dict]:
    """대상층 local_m -> 기준층(건물) local_m 아핀과 진단 정보를 만든다."""
    if studio["floor"]["id"] == reference["floor"]["id"]:
        return IDENTITY, {"anchors": 0, "mean": 0.0, "max": 0.0, "identity": True}

    # source=대상층, target=기준층 방향으로 맞춰야 대상층 좌표를 건물 프레임으로 옮긴다.
    pairs = match_anchors(anchor_points(studio), anchor_points(reference))
    if len(pairs) < MIN_ANCHORS:
        raise ValueError(
            f"{studio['floor']['name']}: 정규화 앵커({ANCHOR_TYPE})가 {len(pairs)}개뿐입니다."
        )
    affine = fit_affine(pairs)
    res = residuals(affine, pairs)
    return affine, {
        "anchors": len(pairs),
        "mean": sum(res) / len(res),
        "max": max(res),
        "identity": False,
    }
