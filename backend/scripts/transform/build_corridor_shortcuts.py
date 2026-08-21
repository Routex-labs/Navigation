"""복도 그래프의 ㄱ·ㄴ 우회를 줄이는 지름길 간선을 골라 클라이언트 상수로 낸다.

## 왜 필요한가

다베오 원본 그래프는 직각 격자다(1F 간선의 67%가 축에서 5도 이내). 그래서 넓게
뚫린 자리에서도 경로가 ㄱ·ㄴ자로 돌아간다. 우회비(그래프거리/직선거리)의
**중앙값 1.26~1.32는 직각 격자의 이론값(약 1.27) 그대로이고, 이건 건물 그 자체다.**
사람도 벽은 통과하지 못하므로 중앙값은 고치지 않는다. 고치는 것은 **꼬리**다
(1F p99 2.06, B1 2.59, 2F 2.66).

## 절대 풀면 안 되는 규칙: 새 노드 0개

지름길은 **이미 있는 노드끼리만** 잇는다. PDR 무해성의 근거가 통째로 여기 걸려 있다
(corridor_tracker_config.dart의 상수는 전부 *개수*에 걸려 있다).

    transitionPenaltyDegM=3      노드를 넘는 *횟수* 비용  -> 노드가 안 늘어 영향 0
    maxTransitionsPerSegment=3   곧은 구간을 안 쪼갠다    -> 영향 0
    junctionZoneRadiusM=3.5      최단 추가분이 5.1m       -> 영향 0
    junctionZoneEdgeLengthRatio=0.4

**"조금만 더 넣자"는 말이 나오면 이 숫자로 돌아와라.** 규칙 3(비율)과 5(차수 예산)를
풀고 무장애 지름길을 전부 넣으면 1F 기준:

    +180개 간선(+75%)   중앙값 1.257 -> 1.175 (**6.5%뿐**)   최대 차수 **5 -> 12**

CorridorPositionTracker._advance는 노드를 넘을 때 recoveryOptionsFromNode의 모든
갈래로 분기한다. 차수 12면 한 노드에서 12갈래가 열리고 **beamWidth=24는 두 노드만에
소진된다.** 중앙값 6.5%를 사기에는 너무 비싸다. 이 숫자가 이 규칙의 유일한 방어다.

## 채택 규칙

    1. 아직 간선이 없는 두 노드
    2. 2m <= 직선거리 <= 20m
    3. 현재 그래프거리 / 직선거리 >= 2.0        <- 꼬리만 친다
    4. 최소 여유폭 >= (그 층 기존 간선 여유폭 p25) x 1.2
    5. 노드당 추가 차수 +1 이하 (절약 미터수 내림차순 그리디)

4의 눈금은 다베오 자신의 간선에서 뽑는다. "벽을 안 뚫는다"를 증명할 방법은 없지만,
**기존 간선보다 20% 넉넉한 자리만 고른다**는 상대 기준은 층마다 자동 보정된다.
기존 간선의 여유폭 중앙값은 1.1~1.4m다.

## 두 묶음으로 나누는 이유

새 간선이 양 끝 기존 간선 모두와 60도 넘게 벌어지면 **두 복도를 잇는 수직 링크**다.
CorridorNetwork.isForwardReachable이 "가까운 간선"이 아니라 **연결된 간선**만 보는
것이 평행 복도 혼동을 막는 지금의 유일한 방어인데, 이 링크는 정확히 그 둘을 잇는다.
하나라도 가짜면 마커가 옆 복도로 건너뛴다 - 지금 없는 종류의 버그다. 여유폭이 넓다는
것은 좋은 신호지 증거가 아니다(넓은 벽면 앞 공간도 그만큼 넓다).
그래서 수직 링크는 검수 대기로 빼고 **기본은 꺼짐**이다.

## B2를 통째로 건너뛰는 이유

B2만 non_walkable 폴리곤이 0개다(나머지 11개 층은 4~219개). 규칙 4의 눈금이 설
바닥이 없다. 채택 후보도 1개뿐이고 그마저 수직 링크이며, 우회비 중앙값·p90·p99를
**하나도 움직이지 않는다.** 근거가 약한 자리에서 이득이 0이면 안 하는 편이 낫다.

실행: python backend/scripts/transform/build_corridor_shortcuts.py
"""

from __future__ import annotations

import collections
import heapq
import json
import math
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
STUDIO = REPO / "backend/resources/studio/thehyundai-seoul-dabeeo"
OUT = REPO / "client/lib/domain/route/corridor_shortcuts_data.dart"

BUILDING_ID = "thehyundai-seoul"
FLOOR_CODES = ["1f", "2f", "3f", "4f", "5f", "6f", "b1", "b2", "b3", "b4", "b5", "b6"]

MIN_LENGTH_M = 2.0
MAX_LENGTH_M = 20.0
MIN_DETOUR_RATIO = 2.0
CLEARANCE_MARGIN = 1.2  # 기존 간선 p25 대비
MAX_EXTRA_DEGREE = 1
PERPENDICULAR_DEG = 60.0  # 이보다 크게 벌어지면 수직 링크로 본다
SAMPLE_STEP_M = 0.4
END_SKIP_M = 0.6  # 노드는 폴리곤 경계에 붙어 있으므로 양 끝은 재지 않는다


def _in_polygon(point, polygon) -> bool:
    x, y = point
    inside = False
    for index in range(len(polygon)):
        a = polygon[index]
        b = polygon[(index + 1) % len(polygon)]
        if (a[1] > y) != (b[1] > y):
            if x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1] + 1e-15) + a[0]:
                inside = not inside
    return inside


def _distance_to_segment(point, a, b) -> float:
    vx, vy = b[0] - a[0], b[1] - a[1]
    squared = vx * vx + vy * vy
    if squared == 0:
        return math.hypot(point[0] - a[0], point[1] - a[1])
    t = max(0.0, min(1.0, ((point[0] - a[0]) * vx + (point[1] - a[1]) * vy) / squared))
    return math.hypot(point[0] - (a[0] + t * vx), point[1] - (a[1] + t * vy))


def _clearance(point, obstacles, footprint) -> float:
    if not _in_polygon(point, footprint):
        return -1.0
    best = min(
        _distance_to_segment(point, footprint[i], footprint[(i + 1) % len(footprint)]) for i in range(len(footprint))
    )
    for polygon in obstacles:
        if _in_polygon(point, polygon):
            return -1.0
        for i in range(len(polygon)):
            best = min(best, _distance_to_segment(point, polygon[i], polygon[(i + 1) % len(polygon)]))
            if best < 0:
                return best
    return best


def min_clearance(a, b, obstacles, footprint) -> float:
    """a-b 직선 위에서 가장 좁은 자리의 여유폭(m). 폴리곤 안이거나 층 밖이면 음수."""
    length = math.dist(a, b)
    if length < 1e-9:
        return -1.0
    steps = max(2, int(length / SAMPLE_STEP_M))
    low, high = END_SKIP_M / length, 1 - END_SKIP_M / length
    values = [
        _clearance(
            (a[0] + (b[0] - a[0]) * i / steps, a[1] + (b[1] - a[1]) * i / steps),
            obstacles,
            footprint,
        )
        for i in range(steps + 1)
        if low <= i / steps <= high
    ]
    return min(values) if values else 99.0


def _bearing(a, b) -> float:
    return math.degrees(math.atan2(b[1] - a[1], b[0] - a[0])) % 180


def _angle_between(left: float, right: float) -> float:
    delta = abs(left - right) % 180
    return min(delta, 180 - delta)


def _all_pairs(positions, adjacency):
    result = {}
    for source in positions:
        distance = {source: 0.0}
        queue = [(0.0, source)]
        while queue:
            cost, node = heapq.heappop(queue)
            if cost > distance.get(node, math.inf):
                continue
            for neighbour, weight in adjacency[node]:
                candidate = cost + weight
                if candidate < distance.get(neighbour, math.inf):
                    distance[neighbour] = candidate
                    heapq.heappush(queue, (candidate, neighbour))
        result[source] = distance
    return result


def select(floor: dict) -> tuple[list[dict], list[dict], float]:
    """(채택, 검수대기, 여유폭 기준)."""
    positions = {
        node["id"]: (node["position"]["local_m"]["x"], node["position"]["local_m"]["y"]) for node in floor["nodes"]
    }
    adjacency = collections.defaultdict(list)
    incident = collections.defaultdict(list)
    existing = set()
    for edge in floor["edges"]:
        adjacency[edge["from"]].append((edge["to"], edge["length_m"]))
        adjacency[edge["to"]].append((edge["from"], edge["length_m"]))
        incident[edge["from"]].append(edge["to"])
        incident[edge["to"]].append(edge["from"])
        existing.add(frozenset((edge["from"], edge["to"])))

    footprint = [(p["x"], p["y"]) for p in floor["building_footprint_local_m"]]
    obstacles = [[(p["x"], p["y"]) for p in s] for s in floor["store_polygons_local_m"]]
    obstacles += [[(p["x"], p["y"]) for p in s["polygon_local_m"]] for s in floor["non_walkable_polygons_local_m"]]

    measured = sorted(
        min_clearance(positions[e["from"]], positions[e["to"]], obstacles, footprint) for e in floor["edges"]
    )
    threshold = max(0.8, measured[len(measured) // 4]) * CLEARANCE_MARGIN

    distances = _all_pairs(positions, adjacency)
    ids = list(positions)
    candidates = []
    for index, left in enumerate(ids):
        for right in ids[index + 1 :]:
            if frozenset((left, right)) in existing:
                continue
            straight = math.dist(positions[left], positions[right])
            if not MIN_LENGTH_M <= straight <= MAX_LENGTH_M:
                continue
            walked = distances[left].get(right, math.inf)
            # 아예 안 이어진 쌍은 지름길이 아니라 **연결 결함**이다(B3에 2노드 섬이
            # 하나 있다). 우회비가 무한대라 규칙 3을 항상 통과해 버리므로 명시적으로
            # 뺀다. 없는 연결을 지어내는 것은 원본을 고칠 일이지 여기서 덮을 일이
            # 아니다 — 섬은 report_islands가 따로 신고한다.
            if not math.isfinite(walked):
                continue
            if walked / straight < MIN_DETOUR_RATIO:
                continue
            candidates.append((walked - straight, walked / straight, straight, left, right))
    candidates.sort(reverse=True)

    accepted: list[dict] = []
    review: list[dict] = []
    extra: collections.Counter = collections.Counter()
    for saved, ratio, straight, left, right in candidates:
        if extra[left] >= MAX_EXTRA_DEGREE or extra[right] >= MAX_EXTRA_DEGREE:
            continue
        clearance = min_clearance(positions[left], positions[right], obstacles, footprint)
        if clearance < threshold:
            continue
        extra[left] += 1
        extra[right] += 1
        bearing = _bearing(positions[left], positions[right])
        perpendicular = all(
            _angle_between(_bearing(positions[node], positions[other]), bearing) > PERPENDICULAR_DEG
            for node in (left, right)
            for other in incident[node]
        )
        record = {
            "from": left,
            "to": right,
            "lengthM": straight,
            "savedM": saved,
            "ratio": ratio,
            "clearanceM": clearance,
            "x1": positions[left][0],
            "y1": positions[left][1],
            "x2": positions[right][0],
            "y2": positions[right][1],
            "degrees": (len(incident[left]), len(incident[right])),
        }
        (review if perpendicular else accepted).append(record)
    return accepted, review, threshold


def report_islands(floor: dict) -> list[list[str]]:
    """그래프에서 떨어져 나온 노드 무리. 지름길로 덮지 않고 신고만 한다."""
    adjacency = collections.defaultdict(set)
    for edge in floor["edges"]:
        adjacency[edge["from"]].add(edge["to"])
        adjacency[edge["to"]].add(edge["from"])
    seen: set[str] = set()
    components: list[list[str]] = []
    for node in (n["id"] for n in floor["nodes"]):
        if node in seen:
            continue
        stack, group = [node], []
        while stack:
            current = stack.pop()
            if current in seen:
                continue
            seen.add(current)
            group.append(current)
            stack.extend(adjacency[current])
        components.append(group)
    components.sort(key=len, reverse=True)
    return components[1:]


def _dart_rows(rows: list[dict], floor_id: str) -> str:
    lines = []
    for row in rows:
        lines.append(
            f"      // {row['savedM']:.1f}m 절약(우회비 {row['ratio']:.2f}), "
            f"여유폭 {row['clearanceM']:.2f}m, 차수 {row['degrees'][0]}+{row['degrees'][1]}, "
            f"local_m ({row['x1']:.1f},{row['y1']:.1f})-({row['x2']:.1f},{row['y2']:.1f})\n"
            f"      CorridorShortcut(\n"
            f"        fromNodeId: '{floor_id}:{row['from']}',\n"
            f"        toNodeId: '{floor_id}:{row['to']}',\n"
            f"        lengthM: {row['lengthM']:.6f},\n"
            f"      ),"
        )
    return "\n".join(lines)


def main() -> None:
    enabled_blocks: list[str] = []
    review_blocks: list[str] = []
    notes: list[str] = []
    for code in FLOOR_CODES:
        floor = json.loads((STUDIO / f"{code}.json").read_text(encoding="utf-8"))
        name = floor["floor"]["name"]
        floor_id = floor["floor"]["id"]
        for island in report_islands(floor):
            positions = {n["id"]: n["position"]["local_m"] for n in floor["nodes"]}
            where = ", ".join(f"({positions[i]['x']:.1f},{positions[i]['y']:.1f})" for i in island[:4])
            notes.append(
                f"//   {name}: **끊긴 섬 {len(island)}개 노드** {where} - 원본 데이터 결함이다. 지름길로 덮지 않는다."
            )
        if not floor["non_walkable_polygons_local_m"]:
            notes.append(f"//   {name}: non_walkable 0개 - 여유폭 눈금이 설 바닥이 없어 건너뛴다.")
            continue
        accepted, review, threshold = select(floor)
        notes.append(
            f"//   {name}: 채택 {len(accepted)}개, 검수대기 {len(review)}개 "
            f"(여유폭 기준 {threshold:.2f}m, 기존 간선 {len(floor['edges'])}개)"
        )
        if accepted:
            enabled_blocks.append(f"    '{name}': [\n{_dart_rows(accepted, floor_id)}\n    ],")
        if review:
            review_blocks.append(f"    '{name}': [\n{_dart_rows(review, floor_id)}\n    ],")

    OUT.write_text(
        "// 생성된 파일이다. 손으로 고치지 마라.\n"
        "// 생성: backend/scripts/transform/build_corridor_shortcuts.py\n"
        "// 채택 규칙과 '새 노드 0개'를 풀면 안 되는 이유는 그 스크립트의 docstring에 있다.\n"
        "//\n"
        "// 층별 결과:\n" + "\n".join(notes) + "\n"
        "\nimport 'corridor_shortcuts.dart';\n"
        "\n/// 지금 적용하는 지름길. 복도를 따라가는 대각선 컷이라 위험이 낮다.\n"
        "const kCorridorShortcuts = CorridorShortcutTable(\n"
        f"  buildingId: '{BUILDING_ID}',\n"
        "  byFloorName: {\n" + "\n".join(enabled_blocks) + "\n"
        "  },\n"
        ");\n"
        "\n/// **켜져 있지 않다.** 양 끝 기존 간선 모두와 60도 넘게 벌어진 = 두 복도를\n"
        "/// 잇는 수직 링크다. CorridorNetwork.isForwardReachable이 연결된 간선만 보는\n"
        "/// 것이 평행 복도 혼동을 막는 지금의 유일한 방어인데 이 링크가 정확히 그 둘을\n"
        "/// 잇는다. 하나라도 가짜면 마커가 옆 복도로 건너뛴다 - 지금 없는 종류의 버그다.\n"
        "/// **도면에서 실제로 뚫린 통로인지 눈으로 확인한 것만** 위 [kCorridorShortcuts]로\n"
        "/// 옮긴다. 좌표는 각 항목 주석의 local_m에 있다.\n"
        "const kCorridorShortcutsNeedingReview = CorridorShortcutTable(\n"
        f"  buildingId: '{BUILDING_ID}',\n"
        "  byFloorName: {\n" + "\n".join(review_blocks) + "\n"
        "  },\n"
        ");\n",
        encoding="utf-8",
    )
    print("\n".join(note[2:] for note in notes))
    print(f"\n-> {OUT.relative_to(REPO)}")


if __name__ == "__main__":
    main()
