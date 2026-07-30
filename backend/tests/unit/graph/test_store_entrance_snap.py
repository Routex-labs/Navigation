"""매장 입구 스냅 거리 제한(studio_adapter) 단위 테스트.

검증 기준(05번):
    입구를 가장 가까운 노드에 스냅할 때 최대 거리를 넘으면 자동 연결하지 않고
    unresolved로 보고한다. 임계값 안이면 그대로 연결한다.
"""

from __future__ import annotations

import json

from scripts.seed import studio_adapter as sa


def _node(node_id: str, x: float, y: float) -> dict:
    return {"id": node_id, "type": "junction", "position": {"local_m": {"x": x, "y": y}}}


def test_nearest_node_id는_노드와_거리를_돌려준다():
    nodes = [_node("F:n1", 0, 0), _node("F:n2", 10, 0)]
    node_id, distance = sa._nearest_node_id(nodes, 3, 0)
    assert node_id == "F:n1"
    assert distance == 3.0


def test_노드가_없으면_None과_inf다():
    node_id, distance = sa._nearest_node_id([], 0, 0)
    assert node_id is None
    assert distance == float("inf")


def _write_stores(directory, stores):
    (directory / "stores_t.json").write_text(json.dumps({"stores": stores}, ensure_ascii=False), encoding="utf-8")


def test_임계값_안_입구는_연결_밖_입구는_unresolved다(tmp_path, monkeypatch):
    monkeypatch.setattr(sa.settings, "store_entrance_snap_max_m", 10.0)
    nodes = [_node("F:n1", 0, 0)]
    _write_stores(
        tmp_path,
        [
            {
                "id": "near",
                "name": "가까운",
                "centroid_local_m": {"x": 2, "y": 0},
                "entrance_local_m": {"x": 2, "y": 0},
            },
            {"id": "far", "name": "먼", "centroid_local_m": {"x": 50, "y": 0}, "entrance_local_m": {"x": 50, "y": 0}},
        ],
    )

    reshaped, unresolved = sa._reshape_stores("t", "F", nodes, tmp_path)
    by_id = {store["id"]: store for store in reshaped}

    # 가까운 입구(2m ≤ 10m)는 노드에 연결된다.
    assert by_id["near"]["entrance_node_id"] == "F:n1"
    # 먼 입구(50m > 10m)는 연결하지 않고(도착점 None) unresolved로 보고한다.
    assert by_id["far"]["entrance_node_id"] is None
    assert len(unresolved) == 1
    assert unresolved[0]["store_id"] == "far"
    assert unresolved[0]["distance_m"] == 50.0
    assert unresolved[0]["max_m"] == 10.0
    # 먼 매장도 지도에는 남는다(연결만 안 됨) — 매장 목록에는 그대로 있다.
    assert "far" in by_id


def test_입구_좌표가_없으면_스냅도_unresolved도_없다(tmp_path, monkeypatch):
    monkeypatch.setattr(sa.settings, "store_entrance_snap_max_m", 10.0)
    nodes = [_node("F:n1", 0, 0)]
    _write_stores(tmp_path, [{"id": "no_ent", "name": "입구없음", "centroid_local_m": {"x": 1, "y": 0}}])

    reshaped, unresolved = sa._reshape_stores("t", "F", nodes, tmp_path)
    assert reshaped[0]["entrance_node_id"] is None
    assert unresolved == []
