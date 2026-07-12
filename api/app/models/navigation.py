"""길찾기 그래프(Node·Edge) ORM 엔티티."""

from __future__ import annotations

from typing import TYPE_CHECKING

from sqlalchemy import Boolean, Float, ForeignKey, Index, JSON, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base

if TYPE_CHECKING:
    from app.models.building import Floor


class Node(Base):
    __tablename__ = "nodes"
    __table_args__ = (
        Index("idx_nodes_floor", "floor_id"),
        Index("idx_nodes_type", "type"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True)
    floor_id: Mapped[str] = mapped_column(ForeignKey("floors.id"), nullable=False)
    type: Mapped[str] = mapped_column(String, nullable=False)
    name: Mapped[str | None] = mapped_column(String)
    x_m: Mapped[float] = mapped_column(Float, nullable=False)
    y_m: Mapped[float] = mapped_column(Float, nullable=False)
    lat: Mapped[float | None] = mapped_column(Float)
    lng: Mapped[float | None] = mapped_column(Float)
    source_x: Mapped[float | None] = mapped_column(Float)
    source_y: Mapped[float | None] = mapped_column(Float)

    floor: Mapped["Floor"] = relationship(back_populates="nodes")


class Edge(Base):
    __tablename__ = "edges"
    __table_args__ = (
        Index("idx_edges_floor", "floor_id"),
        Index("idx_edges_from", "from_node_id"),
        Index("idx_edges_to", "to_node_id"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True)
    floor_id: Mapped[str] = mapped_column(ForeignKey("floors.id"), nullable=False)
    from_node_id: Mapped[str] = mapped_column(ForeignKey("nodes.id"), nullable=False)
    to_node_id: Mapped[str] = mapped_column(ForeignKey("nodes.id"), nullable=False)
    length_m: Mapped[float] = mapped_column(Float, nullable=False)
    bidirectional: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    geometry: Mapped[list[dict] | None] = mapped_column(JSON)

    floor: Mapped["Floor"] = relationship(back_populates="edges")
    from_node: Mapped[Node] = relationship(foreign_keys=[from_node_id])
    to_node: Mapped[Node] = relationship(foreign_keys=[to_node_id])
