"""매장·POI ORM 엔티티."""

from __future__ import annotations

from typing import TYPE_CHECKING

from sqlalchemy import Float, ForeignKey, Index, JSON, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base

if TYPE_CHECKING:
    from app.models.building import Floor
    from app.models.navigation import Node


class Store(Base):
    __tablename__ = "stores"
    __table_args__ = (
        Index("idx_stores_floor", "floor_id"),
        Index("idx_stores_name", "name"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True)
    floor_id: Mapped[str] = mapped_column(ForeignKey("floors.id"), nullable=False)
    name: Mapped[str] = mapped_column(String, nullable=False)
    category: Mapped[str | None] = mapped_column(String)
    subcategory: Mapped[str | None] = mapped_column(String)
    centroid_x_m: Mapped[float] = mapped_column(Float, nullable=False)
    centroid_y_m: Mapped[float] = mapped_column(Float, nullable=False)
    entrance_x_m: Mapped[float | None] = mapped_column(Float)
    entrance_y_m: Mapped[float | None] = mapped_column(Float)
    entrance_node_id: Mapped[str | None] = mapped_column(ForeignKey("nodes.id"))
    polygon: Mapped[list[dict] | None] = mapped_column(JSON)

    floor: Mapped["Floor"] = relationship(back_populates="stores")
    entrance_node: Mapped["Node | None"] = relationship(
        foreign_keys=[entrance_node_id],
    )


class Poi(Base):
    __tablename__ = "pois"
    __table_args__ = (
        Index("idx_pois_floor", "floor_id"),
        Index("idx_pois_type", "type"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True)
    floor_id: Mapped[str] = mapped_column(ForeignKey("floors.id"), nullable=False)
    type: Mapped[str] = mapped_column(String, nullable=False)
    name: Mapped[str | None] = mapped_column(String)
    x_m: Mapped[float] = mapped_column(Float, nullable=False)
    y_m: Mapped[float] = mapped_column(Float, nullable=False)
    linked_node_id: Mapped[str | None] = mapped_column(ForeignKey("nodes.id"))

    floor: Mapped["Floor"] = relationship(back_populates="pois")
    linked_node: Mapped["Node | None"] = relationship(
        foreign_keys=[linked_node_id],
    )


