"""그래프 무결성 검증기(app.graph.integrity) 단위 테스트.

검증 기준:
    검증기는 DB가 못 잡는 의미·위상 위반을 잡는다 — 타 건물 연결, 전이 간선 동일 층,
    NaN/Infinity, 퇴화 geometry, 미연결 매장 입구, 고립 컴포넌트. 정상 그래프는 통과한다.
    (구조적 위반은 DB가 저장 시점에 막으므로, 여기서는 순수 함수로 직접 검사한다.)
"""

from __future__ import annotations

import math

from app.graph.integrity import (
    EdgeInfo,
    FloorInfo,
    GraphData,
    NodeInfo,
    StoreInfo,
    validate_graph,
)


def _edge(
    edge_id,
    from_id,
    to_id,
    *,
    transfer_mode=None,
    floor_id="f1",
    length_m=1.0,
    cost_m=1.0,
    bidirectional=True,
    geometry_point_count=2,
):
    return EdgeInfo(
        id=edge_id,
        from_id=from_id,
        to_id=to_id,
        length_m=length_m,
        cost_m=cost_m,
        transfer_mode=transfer_mode,
        bidirectional=bidirectional,
        floor_id=floor_id,
        geometry_point_count=geometry_point_count,
    )


def _base_graph():
    """건물 하나(b1), 층 둘(1F/2F), 각 층 노드 2개, 정상 간선 + 엘리베이터 전이 1개."""
    floors = [
        FloorInfo(id="f1", building_id="b1", level=1, name="1F"),
        FloorInfo(id="f2", building_id="b1", level=2, name="2F"),
    ]
    nodes = [
        NodeInfo(id="n1", floor_id="f1", type="junction"),
        NodeInfo(id="n2", floor_id="f1", type="elevator"),
        NodeInfo(id="n3", floor_id="f2", type="junction"),
        NodeInfo(id="n4", floor_id="f2", type="elevator"),
    ]
    edges = [
        _edge("e1", "n1", "n2", floor_id="f1"),
        _edge("e2", "n3", "n4", floor_id="f2"),
        _edge("xfer1", "n2", "n4", transfer_mode="elevator", floor_id=None, geometry_point_count=None, cost_m=40.0),
    ]
    stores = [StoreInfo(id="s1", floor_id="f1", entrance_node_id="n1")]
    return GraphData(floors=floors, nodes=nodes, edges=edges, stores=stores)


def _codes(report):
    return {issue.code for issue in report.issues}


def test_정상_그래프는_에러가_없다():
    report = validate_graph(_base_graph())
    assert report.ok, report.to_dict()
    assert report.errors == []


def test_통계가_집계된다():
    report = validate_graph(_base_graph())
    stats = report.stats
    assert stats["buildings"] == 1
    assert stats["floors"] == 2
    assert stats["nodes"] == 4
    assert stats["edges"] == 3
    assert stats["transfer_edges"] == 1
    assert stats["stores"] == 1


def test_존재하지_않는_endpoint를_잡는다():
    graph = _base_graph()
    graph.edges.append(_edge("bad", "n1", "ghost", floor_id="f1"))
    report = validate_graph(graph)
    assert not report.ok
    assert "missing_endpoint" in _codes(report)


def test_다른_건물을_잇는_간선을_잡는다():
    graph = _base_graph()
    graph.floors.append(FloorInfo(id="f9", building_id="b2", level=1, name="1F"))
    graph.nodes.append(NodeInfo(id="n9", floor_id="f9", type="junction"))
    # 층 내부인 척하지만 endpoint가 다른 건물 노드 → cross_building.
    graph.edges.append(_edge("bad", "n1", "n9", floor_id="f1"))
    report = validate_graph(graph)
    assert "cross_building_edge" in _codes(report)


def test_전이_간선이_같은_층을_잇으면_잡는다():
    graph = _base_graph()
    # n1, n2 모두 f1 → 같은 층인데 transfer_mode가 붙었다.
    graph.edges.append(_edge("bad", "n1", "n2", transfer_mode="elevator", floor_id=None))
    report = validate_graph(graph)
    assert "transfer_same_floor" in _codes(report)


def test_층_내부_간선이_다른_층을_잇으면_잡는다():
    graph = _base_graph()
    graph.edges.append(_edge("bad", "n1", "n3", floor_id="f1"))  # n1=f1, n3=f2
    report = validate_graph(graph)
    assert "intra_edge_floor_mismatch" in _codes(report)


def test_에스컬레이터_전이가_양방향이면_잡는다():
    graph = _base_graph()
    graph.edges.append(
        _edge(
            "bad", "n1", "n3", transfer_mode="escalator", floor_id=None, bidirectional=True, geometry_point_count=None
        )
    )
    report = validate_graph(graph)
    assert "escalator_bidirectional" in _codes(report)


def test_NaN_거리를_잡는다():
    graph = _base_graph()
    graph.edges.append(_edge("bad", "n1", "n2", floor_id="f1", length_m=math.nan))
    report = validate_graph(graph)
    assert "non_finite_value" in _codes(report)


def test_Infinity_비용을_잡는다():
    graph = _base_graph()
    graph.edges.append(_edge("bad", "n1", "n2", floor_id="f1", cost_m=math.inf))
    report = validate_graph(graph)
    assert "non_finite_value" in _codes(report)


def test_퇴화_geometry는_경고다():
    graph = _base_graph()
    graph.edges.append(_edge("bad", "n1", "n2", floor_id="f1", geometry_point_count=1))
    report = validate_graph(graph)
    # 경고이므로 ok는 유지되지만 이슈로 보고된다.
    assert report.ok
    assert "degenerate_geometry" in _codes(report)


def test_미연결_매장_입구는_경고다():
    graph = _base_graph()
    graph.stores.append(StoreInfo(id="s2", floor_id="f1", entrance_node_id="ghost"))
    report = validate_graph(graph)
    assert report.ok
    assert "store_entrance_missing_node" in _codes(report)


def test_고립_컴포넌트는_경고다():
    graph = _base_graph()
    # 어느 간선과도 이어지지 않은 노드 두 개(자기들끼리만 연결)를 b1에 더한다.
    graph.nodes.append(NodeInfo(id="iso1", floor_id="f1", type="junction"))
    graph.nodes.append(NodeInfo(id="iso2", floor_id="f1", type="junction"))
    graph.edges.append(_edge("iso", "iso1", "iso2", floor_id="f1"))
    report = validate_graph(graph)
    assert report.ok
    assert "disconnected_components" in _codes(report)
