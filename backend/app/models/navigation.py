# 길찾기 그래프(Node·Edge) ORM 엔티티.

from __future__ import annotations

from typing import TYPE_CHECKING

from sqlalchemy import JSON, Boolean, CheckConstraint, Float, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base

if TYPE_CHECKING:
    from app.models.building import Floor

# 수직 전이 간선이 가질 수 있는 이동 수단. 층 내부 간선은 transfer_mode가 NULL이다.
# scripts/transform/vertical_transfers.TRANSFER_TYPES와 같은 집합을 DB 제약으로 못박는다.
TRANSFER_MODES = ("elevator", "escalator")


class Node(Base):
    __tablename__ = "nodes"
    __table_args__ = (
        Index("idx_nodes_floor", "floor_id"),
        Index("idx_nodes_type", "type"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True)  # 노드 고유 id (층 스코프로 접두: "{floor_id}:{원본id}")
    floor_id: Mapped[str] = mapped_column(ForeignKey("floors.id"), nullable=False)  # 소속 층 FK

    type: Mapped[str] = mapped_column(String, nullable=False)  # 노드 종류 (junction/elevator/escalator 등)
    name: Mapped[str | None] = mapped_column(String)  # 노드 표시 이름, 선택 (대부분 없음)

    x_m: Mapped[float] = mapped_column(Float, nullable=False)  # 건물 로컬 좌표 X (미터)
    y_m: Mapped[float] = mapped_column(Float, nullable=False)  # 건물 로컬 좌표 Y (미터)

    lat: Mapped[float | None] = mapped_column(Float)  # 실측 위도(WGS84), 선택 — geo 변환 대응점
    lng: Mapped[float | None] = mapped_column(Float)  # 실측 경도(WGS84), 선택 — geo 변환 대응점

    source_x: Mapped[float | None] = mapped_column(Float)  # 원천 데이터 원좌표 X (디버그·역추적용), 선택
    source_y: Mapped[float | None] = mapped_column(Float)  # 원천 데이터 원좌표 Y (디버그·역추적용), 선택

    floor: Mapped[Floor] = relationship(back_populates="nodes")  # 소속 층 (N:1)


class Edge(Base):
    __tablename__ = "edges"
    # 주석·시드 로직에만 있던 핵심 불변식을 DB 제약으로 못박아, 손상된 간선이 애초에
    # commit되지 못하게 한다(그래프 검증기와 함께 무결성의 두 겹 방어선).
    __table_args__ = (
        Index("idx_edges_floor", "floor_id"),
        Index("idx_edges_from", "from_node_id"),
        Index("idx_edges_to", "to_node_id"),
        # 거리·비용은 음수일 수 없다(다익스트라 가중치 음수 = 잘못된 최단 경로).
        CheckConstraint("length_m >= 0", name="ck_edges_length_nonneg"),
        CheckConstraint("cost_m >= 0", name="ck_edges_cost_nonneg"),
        # 자기 자신을 잇는 간선은 길찾기에서 의미가 없고 무한 루프의 씨앗이 된다.
        CheckConstraint("from_node_id <> to_node_id", name="ck_edges_no_self_loop"),
        # 전이 수단은 NULL(층 내부 간선)이거나 알려진 수단 중 하나여야 한다.
        CheckConstraint(
            "transfer_mode IS NULL OR transfer_mode IN ('elevator', 'escalator')",
            name="ck_edges_transfer_mode",
        ),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True)  # 간선 고유 id
    # 층 내부 간선은 해당 층 id를 가진다. 층을 잇는 수직 전이(transfer) 간선은
    # 특정 층에 속하지 않으므로 NULL이다. (단일 층 조회는 floor_id로 필터되어 제외됨)
    floor_id: Mapped[str | None] = mapped_column(ForeignKey("floors.id"))
    from_node_id: Mapped[str] = mapped_column(ForeignKey("nodes.id"), nullable=False)  # 시작 노드 FK
    to_node_id: Mapped[str] = mapped_column(ForeignKey("nodes.id"), nullable=False)  # 끝 노드 FK
    # 실제 이동 거리(미터). 사용자에게 보여 주는 거리·진행률의 근거다.
    length_m: Mapped[float] = mapped_column(Float, nullable=False)
    # 라우팅 비용(미터 단위 가중치) = Dijkstra가 최소화하는 값.
    #
    # 층 내부 간선은 length_m와 같다. 수직 전이 간선만 달라진다 — "어떤 수단으로 몇 층을
    # 갈지"를 고르게 하려고 실제 거리가 아닌 튜닝된 비용을 싣기 때문이다
    # (scripts/transform/vertical_transfers.py의 비용 상수 주석 참고).
    # 이 둘을 한 컬럼으로 겸하면 에스컬레이터 20m 같은 가중치가 사용자에게 보이는
    # 총 거리에 그대로 더해져 표시 거리가 부풀려진다.
    cost_m: Mapped[float] = mapped_column(Float, nullable=False)
    bidirectional: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)  # 양방향 통행 가능 여부
    geometry: Mapped[list[dict] | None] = mapped_column(JSON)  # 간선 경로 폴리라인 좌표(local_m), 선택 (직선이면 없음)
    # 수직 전이 간선 여부(elevator/escalator 환승). 층 내부 간선은 None.
    transfer_mode: Mapped[str | None] = mapped_column(String)

    floor: Mapped[Floor] = relationship(back_populates="edges")  # 소속 층 (N:1, 전이 간선은 None)
    from_node: Mapped[Node] = relationship(foreign_keys=[from_node_id])  # 시작 노드 객체
    to_node: Mapped[Node] = relationship(foreign_keys=[to_node_id])  # 끝 노드 객체
