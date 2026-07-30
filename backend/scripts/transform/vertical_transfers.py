"""층을 잇는 수직 전이(transfer) 간선을 만든다.

Edge 모델은 이미 이걸 전제한다(app/models/navigation.py):
  - floor_id가 nullable — 전이 간선은 특정 층에 속하지 않는다.
  - transfer_mode 컬럼 — elevator/escalator 구분.
  - bidirectional — 에스컬레이터는 단방향, 엘리베이터는 양방향.
이 전이 간선은 건물 전체 그래프 응답(building_queries.get_building_graph)에 실려,
클라이언트가 온디바이스 경로 탐색에서 층 간 이동에 사용한다.

수단별 모델 (설계 근거는 아래 비용 상수 주석):
  - 에스컬레이터: 한 층씩만 오르내리고 상/하행이 분리돼 있다. 원본 노드의
    trans_code(OB-ESCALATOR_UP/DOWN)로 방향을 읽어 **단방향** 간선을 만든다.
    상행 전용을 하행으로 타는 불가능 경로를 여기서 제거한다. 인접 층끼리만 잇는다.
  - 엘리베이터: 한 번 타면 여러 층을 직행한다. 같은 샤프트(층이 달라도 같은 자리)를
    묶어 **그 샤프트가 서비스하는 모든 층쌍**을 양방향으로 잇는다. 비용은 층수에
    비례하되 고정 탑승비를 얹어, 여러 층 이동일수록 에스컬레이터보다 싸지게 한다.

매칭 방식:
  예전 link_vertical_transfers는 엘리베이터 이름(EV1, EV2…)으로 그룹핑했지만,
  Studio에서 새로 만든 층은 이름이 전부 "엘리베이터"라 이름으로는 구분되지 않는다.
  대신 모든 층을 건물 공통 프레임으로 정규화한 뒤(floor_alignment) **위치 근접**으로
  맞춘다. 엘리베이터/에스컬레이터는 층이 달라도 같은 자리에 있기 때문이다.

  단 **에스컬레이터는 위치 근접이 원리적으로 틀린다.** 탑승구와 하차구는 같은
  자리가 아니라 경사로의 양 끝이라, 층을 겹쳐 보면 공통 프레임에서 20m쯤 떨어져
  있다(실측: ES1 19.6m, ES2 20.2m, ES2-1 19.9m). MATCH_RADIUS_M(8m) 안에서
  최근접을 고르면 같은 기기의 반대쪽 끝이 아니라 옆 기기의 같은 쪽 끝
  (탑승구↔탑승구, 하차구↔하차구)이 잡히고, 정작 필요한 탑승구는 짝을 못 찾아
  간선이 아예 안 생긴다. 그래서 에스컬레이터는 **원본(다베오) 층간 간선을
  1차 근거**로 쓰고, 방향(from/to)만 trans_code로 정한다. 위치 근접은 원본
  간선이 없는 노드의 폴백으로만 남긴다.
"""

from __future__ import annotations

import re
from math import hypot

# 수직 이동 수단으로 볼 노드 타입
TRANSFER_TYPES = ("elevator", "escalator")
# 같은 수직 통로로 볼 최대 수평 거리(m). 정규화 잔차(~1-3m)를 감안한 값.
MATCH_RADIUS_M = 8.0

# 층고 추정치(m). 전이 간선의 **실제 이동 거리**(length_m)를 구할 때만 쓴다.
# 원천 데이터에 층별 높이가 없어 백화점 기준 통상값을 상수로 둔다 — 정확한 실측이
# 생기면 층 데이터에서 읽도록 바꾼다. 라우팅 결과에는 영향이 없다(그쪽은 cost_m).
FLOOR_HEIGHT_M = 4.5

# --- 라우팅 비용(=Dijkstra 가중치, m) -----------------------------------------
# 실제 높이가 아니라 "어떤 수단으로 몇 층을 이동할지"를 라우팅이 고르게 만드는 값이다.
# 클라이언트 Dijkstra는 이 비용 합만 보므로, 수단 선호는 전적으로 이 가중치로 인코딩된다.
# 실제 이동 거리는 별도로 length_m에 싣는다(사용자에게 보이는 거리는 그쪽을 쓴다).
#
# 에스컬레이터는 한 층 세그먼트마다 이 비용을 문다(n층 이동 = ESCALATOR_HOP_M × n).
ESCALATOR_HOP_M = 20.0
# 엘리베이터는 고정 탑승비 + 층당 비용. n층 이동 = BOARD + PER_FLOOR × n.
# 두 모델의 교차점:
#   n=1: 에스컬 20  vs 엘리베 40  → 에스컬레이터
#   n=2: 에스컬 40  vs 엘리베 45  → 에스컬레이터
#   n=3: 에스컬 60  vs 엘리베 50  → 엘리베이터
# 즉 1~2층은 에스컬레이터, 3층 이상은 엘리베이터가 최단이 된다(가까운 기기 우선은
# 기기까지의 보행 거리가 그래프에 이미 있어 자동 반영된다). 값을 바꾸면 교차점이 바뀐다.
ELEVATOR_BOARD_M = 35.0
ELEVATOR_PER_FLOOR_M = 5.0


def _by_type(nodes: list[dict], node_type: str) -> list[dict]:
    return [n for n in nodes if n.get("type") == node_type]


def _local(node: dict) -> dict:
    return node["position"]["local_m"]


def _distance(a: dict, b: dict) -> float:
    pa, pb = _local(a), _local(b)
    return hypot(pb["x"] - pa["x"], pb["y"] - pa["y"])


# 에스컬레이터 노드의 진행 방향("up"/"down")을 원본 메타에서 읽는다. 못 읽으면 None.
# trans_code(OB-ESCALATOR_UP/DOWN)가 1차 근거, 이름(ES1-UP/ES1-DN…)이 폴백이다.
def _escalator_direction(node: dict) -> str | None:
    trans_code = ((node.get("source") or {}).get("trans_code") or "").upper()
    if trans_code.endswith("_UP"):
        return "up"
    if trans_code.endswith("_DOWN"):
        return "down"
    name = (node.get("name") or "").upper()
    if "-UP" in name:
        return "up"
    if "-DN" in name or "-DOWN" in name:
        return "down"
    return None


# 에스컬레이터 이름 규칙: "<그룹>-<UP|DN>(<TO|FR><층>)".
#   B1 "ES2-1-DN(TOB2)"  = B1에서 B2로 내려가는 **탑승구**
#   B2 "ES2-1-DN(FRB1)"  = 그 기기가 B2에 내려놓는 **하차구**
# 원본 간선 검증용으로만 쓴다(간선 생성의 근거는 원본 토폴로지 + trans_code).
_ESCALATOR_NAME = re.compile(
    r"^(?P<group>ES[0-9\-]*?)-(?P<dir>UP|DN|DOWN)\((?P<role>TO|FR)(?P<floor>[A-Z0-9]+)\)$"
)


def _parse_escalator_name(node: dict) -> dict | None:
    match = _ESCALATOR_NAME.match((node.get("name") or "").strip().upper())
    if match is None:
        return None
    group = match.group("group")
    direction = "up" if match.group("dir") == "UP" else "down"
    return {"group": group, "direction": direction, "role": match.group("role")}


# 원본 간선이 이름 규칙(같은 그룹·같은 방향, 탑승구 TO → 하차구 FR)과 어긋나는지.
# 어긋나도 간선은 만든다 — 토폴로지가 1차 근거이고 이름은 오탈자가 있을 수 있다
# (예: "ES3-DN(TOB2F)"처럼 층 표기가 흔들린다). 대신 개수를 보고할 수 있게 남긴다.
def _escalator_name_mismatch(from_node: dict, to_node: dict) -> str | None:
    a, b = _parse_escalator_name(from_node), _parse_escalator_name(to_node)
    if a is None or b is None:
        return "이름 규칙으로 해석 불가"
    if a["group"] != b["group"]:
        return f"그룹 불일치({a['group']} vs {b['group']})"
    if a["direction"] != b["direction"]:
        return f"방향 불일치({a['direction']} vs {b['direction']})"
    if (a["role"], b["role"]) != ("TO", "FR"):
        return f"탑승/하차 역할 불일치({a['role']} -> {b['role']})"
    return None


# 원본(다베오) 층간 간선으로 에스컬레이터 전이를 만든다.
#
# source_edges: [{"from","to","passable"?}] — 노드 id는 이미 층 스코프가 붙은 값.
# 같은 간선이 양쪽 층 파일에 한 번씩 들어 있어 중복으로 들어오므로 무순서 쌍으로 묶는다.
# from/to는 진행 방향에 맞춘다: 상행은 아래 층이 탑승구, 하행은 위 층이 탑승구다.
# 반환: 간선이 만들어진(=폴백이 필요 없는) 노드 id 집합.
def _escalator_transfers_from_source(
    ordered: list[dict],
    source_edges: list[dict],
    transfers: list[dict],
    unresolved: list[dict],
) -> set[str]:
    rank = {floor["name"]: index for index, floor in enumerate(ordered)}
    owner: dict[str, tuple[dict, dict]] = {}
    for floor in ordered:
        for node in _by_type(floor["nodes"], "escalator"):
            owner[node["id"]] = (floor, node)

    # 무순서 쌍 → 원본이 준 passable 플래그들.
    grouped: dict[tuple[str, str], list[bool]] = {}
    for edge in source_edges:
        key = tuple(sorted((edge["from"], edge["to"])))
        if key[0] not in owner or key[1] not in owner:
            continue  # 엘리베이터·junction 등은 각자의 규칙으로 처리한다.
        grouped.setdefault(key, []).append(bool(edge.get("passable", True)))

    covered: set[str] = set()
    for (left_id, right_id), passables in grouped.items():
        left_floor, left = owner[left_id]
        right_floor, right = owner[right_id]
        note = {"mode": "escalator", "floor": left_floor["name"], "node_id": left_id}

        # 층 파일마다 passable이 엇갈리는 쌍이 있다(원본 노이즈). 한쪽이라도
        # 통행 가능이면 살린다 — 실재하는 기기를 통째로 지우는 쪽이 더 위험하다.
        if not any(passables):
            unresolved.append({**note, "reason": "원본 간선이 통행 불가로 표시됨"})
            continue
        direction = _escalator_direction(left)
        if direction is None or direction != _escalator_direction(right):
            unresolved.append({**note, "reason": "원본 간선 양끝의 진행 방향이 다름"})
            continue
        if left_floor["name"] == right_floor["name"]:
            unresolved.append({**note, "reason": "원본 간선이 같은 층을 잇는다"})
            continue
        if abs(rank[left_floor["name"]] - rank[right_floor["name"]]) != 1:
            unresolved.append({**note, "reason": "원본 간선이 인접하지 않은 층을 잇는다"})
            continue

        lower, upper = (
            (left, right)
            if rank[left_floor["name"]] < rank[right_floor["name"]]
            else (right, left)
        )
        from_node, to_node = (lower, upper) if direction == "up" else (upper, lower)
        mismatch = _escalator_name_mismatch(from_node, to_node)
        if mismatch is not None:
            unresolved.append({**note, "reason": f"이름 규칙 불일치: {mismatch}"})
        transfers.append(_edge(
            from_node=from_node,
            to_node=to_node,
            mode="escalator",
            # 기존 근접 매칭과 같은 규칙: [아래층, 위층] 순서.
            floors=sorted(
                (left_floor["name"], right_floor["name"]),
                key=lambda name: rank[name],
            ),
            # main과 같은 규칙: 표시 거리는 수평+층고의 3D 거리, 비용은 탑승 부담.
            length_m=hypot(_distance(from_node, to_node), FLOOR_HEIGHT_M),
            cost_m=ESCALATOR_HOP_M,
            bidirectional=False,
            distance=_distance(from_node, to_node),
        ))
        covered.add(left_id)
        covered.add(right_id)
    return covered


# a쪽 노드들을 b쪽 노드에 최근접 1:1로 짝짓는다. 반경 밖이면 unresolved에 남긴다.
# 반환: [(a_node, b_node, distance)] — 짝지어진 것만.
def _match_by_position(
    a_nodes: list[dict],
    b_nodes: list[dict],
    *,
    a_floor: dict,
    b_floor: dict,
    mode: str,
    unresolved: list[dict],
) -> list[tuple[dict, dict, float]]:
    used: set[str] = set()
    pairs: list[tuple[dict, dict, float]] = []
    for a in a_nodes:
        candidates = [(_distance(a, b), b) for b in b_nodes if b["id"] not in used]
        near = [c for c in candidates if c[0] <= MATCH_RADIUS_M]
        if not near:
            unresolved.append(
                {
                    "node_id": a["id"],
                    "floor": a_floor["name"],
                    "mode": mode,
                    "reason": f"{b_floor['name']}에 {MATCH_RADIUS_M}m 이내 대응 없음",
                }
            )
            continue
        distance, b = min(near, key=lambda c: c[0])
        used.add(b["id"])
        pairs.append((a, b, distance))
    return pairs


def _edge(
    *,
    from_node: dict,
    to_node: dict,
    mode: str,
    floors: list[str],
    length_m: float,
    cost_m: float,
    bidirectional: bool,
    distance: float,
) -> dict:
    prefix = mode[:2]
    return {
        "id": f"xfer:{prefix}:{from_node['id']}__{to_node['id']}",
        "from": from_node["id"],
        "to": to_node["id"],
        "mode": mode,
        "floors": floors,
        # length_m은 실제 이동 거리(표시용), cost_m은 라우팅 가중치다. 둘을 겸하면
        # 튜닝 비용이 사용자에게 보이는 총 거리에 그대로 새어 들어간다.
        "length_m": round(length_m, 3),
        "cost_m": cost_m,
        "bidirectional": bidirectional,
        "horizontal_offset_m": round(distance, 3),
    }


# 인접한 두 층 사이의 에스컬레이터 단방향 전이 간선. lower/upper는 level 오름차순.
# 방향별로 나눠 매칭한다 — 상행 노드는 상행끼리, 하행 노드는 하행끼리 이어야
# 물리적으로 존재하는 세그먼트만 남고 반대 방향 통행이 끼지 않는다.
#
# **원본 간선이 없는 노드에만 쓰는 폴백이다**(skip_node_ids로 제외). 모듈 docstring의
# 이유대로 탑승/하차구는 같은 자리가 아니라서, 이 매칭은 짝을 틀리게 잡을 수 있다.
def _escalator_transfers(
    lower: dict,
    upper: dict,
    transfers: list[dict],
    unresolved: list[dict],
    skip_node_ids: set[str] | None = None,
) -> None:
    skip = skip_node_ids or set()
    lower_esc = [n for n in _by_type(lower["nodes"], "escalator") if n["id"] not in skip]
    upper_esc = [n for n in _by_type(upper["nodes"], "escalator") if n["id"] not in skip]
    floors = [lower["name"], upper["name"]]

    for direction in ("up", "down"):
        lower_dir = [n for n in lower_esc if _escalator_direction(n) == direction]
        upper_dir = [n for n in upper_esc if _escalator_direction(n) == direction]
        # 상행은 아래→위, 하행은 위→아래. 어느 쪽을 기준으로 매칭하든 짝은 같지만,
        # 간선의 from/to는 진행 방향에 맞춘다(bidirectional=False라 방향이 곧 통행 가능 방향).
        pairs = _match_by_position(
            lower_dir if direction == "up" else upper_dir,
            upper_dir if direction == "up" else lower_dir,
            a_floor=lower if direction == "up" else upper,
            b_floor=upper if direction == "up" else lower,
            mode="escalator",
            unresolved=unresolved,
        )
        for a, b, distance in pairs:
            transfers.append(
                _edge(
                    from_node=a,
                    to_node=b,
                    mode="escalator",
                    floors=floors,
                    # 실제 이동 거리는 경사면 길이 — 수평 주행거리와 층고의 빗변이다.
                    length_m=hypot(distance, FLOOR_HEIGHT_M),
                    cost_m=ESCALATOR_HOP_M,
                    bidirectional=False,
                    distance=distance,
                )
            )


# 엘리베이터 노드를 층을 가로질러 같은 자리(샤프트)끼리 묶는다.
# 반환: [[(floor, node), ...]] — 각 리스트가 한 샤프트, level 오름차순.
def _elevator_shafts(ordered: list[dict]) -> list[list[tuple[dict, dict]]]:
    shafts: list[list[tuple[dict, dict]]] = []
    for floor in ordered:
        for node in _by_type(floor["nodes"], "elevator"):
            # 이미 있는 샤프트 중 대표 노드가 반경 안이고, 그 층이 아직 안 들어간 것을 찾는다.
            placed = False
            for shaft in shafts:
                rep_node = shaft[0][1]
                if _distance(node, rep_node) <= MATCH_RADIUS_M and all(f["name"] != floor["name"] for f, _n in shaft):
                    shaft.append((floor, node))
                    placed = True
                    break
            if not placed:
                shafts.append([(floor, node)])
    return shafts


# 엘리베이터 전이 간선. 각 샤프트가 서비스하는 모든 층쌍을 양방향으로 잇는다.
# 비용은 두 층 사이의 홉 수(=정렬상 층 간격)에 비례한다. level 차가 아니라 홉 수를
# 쓰는 이유: 지상/지하 사이에 level 0이 없어(1F=1, B1=-1) level 차가 실제 층수를
# 한 칸 부풀리기 때문이다.
def _elevator_transfers(
    ordered: list[dict],
    transfers: list[dict],
    unresolved: list[dict],
) -> None:
    rank = {floor["name"]: index for index, floor in enumerate(ordered)}

    for shaft in _elevator_shafts(ordered):
        if len(shaft) < 2:
            floor, node = shaft[0]
            unresolved.append(
                {
                    "node_id": node["id"],
                    "floor": floor["name"],
                    "mode": "elevator",
                    "reason": "다른 층에 같은 샤프트 대응 없음",
                }
            )
            continue
        for i in range(len(shaft)):
            for j in range(i + 1, len(shaft)):
                lower_floor, lower_node = shaft[i]
                upper_floor, upper_node = shaft[j]
                hops = abs(rank[upper_floor["name"]] - rank[lower_floor["name"]])
                horizontal = _distance(lower_node, upper_node)
                transfers.append(
                    _edge(
                        from_node=lower_node,
                        to_node=upper_node,
                        mode="elevator",
                        floors=[lower_floor["name"], upper_floor["name"]],
                        # 실제 이동 거리는 샤프트를 오르내린 높이다(같은 샤프트라 수평 이동은 정렬 잔차 수준).
                        length_m=hypot(horizontal, FLOOR_HEIGHT_M * hops),
                        cost_m=ELEVATOR_BOARD_M + ELEVATOR_PER_FLOOR_M * hops,
                        bidirectional=True,
                        distance=horizontal,
                    )
                )


# 층 간 수직 전이 간선을 만든다.
# floors: [{"code","floor_id","name","level","nodes"}] — nodes는 건물 공통 프레임으로
# 정규화된 뒤여야 한다. level은 위층일수록 크다(6F=6 … 1F=1 … B6=-6).
# source_edges: 원본(다베오) 층간 간선. 노드 id는 floors의 노드 id와 같은 스코프여야
#   한다. 에스컬레이터 짝을 여기서 읽는다. 없으면 전부 위치 근접 폴백으로 떨어진다.
# 반환: (전이 간선 목록, 짝을 못 찾은 노드 목록)
def build_transfers(
    floors: list[dict],
    source_edges: list[dict] | None = None,
) -> tuple[list[dict], list[dict]]:
    ordered = sorted(floors, key=lambda f: f["level"])
    transfers: list[dict] = []
    unresolved: list[dict] = []

    # 에스컬레이터: 원본 간선이 1차 근거, 남은 노드만 위치 근접 폴백.
    covered = (
        _escalator_transfers_from_source(ordered, source_edges, transfers, unresolved)
        if source_edges
        else set()
    )
    for lower, upper in zip(ordered, ordered[1:]):
        _escalator_transfers(
            lower, upper, transfers, unresolved, skip_node_ids=covered
        )

    # 엘리베이터: 샤프트 단위로 서비스 층 전체를 직행 연결.
    _elevator_transfers(ordered, transfers, unresolved)

    return transfers, unresolved
