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
"""

from __future__ import annotations

from math import hypot

# 수직 이동 수단으로 볼 노드 타입
TRANSFER_TYPES = ("elevator", "escalator")
# 같은 수직 통로로 볼 최대 수평 거리(m). 정규화 잔차(~1-3m)를 감안한 값.
MATCH_RADIUS_M = 8.0

# --- 비용(=Dijkstra 가중치, m) ------------------------------------------------
# 실제 높이가 아니라 "어떤 수단으로 몇 층을 이동할지"를 라우팅이 고르게 만드는 값이다.
# 클라이언트 Dijkstra는 순수 거리 합만 보므로, 수단 선호는 전적으로 이 가중치로 인코딩된다.
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
        "length_m": length_m,
        "bidirectional": bidirectional,
        "horizontal_offset_m": round(distance, 3),
    }


# 인접한 두 층 사이의 에스컬레이터 단방향 전이 간선. lower/upper는 level 오름차순.
# 방향별로 나눠 매칭한다 — 상행 노드는 상행끼리, 하행 노드는 하행끼리 이어야
# 물리적으로 존재하는 세그먼트만 남고 반대 방향 통행이 끼지 않는다.
def _escalator_transfers(
    lower: dict,
    upper: dict,
    transfers: list[dict],
    unresolved: list[dict],
) -> None:
    lower_esc = _by_type(lower["nodes"], "escalator")
    upper_esc = _by_type(upper["nodes"], "escalator")
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
                    length_m=ESCALATOR_HOP_M,
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
                length_m = ELEVATOR_BOARD_M + ELEVATOR_PER_FLOOR_M * hops
                transfers.append(
                    _edge(
                        from_node=lower_node,
                        to_node=upper_node,
                        mode="elevator",
                        floors=[lower_floor["name"], upper_floor["name"]],
                        length_m=length_m,
                        bidirectional=True,
                        distance=_distance(lower_node, upper_node),
                    )
                )


# 층 간 수직 전이 간선을 만든다.
# floors: [{"code","floor_id","name","level","nodes"}] — nodes는 건물 공통 프레임으로
# 정규화된 뒤여야 한다. level은 위층일수록 크다(6F=6 … 1F=1 … B6=-6).
# 반환: (전이 간선 목록, 짝을 못 찾은 노드 목록)
def build_transfers(floors: list[dict]) -> tuple[list[dict], list[dict]]:
    ordered = sorted(floors, key=lambda f: f["level"])
    transfers: list[dict] = []
    unresolved: list[dict] = []

    # 에스컬레이터: 인접 층끼리만, 방향을 지켜 단방향으로.
    for lower, upper in zip(ordered, ordered[1:]):
        _escalator_transfers(lower, upper, transfers, unresolved)

    # 엘리베이터: 샤프트 단위로 서비스 층 전체를 직행 연결.
    _elevator_transfers(ordered, transfers, unresolved)

    return transfers, unresolved
