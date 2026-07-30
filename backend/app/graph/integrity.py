"""길찾기 그래프 무결성 검증기.

DB의 CheckConstraint·FK(app/models/navigation.py, app/core/database.py의 PRAGMA)는
**구조적** 위반(중복 PK, 고아 참조, 자기 참조, 음수 거리·비용)을 저장 시점에 막는다.
이 검증기는 그 위에서 DB가 못 잡는 **의미·위상** 위반을 잡는다.

  - 다른 건물을 잇는 간선 (FK는 노드 존재만 보고 소속 건물은 안 본다)
  - 수직 전이 간선이 같은 층을 잇거나, 층 내부 간선이 다른 층을 잇는 경우
  - NaN/Infinity 거리·비용 (SQLite의 `>= 0` 비교로는 걸러지지 않을 수 있다)
  - 빈/한 점짜리 geometry (직선을 그릴 수 없는 층 내부 간선)
  - 에스컬레이터 전이가 양방향이거나 같은 층을 잇는 경우
  - 그래프에 연결되지 않은 매장 입구, 고립된 컴포넌트

**DB 삽입에 의존하지 않는 순수 함수**다. 그래야 (1) 일부러 깨진 그래프로 검증기 자체를
테스트할 수 있고 — DB는 그런 간선을 애초에 거부하므로 —, (2) 04·05 작업이 간선을
저장하기 *전에* 같은 규칙으로 검사할 수 있다.

collect_graph_data(session)로 DB 전체를 평범한 구조로 뽑고, validate_graph(data)로
검사한다. 시드는 이 둘을 이어 붙여 검증 결과와 통계를 artifact로 남긴다.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
from math import isfinite
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Edge, Floor, Node, Store

ERROR = "error"
WARNING = "warning"


class GraphIntegrityError(ValueError):
    """그래프 검증에서 에러가 나왔을 때 시드를 중단시키는 예외.

    facet 검증(studio_adapter.validate_facet_resources)과 같은 철학 — 잘못된
    데이터가 DB에 반쯤 들어간 채 실패하지 않도록, commit 전에 던져 롤백을 유도한다.
    """

    def __init__(self, report: "GraphReport") -> None:
        self.report = report
        detail = "\n  - ".join(f"[{issue.code}] {issue.message}" for issue in report.errors)
        super().__init__(f"그래프 무결성 검증 실패 ({len(report.errors)}건):\n  - {detail}")


# --- 입력 구조 (DB에 독립) ---------------------------------------------------


@dataclass(frozen=True)
class FloorInfo:
    id: str
    building_id: str
    level: int
    name: str


@dataclass(frozen=True)
class NodeInfo:
    id: str
    floor_id: str
    type: str


@dataclass(frozen=True)
class EdgeInfo:
    id: str
    from_id: str
    to_id: str
    length_m: float
    cost_m: float
    transfer_mode: str | None
    bidirectional: bool
    # 층 내부 간선은 floor_id를 가지고, 수직 전이 간선은 None이다.
    floor_id: str | None
    # geometry 점 개수만 검증에 쓰므로 좌표 전체 대신 개수만 받는다(None이면 미지정).
    geometry_point_count: int | None


@dataclass(frozen=True)
class StoreInfo:
    id: str
    floor_id: str
    entrance_node_id: str | None


@dataclass
class GraphData:
    floors: list[FloorInfo]
    nodes: list[NodeInfo]
    edges: list[EdgeInfo]
    stores: list[StoreInfo]


# --- 검증 결과 ---------------------------------------------------------------


@dataclass(frozen=True)
class GraphIssue:
    severity: str  # ERROR | WARNING
    code: str  # 기계가 분류할 짧은 코드
    message: str  # 사람이 읽을 설명(한국어)
    building_id: str | None = None
    ref: str | None = None  # 관련 node/edge/store id

    def to_dict(self) -> dict[str, Any]:
        return {
            "severity": self.severity,
            "code": self.code,
            "message": self.message,
            "building_id": self.building_id,
            "ref": self.ref,
        }


@dataclass
class GraphReport:
    issues: list[GraphIssue] = field(default_factory=list)
    stats: dict[str, Any] = field(default_factory=dict)

    @property
    def errors(self) -> list[GraphIssue]:
        return [issue for issue in self.issues if issue.severity == ERROR]

    @property
    def warnings(self) -> list[GraphIssue]:
        return [issue for issue in self.issues if issue.severity == WARNING]

    @property
    def ok(self) -> bool:
        # 경고는 통과, 에러가 하나라도 있으면 실패.
        return not self.errors

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "error_count": len(self.errors),
            "warning_count": len(self.warnings),
            "stats": self.stats,
            "issues": [issue.to_dict() for issue in self.issues],
        }


# --- DB → GraphData ----------------------------------------------------------


def validate_seeded_graph(session: Session) -> GraphReport:
    """세션에 쌓인 그래프를 flush 후 검증하고, 에러가 있으면 GraphIntegrityError를 던진다.

    시드 게이트로 쓴다 — commit 전에 호출해 손상된 그래프가 저장되지 못하게 한다.
    경고는 통과시키므로, 반환된 리포트로 통계·경고를 artifact에 남길 수 있다.
    """
    session.flush()  # add_all로 대기 중인 노드·간선을 DB에 내보내 조회로 되읽을 수 있게 한다.
    report = validate_graph(collect_graph_data(session))
    if not report.ok:
        raise GraphIntegrityError(report)
    return report


def collect_graph_data(session: Session) -> GraphData:
    """DB 전체 그래프를 검증기 입력 구조로 뽑는다(건물 무관, 한 번에)."""
    floors = [
        FloorInfo(id=f.id, building_id=f.building_id, level=f.level, name=f.name)
        for f in session.scalars(select(Floor)).all()
    ]
    nodes = [NodeInfo(id=n.id, floor_id=n.floor_id, type=n.type) for n in session.scalars(select(Node)).all()]
    edges = [
        EdgeInfo(
            id=e.id,
            from_id=e.from_node_id,
            to_id=e.to_node_id,
            length_m=e.length_m,
            cost_m=e.cost_m,
            transfer_mode=e.transfer_mode,
            bidirectional=e.bidirectional,
            floor_id=e.floor_id,
            geometry_point_count=len(e.geometry) if e.geometry is not None else None,
        )
        for e in session.scalars(select(Edge)).all()
    ]
    stores = [
        StoreInfo(id=s.id, floor_id=s.floor_id, entrance_node_id=s.entrance_node_id)
        for s in session.scalars(select(Store)).all()
    ]
    return GraphData(floors=floors, nodes=nodes, edges=edges, stores=stores)


# --- 검증 --------------------------------------------------------------------


def validate_graph(data: GraphData) -> GraphReport:
    """그래프 무결성을 검사하고 이슈 목록 + 통계를 담은 리포트를 낸다."""
    report = GraphReport()

    floor_by_id = {floor.id: floor for floor in data.floors}
    node_by_id = {node.id: node for node in data.nodes}

    _check_duplicate_ids(data, report)
    _check_edge_endpoints(data, node_by_id, floor_by_id, report)
    _check_edge_values(data, report)
    _check_edge_geometry(data, report)
    _check_store_entrances(data, node_by_id, report)
    _check_connectivity(data, node_by_id, floor_by_id, report)

    report.stats = _build_stats(data, floor_by_id)
    return report


def _node_building(node: NodeInfo, floor_by_id: dict[str, FloorInfo]) -> str | None:
    floor = floor_by_id.get(node.floor_id)
    return floor.building_id if floor else None


def _check_duplicate_ids(data: GraphData, report: GraphReport) -> None:
    # DB PK가 이미 막지만, DB에 넣기 전 데이터(04·05)에도 이 검증기를 쓰므로 확인한다.
    for kind, ids in (("node", [n.id for n in data.nodes]), ("edge", [e.id for e in data.edges])):
        seen: set[str] = set()
        for identifier in ids:
            if identifier in seen:
                report.issues.append(
                    GraphIssue(ERROR, f"duplicate_{kind}_id", f"{kind} id가 중복된다: {identifier}", ref=identifier)
                )
            seen.add(identifier)


def _check_edge_endpoints(
    data: GraphData,
    node_by_id: dict[str, NodeInfo],
    floor_by_id: dict[str, FloorInfo],
    report: GraphReport,
) -> None:
    for edge in data.edges:
        from_node = node_by_id.get(edge.from_id)
        to_node = node_by_id.get(edge.to_id)

        # 존재하지 않는 endpoint.
        if from_node is None or to_node is None:
            missing = edge.from_id if from_node is None else edge.to_id
            report.issues.append(
                GraphIssue(ERROR, "missing_endpoint", f"간선 {edge.id}의 endpoint 노드가 없다: {missing}", ref=edge.id)
            )
            continue

        # 자기 자신을 잇는 간선.
        if edge.from_id == edge.to_id:
            report.issues.append(GraphIssue(ERROR, "self_loop", f"간선 {edge.id}이 자기 자신을 잇는다", ref=edge.id))

        from_building = _node_building(from_node, floor_by_id)
        to_building = _node_building(to_node, floor_by_id)

        # 다른 건물을 잇는 간선.
        if from_building is not None and to_building is not None and from_building != to_building:
            report.issues.append(
                GraphIssue(
                    ERROR,
                    "cross_building_edge",
                    f"간선 {edge.id}이 다른 건물을 잇는다: {from_building} → {to_building}",
                    building_id=from_building,
                    ref=edge.id,
                )
            )

        same_floor = from_node.floor_id == to_node.floor_id

        if edge.transfer_mode is None:
            # 층 내부 간선: 양 끝이 같은 층이어야 하고, 간선의 floor_id와도 일치해야 한다.
            if not same_floor:
                report.issues.append(
                    GraphIssue(
                        ERROR,
                        "intra_edge_floor_mismatch",
                        f"층 내부 간선 {edge.id}의 양 끝이 다른 층이다",
                        building_id=from_building,
                        ref=edge.id,
                    )
                )
            elif edge.floor_id is not None and edge.floor_id != from_node.floor_id:
                report.issues.append(
                    GraphIssue(
                        ERROR,
                        "intra_edge_floor_label_mismatch",
                        f"층 내부 간선 {edge.id}의 floor_id가 endpoint 층과 다르다",
                        building_id=from_building,
                        ref=edge.id,
                    )
                )
        else:
            # 수직 전이 간선: 서로 다른 층을 이어야 한다(같은 층이면 전이가 아니다).
            if same_floor:
                report.issues.append(
                    GraphIssue(
                        ERROR,
                        "transfer_same_floor",
                        f"전이 간선 {edge.id}이 같은 층을 잇는다",
                        building_id=from_building,
                        ref=edge.id,
                    )
                )
            # 에스컬레이터 전이는 단방향이어야 한다(상행 전용을 하행으로 타는 불가능 경로 방지).
            if edge.transfer_mode == "escalator" and edge.bidirectional:
                report.issues.append(
                    GraphIssue(
                        ERROR,
                        "escalator_bidirectional",
                        f"에스컬레이터 전이 {edge.id}이 양방향이다(단방향이어야 함)",
                        building_id=from_building,
                        ref=edge.id,
                    )
                )


def _check_edge_values(data: GraphData, report: GraphReport) -> None:
    for edge in data.edges:
        for label, value in (("length_m", edge.length_m), ("cost_m", edge.cost_m)):
            # NaN/Infinity — DB의 `>= 0`으로는 못 거를 수 있어 여기서 확실히 잡는다.
            if not isfinite(value):
                report.issues.append(
                    GraphIssue(
                        ERROR, "non_finite_value", f"간선 {edge.id}의 {label}가 유한하지 않다: {value}", ref=edge.id
                    )
                )
            elif value < 0:
                report.issues.append(
                    GraphIssue(ERROR, "negative_value", f"간선 {edge.id}의 {label}가 음수다: {value}", ref=edge.id)
                )


def _check_edge_geometry(data: GraphData, report: GraphReport) -> None:
    for edge in data.edges:
        # 수직 전이 간선은 geometry가 없어도 된다(직선 마커). 층 내부 간선만 검사한다.
        if edge.transfer_mode is not None:
            continue
        if edge.geometry_point_count is None:
            continue  # geometry 미지정 — 시드가 양 끝 노드로 직선을 보완하므로 허용.
        if edge.geometry_point_count < 2:
            report.issues.append(
                GraphIssue(
                    WARNING,
                    "degenerate_geometry",
                    f"간선 {edge.id}의 geometry가 점 {edge.geometry_point_count}개뿐이라 선을 그릴 수 없다",
                    ref=edge.id,
                )
            )


def _check_store_entrances(data: GraphData, node_by_id: dict[str, NodeInfo], report: GraphReport) -> None:
    # 입구 노드가 있는데 그래프에 없는 노드를 가리키면 경로의 도착점이 사라진다.
    for store in data.stores:
        if store.entrance_node_id is None:
            continue
        if store.entrance_node_id not in node_by_id:
            report.issues.append(
                GraphIssue(
                    WARNING,
                    "store_entrance_missing_node",
                    f"매장 {store.id}의 입구 노드 {store.entrance_node_id}가 그래프에 없다",
                    ref=store.id,
                )
            )


def _check_connectivity(
    data: GraphData,
    node_by_id: dict[str, NodeInfo],
    floor_by_id: dict[str, FloorInfo],
    report: GraphReport,
) -> None:
    # 건물별로 연결 컴포넌트를 세어, 여러 조각으로 갈라진 그래프를 경고한다.
    # 경고인 이유: 일부 건물은 물리적으로 떨어진 구역이 있을 수 있어 무조건 오류는 아니다.
    building_nodes: dict[str, list[str]] = defaultdict(list)
    for node in data.nodes:
        building = _node_building(node, floor_by_id)
        if building is not None:
            building_nodes[building].append(node.id)

    # Union-Find로 endpoint가 둘 다 존재하는 간선만 합친다.
    parent: dict[str, str] = {node.id: node.id for node in data.nodes}

    def find(x: str) -> str:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a: str, b: str) -> None:
        parent[find(a)] = find(b)

    for edge in data.edges:
        if edge.from_id in parent and edge.to_id in parent:
            union(edge.from_id, edge.to_id)

    for building, node_ids in building_nodes.items():
        if len(node_ids) < 2:
            continue
        components = {find(node_id) for node_id in node_ids}
        if len(components) > 1:
            report.issues.append(
                GraphIssue(
                    WARNING,
                    "disconnected_components",
                    f"건물 {building} 그래프가 {len(components)}개 컴포넌트로 갈라져 있다",
                    building_id=building,
                )
            )


def _build_stats(data: GraphData, floor_by_id: dict[str, FloorInfo]) -> dict[str, Any]:
    transfer_edges = [edge for edge in data.edges if edge.transfer_mode is not None]
    by_building: dict[str, dict[str, int]] = defaultdict(lambda: {"floors": 0, "nodes": 0, "edges": 0})

    for floor in data.floors:
        by_building[floor.building_id]["floors"] += 1
    for node in data.nodes:
        building = _node_building(node, floor_by_id)
        if building is not None:
            by_building[building]["nodes"] += 1
    for edge in data.edges:
        floor = floor_by_id.get(edge.floor_id) if edge.floor_id else None
        # 전이 간선은 floor_id가 없으므로 from endpoint의 건물로 집계한다.
        building = floor.building_id if floor else None
        if building is not None:
            by_building[building]["edges"] += 1

    return {
        "buildings": len(by_building),
        "floors": len(data.floors),
        "nodes": len(data.nodes),
        "edges": len(data.edges),
        "transfer_edges": len(transfer_edges),
        "stores": len(data.stores),
        "by_building": dict(by_building),
    }
