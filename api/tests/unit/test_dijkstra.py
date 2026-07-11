"""다익스트라 순수 도메인 로직 단위 테스트."""

import pytest

from app.domain.building import Edge, LocalPoint, Node
from app.domain.dijkstra import find_shortest_path

FLOOR_ID = "floor-1"


def _node(node_id: str) -> Node:
    return Node(node_id, FLOOR_ID, "corridor", None, LocalPoint(0, 0), None, None)


def _edge(
    edge_id: str,
    start: str,
    end: str,
    length: float,
    bidirectional: bool = True,
) -> Edge:
    return Edge(edge_id, FLOOR_ID, start, end, length, bidirectional)


# 직접 경로보다 거리 합이 작은 우회 경로를 선택하는지 검증한다.
def test_거리합이_가장_작은_경로를_선택한다():
    path = find_shortest_path(
        [_node("A"), _node("B"), _node("C")],
        [
            _edge("AC", "A", "C", 10.0),
            _edge("AB", "A", "B", 2.0),
            _edge("BC", "B", "C", 3.0),
        ],
        "A",
        "C",
    )

    assert path.node_ids == ("A", "B", "C")
    assert path.edge_ids == ("AB", "BC")
    assert path.total_distance_m == 5.0


# 단방향 간선을 반대 방향으로 탐색하지 않는지 검증한다.
def test_단방향_간선은_역방향으로_이동할_수_없다():
    path = find_shortest_path(
        [_node("A"), _node("B")],
        [_edge("AB", "A", "B", 1.0, bidirectional=False)],
        "B",
        "A",
    )

    assert path is None


# 출발지와 목적지가 같을 때 이동 간선 없이 거리 0인지 검증한다.
def test_출발지와_목적지가_같으면_거리는_0이다():
    path = find_shortest_path([_node("A")], [], "A", "A")

    assert path.node_ids == ("A",)
    assert path.edge_ids == ()
    assert path.total_distance_m == 0.0


# 서로 연결되지 않은 노드 사이의 경로가 결과 없음인지 검증한다.
def test_연결되지_않은_노드는_경로가_없다():
    path = find_shortest_path([_node("A"), _node("B")], [], "A", "B")

    assert path is None


# 다익스트라가 지원하지 않는 음수 간선 거리를 거부하는지 검증한다.
def test_음수_가중치는_값오류다():
    with pytest.raises(ValueError, match="음수"):
        find_shortest_path(
            [_node("A"), _node("B")],
            [_edge("AB", "A", "B", -1.0)],
            "A",
            "B",
        )


# 그래프에 없는 출발 노드가 값 오류로 처리되는지 검증한다.
def test_존재하지_않는_출발노드는_값오류다():
    with pytest.raises(ValueError, match="출발 노드"):
        find_shortest_path([_node("A")], [], "missing", "A")
