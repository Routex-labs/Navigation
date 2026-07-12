"""건물·층 ORM 엔티티."""

from __future__ import annotations

from typing import TYPE_CHECKING

from sqlalchemy import Float, ForeignKey, Integer, JSON, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base

if TYPE_CHECKING:
    from app.models.navigation import Edge, Node
    from app.models.place import FloorVectorMap, Poi, Store


class Building(Base):
    __tablename__ = "buildings"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    area_m2: Mapped[float | None] = mapped_column(Float)
    perimeter_m: Mapped[float | None] = mapped_column(Float)
    footprint_local_m: Mapped[list[dict] | None] = mapped_column(JSON)

    floors: Mapped[list["Floor"]] = relationship(back_populates="building")


class Floor(Base):
    __tablename__ = "floors"
    __table_args__ = (
        UniqueConstraint("building_id", "name", name="uq_floors_building_name"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True)
    building_id: Mapped[str] = mapped_column(
        String,
        ForeignKey("buildings.id"),
        nullable=False,
    )
    name: Mapped[str] = mapped_column(String, nullable=False)
    level: Mapped[int] = mapped_column(Integer, nullable=False)

    building: Mapped["Building"] = relationship(back_populates="floors")
    nodes: Mapped[list["Node"]] = relationship(back_populates="floor")
    edges: Mapped[list["Edge"]] = relationship(back_populates="floor")
    stores: Mapped[list["Store"]] = relationship(back_populates="floor")
    pois: Mapped[list["Poi"]] = relationship(back_populates="floor")
    vector_map: Mapped["FloorVectorMap | None"] = relationship(
        back_populates="floor",
        uselist=False,
    )
