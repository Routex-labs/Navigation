"""매장·POI·벡터 지도 ORM 엔티티."""

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


class FloorVectorMap(Base):
    __tablename__ = "floor_vector_maps"

    floor_id: Mapped[str] = mapped_column(
        ForeignKey("floors.id"),
        primary_key=True,
    )
    coordinate_system: Mapped[dict] = mapped_column(JSON, nullable=False)
    source: Mapped[dict] = mapped_column(JSON, nullable=False)

    floor: Mapped["Floor"] = relationship(back_populates="vector_map")
    features: Mapped[list["MapFeature"]] = relationship(back_populates="vector_map")


class MapFeature(Base):
    __tablename__ = "map_features"
    __table_args__ = (
        Index("idx_map_features_floor", "floor_id"),
        Index("idx_map_features_kind", "kind"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True)
    floor_id: Mapped[str] = mapped_column(
        ForeignKey("floor_vector_maps.floor_id"),
        primary_key=True,
    )
    kind: Mapped[str] = mapped_column(String, nullable=False)
    name: Mapped[str | None] = mapped_column(String)
    category: Mapped[str | None] = mapped_column(String)
    geometry_type: Mapped[str] = mapped_column(String, nullable=False)
    coordinates: Mapped[list | dict] = mapped_column(JSON, nullable=False)
    centroid_x: Mapped[float | None] = mapped_column(Float)
    centroid_y: Mapped[float | None] = mapped_column(Float)

    vector_map: Mapped["FloorVectorMap"] = relationship(back_populates="features")
