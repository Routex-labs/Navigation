"""수직 전이 간선 생성(build_transfers) 단위 테스트.

DB 없이 층 dict를 직접 만들어 순수 함수를 검증한다. 실데이터 스모크는
tests/integration/test_real_data_smoke.py가, 서빙은 test_building_graph.py가 덮는다.

검증 기준:
    V1  에스컬레이터는 단방향이고 방향이 층 level과 일치한다(불가능 경로 제거).
    V2  1~2층은 에스컬레이터, 3층+는 엘리베이터가 더 싸다(층수 기반 수단 선택).
    V3  실제 이동 거리(length_m)와 라우팅 비용(cost_m)이 분리돼 있다 —
        비용이 표시 거리로 새어 나가면 사용자에게 보이는 총 거리가 부풀려진다.
    V4  에스컬레이터 짝은 원본 층간 간선으로 정한다 — 탑승구와 하차구는 20m쯤
        떨어져 있어 위치 근접으로는 같은 기기의 반대쪽 끝을 못 찾는다.
"""

from math import hypot

import pytest

from scripts.transform import vertical_transfers as vt


def _esc(node_id: str, x: float, y: float, direction: str, name: str | None = None) -> dict:
    # trans_code로 방향을 준다 — 실데이터(OB-ESCALATOR_UP/DOWN)와 같은 경로.
    code = "OB-ESCALATOR_UP" if direction == "up" else "OB-ESCALATOR_DOWN"
    return {
        "id": node_id,
        "type": "escalator",
        "name": name or node_id,
        "position": {"local_m": {"x": x, "y": y}},
        "source": {"trans_code": code},
    }


def _elev(node_id: str, x: float, y: float) -> dict:
    return {
        "id": node_id,
        "type": "elevator",
        "name": node_id,
        "position": {"local_m": {"x": x, "y": y}},
        "source": {"trans_code": "OB-ELEVATOR"},
    }


def _floor(name: str, level: int, nodes: list[dict]) -> dict:
    return {"code": name.lower(), "floor_id": f"F-{name}", "name": name, "level": level, "nodes": nodes}


# V1 — 상행 에스컬레이터는 아래→위 단방향 간선만, 하행은 위→아래 단방향만 만든다.
def test_에스컬레이터는_방향을_지켜_단방향으로_잇는다():
    # 1F/2F에 같은 자리(10,10 상행 / 20,20 하행)의 상·하행 노드를 둔다.
    floors = [
        _floor("1F", 1, [_esc("1F:up", 10, 10, "up"), _esc("1F:dn", 20, 20, "down")]),
        _floor("2F", 2, [_esc("2F:up", 10, 10, "up"), _esc("2F:dn", 20, 20, "down")]),
    ]
    transfers, _unresolved = vt.build_transfers(floors)
    esc = [t for t in transfers if t["mode"] == "escalator"]

    assert esc, "에스컬레이터 전이 간선이 있어야 한다"
    assert all(t["bidirectional"] is False for t in esc), "에스컬레이터는 단방향"

    up = next(t for t in esc if t["from"] == "1F:up")
    assert up["to"] == "2F:up"  # 상행: 아래층 → 위층
    down = next(t for t in esc if t["from"] == "2F:dn")
    assert down["to"] == "1F:dn"  # 하행: 위층 → 아래층

    # 상행 노드가 하행 노드와 섞여 이어지지 않는다(반대 방향 통행 불가).
    assert not [t for t in esc if {t["from"], t["to"]} == {"1F:up", "2F:dn"}]


# 상행 전용을 하행으로 타는 간선이 생기지 않는다 — 상행 노드만 있으면 하행 간선 0.
def test_상행_전용은_하행_간선을_만들지_않는다():
    floors = [
        _floor("1F", 1, [_esc("1F:up", 10, 10, "up")]),
        _floor("2F", 2, [_esc("2F:up", 10, 10, "up")]),
    ]
    transfers, _ = vt.build_transfers(floors)
    esc = [t for t in transfers if t["mode"] == "escalator"]

    assert len(esc) == 1
    assert esc[0]["from"] == "1F:up" and esc[0]["to"] == "2F:up"  # 상행뿐


# V3 — 실데이터 배치를 그대로 옮긴 케이스.
#
# B1 탑승구(TOB2)는 y=160, 그 기기의 B2 하차구(FRB1)는 y=141로 약 19m 떨어져 있고,
# B1 탑승구 근처(8m 안)에는 옆 기기의 B2 탑승구(TOB3)만 있다. 근접 매칭은 여기서
# 탑승구↔탑승구를 잇거나 아무것도 못 잇는다. 원본 간선을 주면 올바른 짝을 만든다.
def _b1_b2_floors() -> list[dict]:
    return [
        _floor("B2", -2, [
            _esc("B2:fr", 152, 141, "down", name="ES2-1-DN(FRB1)"),
            _esc("B2:to", 154, 141, "down", name="ES2-1-DN(TOB3)"),
        ]),
        _floor("B1", -1, [_esc("B1:to", 158, 160, "down", name="ES2-1-DN(TOB2)")]),
    ]


def test_원본_간선으로_에스컬레이터_탑승구와_하차구를_잇는다():
    floors = _b1_b2_floors()
    source = [{"from": "B1:to", "to": "B2:fr", "passable": True}]
    transfers, unresolved = vt.build_transfers(floors, source)
    esc = [t for t in transfers if t["mode"] == "escalator"]

    assert len(esc) == 1
    assert esc[0]["from"] == "B1:to" and esc[0]["to"] == "B2:fr"  # 하행: 위층 → 아래층
    assert esc[0]["bidirectional"] is False
    assert esc[0]["cost_m"] == vt.ESCALATOR_HOP_M
    # length_m은 비용이 아니라 실제 이동 거리다(수평 약 19m + 층고).
    # 원본으로 이어진 노드는 근접 폴백을 타지 않으므로 미해결로 남지 않는다.
    assert not [u for u in unresolved if u["node_id"] == "B1:to"]


def test_원본_간선이_없으면_근접_폴백이_짝을_못_찾는다():
    # 이 회귀가 실제 증상이었다: 바로 옆 에스컬레이터에 간선이 없어 라우팅이
    # 멀리 돌아가는 기기를 골랐다.
    transfers, unresolved = vt.build_transfers(_b1_b2_floors())
    esc = [t for t in transfers if t["mode"] == "escalator"]

    assert not [t for t in esc if t["from"] == "B1:to" and t["to"] == "B2:fr"]
    assert [u for u in unresolved if u["node_id"] == "B1:to"]


def test_통행_불가로_표시된_원본_간선은_만들지_않는다():
    floors = _b1_b2_floors()
    source = [{"from": "B1:to", "to": "B2:fr", "passable": False}]
    transfers, unresolved = vt.build_transfers(floors, source)

    assert not [t for t in transfers if t["mode"] == "escalator"]
    assert [u for u in unresolved if "통행 불가" in u["reason"]]


def test_양쪽_층_파일의_passable이_엇갈리면_통행_가능으로_본다():
    # 원본은 같은 간선을 양쪽 층 파일에 한 번씩 넣는데, 실데이터에서 4쌍은
    # 한쪽만 passable=False다. 실재하는 기기를 통째로 지우는 쪽이 더 위험하다.
    floors = _b1_b2_floors()
    source = [
        {"from": "B1:to", "to": "B2:fr", "passable": False},
        {"from": "B2:fr", "to": "B1:to", "passable": True},
    ]
    transfers, _ = vt.build_transfers(floors, source)

    assert len([t for t in transfers if t["mode"] == "escalator"]) == 1


def test_원본_간선의_방향이_엇갈리면_잇지_않는다():
    floors = [
        _floor("1F", 1, [_esc("1F:up", 10, 10, "up")]),
        _floor("2F", 2, [_esc("2F:dn", 10, 10, "down")]),
    ]
    transfers, unresolved = vt.build_transfers(
        floors, [{"from": "1F:up", "to": "2F:dn", "passable": True}]
    )

    assert not [t for t in transfers if t["mode"] == "escalator"]
    assert [u for u in unresolved if "진행 방향" in u["reason"]]


# 엘리베이터는 샤프트가 서비스하는 모든 층쌍을 양방향으로 잇는다.
def test_엘리베이터는_샤프트_전_층쌍을_직행_연결한다():
    # 같은 자리(10,10)의 엘리베이터가 3개 층에 있다.
    floors = [
        _floor("1F", 1, [_elev("1F:ev", 10, 10)]),
        _floor("2F", 2, [_elev("2F:ev", 10, 10)]),
        _floor("3F", 3, [_elev("3F:ev", 10, 10)]),
    ]
    transfers, _ = vt.build_transfers(floors)
    ele = [t for t in transfers if t["mode"] == "elevator"]

    # 3개 층 → 층쌍 3개(1-2, 2-3, 1-3) 모두 직행 간선.
    assert len(ele) == 3
    assert all(t["bidirectional"] for t in ele)
    pairs = {frozenset(t["floors"]) for t in ele}
    assert pairs == {frozenset(["1F", "2F"]), frozenset(["2F", "3F"]), frozenset(["1F", "3F"])}


# V2 — 층수 기반 비용: 1~2층은 에스컬레이터, 3층+는 엘리베이터가 최단.
def test_비용모델이_층수에_따라_수단을_가른다():
    # 순수 비용 함수로 교차점을 고정한다. 에스컬 = 20×n, 엘리베 = 35 + 5×n.
    def esc_cost(n):
        return vt.ESCALATOR_HOP_M * n

    def elev_cost(n):
        return vt.ELEVATOR_BOARD_M + vt.ELEVATOR_PER_FLOOR_M * n

    assert esc_cost(1) < elev_cost(1)  # 1층: 에스컬레이터
    assert esc_cost(2) < elev_cost(2)  # 2층: 에스컬레이터
    assert elev_cost(3) < esc_cost(3)  # 3층: 엘리베이터
    assert elev_cost(4) < esc_cost(4)  # 4층+: 엘리베이터


# 엘리베이터 비용이 이동 층수에 비례해 커진다(직행이라도 멀수록 비싸다).
def test_엘리베이터_비용은_층수에_비례한다():
    floors = [
        _floor("1F", 1, [_elev("1F:ev", 10, 10)]),
        _floor("2F", 2, [_elev("2F:ev", 10, 10)]),
        _floor("3F", 3, [_elev("3F:ev", 10, 10)]),
    ]
    transfers, _ = vt.build_transfers(floors)
    # 비용은 cost_m이다 — length_m은 실제 이동 거리라 공식과 다르다.
    ele = {frozenset(t["floors"]): t["cost_m"] for t in transfers if t["mode"] == "elevator"}

    one_hop = ele[frozenset(["1F", "2F"])]
    two_hop = ele[frozenset(["1F", "3F"])]
    assert one_hop == vt.ELEVATOR_BOARD_M + vt.ELEVATOR_PER_FLOOR_M * 1
    assert two_hop == vt.ELEVATOR_BOARD_M + vt.ELEVATOR_PER_FLOOR_M * 2
    assert two_hop > one_hop


# V3 — 전이 간선은 실제 이동 거리와 라우팅 비용을 각각 따로 싣는다.
#
# 예전에는 length_m 하나가 둘을 겸했다. 그러면 에스컬레이터 한 칸이 실제로는 6m쯤인데
# 라우팅 튜닝값 20m가 그대로 사용자 표시 거리에 더해진다. 두 값이 섞이지 않는지 본다.
def test_전이_간선은_실제_거리와_라우팅_비용을_분리한다():
    floors = [
        _floor("1F", 1, [_esc("1F:up", 10, 10, "up")]),
        _floor("2F", 2, [_esc("2F:up", 12, 10, "up")]),
    ]
    transfers, _ = vt.build_transfers(floors)
    esc = next(t for t in transfers if t["mode"] == "escalator")

    # 비용은 튜닝 상수 그대로다.
    assert esc["cost_m"] == vt.ESCALATOR_HOP_M
    # 거리는 수평 주행(2m)과 층고의 빗변 — 비용과 무관하게 실제 기하로 나온다.
    assert esc["length_m"] == pytest.approx(hypot(2.0, vt.FLOOR_HEIGHT_M), abs=1e-3)
    assert esc["length_m"] != esc["cost_m"]


# 엘리베이터도 같다. 층을 많이 갈수록 실제 거리와 비용이 함께 늘지만 값 자체는 다르다.
def test_엘리베이터도_거리와_비용이_따로_늘어난다():
    floors = [
        _floor("1F", 1, [_elev("1F:ev", 10, 10)]),
        _floor("2F", 2, [_elev("2F:ev", 10, 10)]),
        _floor("3F", 3, [_elev("3F:ev", 10, 10)]),
    ]
    transfers, _ = vt.build_transfers(floors)
    by_floors = {frozenset(t["floors"]): t for t in transfers if t["mode"] == "elevator"}

    one_hop = by_floors[frozenset(["1F", "2F"])]
    two_hop = by_floors[frozenset(["1F", "3F"])]

    # 같은 샤프트라 수평 이동은 0 — 실제 거리는 층고 × 홉 수다.
    assert one_hop["length_m"] == pytest.approx(vt.FLOOR_HEIGHT_M, abs=1e-3)
    assert two_hop["length_m"] == pytest.approx(vt.FLOOR_HEIGHT_M * 2, abs=1e-3)
    # 비용에는 고정 탑승비가 붙어 거리와 전혀 다른 값이 된다.
    assert one_hop["cost_m"] == vt.ELEVATOR_BOARD_M + vt.ELEVATOR_PER_FLOOR_M
    assert one_hop["cost_m"] > one_hop["length_m"]
