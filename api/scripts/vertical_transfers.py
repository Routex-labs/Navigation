"""층을 잇는 수직 전이(transfer) 간선을 만든다.

Edge 모델은 이미 이걸 전제한다(app/models/navigation.py):
  - floor_id가 nullable — 전이 간선은 특정 층에 속하지 않는다.
  - transfer_mode 컬럼 — elevator/escalator 구분.
라우팅도 준비돼 있다(NavigationService.get_building_shortest_path).

매칭 방식:
  예전 link_vertical_transfers는 엘리베이터 **이름**(EV1, EV2…)으로 그룹핑했지만,
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
# 층 간 이동 비용(m). 실제 높이가 아니라 라우팅에서 층 이동을 적당히 억제하는 값.
TRANSFER_LENGTH_M = 20.0


def _by_type(nodes: list[dict], node_type: str) -> list[dict]:
    return [n for n in nodes if n.get("type") == node_type]


def build_transfers(floors: list[dict]) -> tuple[list[dict], list[dict]]:
    """인접한 층끼리 같은 수직 통로를 이어 전이 간선을 만든다.

    floors: [{"code","floor_id","name","level","nodes"}] — nodes는 **건물 공통 프레임**
    으로 정규화된 뒤여야 한다.

    인접 판단은 level 정렬로 한다. 이 데이터의 level은 위층일수록 작다(1F=5, 2F=4 …)
    는 점에 주의. 어느 쪽이 위인지는 전이 간선이 양방향이라 결과에 영향이 없고,
    "정렬상 이웃한 두 층"만 이으면 된다.

    반환: (전이 간선 목록, 짝을 못 찾은 노드 목록)
    """
    ordered = sorted(floors, key=lambda f: f["level"])
    transfers: list[dict] = []
    unresolved: list[dict] = []

    for near_floor, next_floor in zip(ordered, ordered[1:]):
        for mode in TRANSFER_TYPES:
            a_nodes = _by_type(near_floor["nodes"], mode)
            b_nodes = _by_type(next_floor["nodes"], mode)
            used: set[str] = set()
            for a in a_nodes:
                ap = a["position"]["local_m"]
                candidates = [
                    (hypot(b["position"]["local_m"]["x"] - ap["x"],
                           b["position"]["local_m"]["y"] - ap["y"]), b)
                    for b in b_nodes
                    if b["id"] not in used
                ]
                near = [c for c in candidates if c[0] <= MATCH_RADIUS_M]
                if not near:
                    unresolved.append({
                        "node_id": a["id"],
                        "floor": near_floor["name"],
                        "mode": mode,
                        "reason": f"{next_floor['name']}에 {MATCH_RADIUS_M}m 이내 대응 없음",
                    })
                    continue
                distance, b = min(near, key=lambda c: c[0])
                used.add(b["id"])
                transfers.append({
                    "id": f"xfer:{mode[:2]}:{a['id']}__{b['id']}",
                    "from": a["id"],
                    "to": b["id"],
                    "mode": mode,
                    "floors": [near_floor["name"], next_floor["name"]],
                    "length_m": TRANSFER_LENGTH_M,
                    "bidirectional": True,
                    "horizontal_offset_m": round(distance, 3),
                })
    return transfers, unresolved
