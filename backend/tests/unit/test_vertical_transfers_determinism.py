"""수직 전이 생성의 결정성(permutation invariance) property test.

검증 기준(04번 완료 기준 1):
    입력의 순서만 바꿔도 생성 결과(전이 간선 집합 + unresolved 집합)가 동일하다.
    층 순서, 층 안의 노드 순서를 어떻게 섞어도 같아야 한다 — 예전 순차 탐욕 매칭은
    이 성질을 어겼다.
"""

from __future__ import annotations

import itertools
import random

from scripts.transform import vertical_transfers as vt


def _esc(node_id: str, x: float, y: float, direction: str) -> dict:
    code = "OB-ESCALATOR_UP" if direction == "up" else "OB-ESCALATOR_DOWN"
    return {
        "id": node_id,
        "type": "escalator",
        "name": node_id,
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


def _fixture_floors() -> list[dict]:
    # 3개 층, 각 층에: 상·하행 에스컬레이터 + 나란한 엘리베이터 뱅크 2열.
    floors = []
    for name, level in (("1F", 1), ("2F", 2), ("3F", 3)):
        floors.append(
            _floor(
                name,
                level,
                [
                    _esc(f"{name}:up", 10, 10, "up"),
                    _esc(f"{name}:dn", 20, 20, "down"),
                    _elev(f"{name}:eva", 30, 30),
                    _elev(f"{name}:evb", 33, 30),
                ],
            )
        )
    return floors


def _canonical(result):
    transfers, unresolved = result
    edge_set = frozenset(
        (t["from"], t["to"], t["mode"], t["bidirectional"], round(t["cost_m"], 6), round(t["length_m"], 6))
        for t in transfers
    )
    unresolved_set = frozenset((u["node_id"], u["floor"], u["mode"], u["reason"]) for u in unresolved)
    return edge_set, unresolved_set


def _permuted(floors: list[dict], rng: random.Random) -> list[dict]:
    shuffled = []
    for floor in floors:
        nodes = list(floor["nodes"])
        rng.shuffle(nodes)
        shuffled.append({**floor, "nodes": nodes})
    rng.shuffle(shuffled)
    return shuffled


def test_층_노드_순서를_섞어도_결과가_동일하다():
    floors = _fixture_floors()
    baseline = _canonical(vt.build_transfers(floors))

    rng = random.Random(0)
    for _ in range(50):
        permuted = _permuted(floors, rng)
        assert _canonical(vt.build_transfers(permuted)) == baseline


def test_층_순서_전체_순열에서도_동일하다():
    floors = _fixture_floors()
    baseline = _canonical(vt.build_transfers(floors))

    # 층 순서 6가지 전부 확인(build_transfers가 내부에서 level로 정렬하므로 무관해야 한다).
    for order in itertools.permutations(floors):
        assert _canonical(vt.build_transfers(list(order))) == baseline


def test_결과가_비어있지_않다():
    # 픽스처가 실제로 전이 간선을 만들어 위 불변 테스트가 공허하지 않음을 보장한다.
    transfers, _ = vt.build_transfers(_fixture_floors())
    assert [t for t in transfers if t["mode"] == "escalator"]
    assert [t for t in transfers if t["mode"] == "elevator"]
