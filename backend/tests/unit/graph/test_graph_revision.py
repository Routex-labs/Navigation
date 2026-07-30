"""그래프 리비전(app.graph.revision) 단위 테스트.

검증 기준:
    같은 그래프는 순서가 달라도 같은 리비전을, 내용이 바뀌면 다른 리비전을 낸다.
    캐시 무효화 키로 쓰이므로 이 두 성질이 핵심이다.
"""

from __future__ import annotations

from app.graph.revision import graph_revision

NODES = [{"id": "n1", "x_m": 0.0}, {"id": "n2", "x_m": 1.0}]
EDGES = [{"id": "e1", "from": "n1", "to": "n2", "cost_m": 1.0}]


def test_같은_그래프는_같은_리비전이다():
    assert graph_revision(NODES, EDGES) == graph_revision(NODES, EDGES)


def test_입력_순서가_달라도_같은_리비전이다():
    shuffled_nodes = list(reversed(NODES))
    assert graph_revision(shuffled_nodes, EDGES) == graph_revision(NODES, EDGES)


def test_노드_값이_바뀌면_리비전이_바뀐다():
    changed = [{"id": "n1", "x_m": 99.0}, {"id": "n2", "x_m": 1.0}]
    assert graph_revision(changed, EDGES) != graph_revision(NODES, EDGES)


def test_간선_비용이_바뀌면_리비전이_바뀐다():
    changed = [{"id": "e1", "from": "n1", "to": "n2", "cost_m": 2.0}]
    assert graph_revision(NODES, changed) != graph_revision(NODES, EDGES)


def test_간선이_추가되면_리비전이_바뀐다():
    extended = EDGES + [{"id": "e2", "from": "n2", "to": "n1", "cost_m": 1.0}]
    assert graph_revision(NODES, extended) != graph_revision(NODES, EDGES)
