# 매장·POI ORM 엔티티.

from __future__ import annotations

from typing import TYPE_CHECKING

from sqlalchemy import JSON, Float, ForeignKey, Index, String
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

    id: Mapped[str] = mapped_column(String, primary_key=True)  # 매장 고유 id
    floor_id: Mapped[str] = mapped_column(ForeignKey("floors.id"), nullable=False)  # 소속 층 FK

    name: Mapped[str] = mapped_column(String, nullable=False)  # 매장명 (화장실·엘리베이터도 매장으로 저장됨)

    category: Mapped[str | None] = mapped_column(String)     # 카테고리 (예: 편의점·패션), 선택
    subcategory: Mapped[str | None] = mapped_column(String)  # 세부 카테고리, 선택

    centroid_x_m: Mapped[float] = mapped_column(Float, nullable=False)  # 매장 중심점 로컬 좌표 X (미터)
    centroid_y_m: Mapped[float] = mapped_column(Float, nullable=False)  # 매장 중심점 로컬 좌표 Y (미터)

    entrance_x_m: Mapped[float | None] = mapped_column(Float)  # 입구 로컬 좌표 X (미터), 선택
    entrance_y_m: Mapped[float | None] = mapped_column(Float)  # 입구 로컬 좌표 Y (미터), 선택

    # 입구와 이어진 그래프 노드 FK. 온디바이스 경로의 도착 노드. 없으면 경로 계산 불가
    entrance_node_id: Mapped[str | None] = mapped_column(ForeignKey("nodes.id"))

    polygon: Mapped[list[dict] | None] = mapped_column(JSON)  # 매장 외곽 폴리곤 좌표(local_m), 선택

    # 검색 전용 추천 태그(intents/styles/...), 대부분 매장은 미지정. 선택
    search_facets: Mapped[dict[str, list[str]] | None] = mapped_column(JSON)

    floor: Mapped[Floor] = relationship(back_populates="stores")  # 소속 층 (N:1)
    entrance_node: Mapped[Node | None] = relationship(
        foreign_keys=[entrance_node_id],
    )  # 입구 노드 객체 (entrance_node_id 대응), 선택


class Poi(Base):
    __tablename__ = "pois"
    __table_args__ = (
        Index("idx_pois_floor", "floor_id"),
        Index("idx_pois_type", "type"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True)  # POI 고유 id ("poi_{노드id}")
    floor_id: Mapped[str] = mapped_column(ForeignKey("floors.id"), nullable=False)  # 소속 층 FK

    type: Mapped[str] = mapped_column(String, nullable=False)  # POI 종류 (elevator/escalator) — 노드에서 승격

    name: Mapped[str | None] = mapped_column(String)  # POI 표시 이름, 선택

    x_m: Mapped[float] = mapped_column(Float, nullable=False)  # 마커 로컬 좌표 X (미터)
    y_m: Mapped[float] = mapped_column(Float, nullable=False)  # 마커 로컬 좌표 Y (미터)

    # 원본 그래프 노드 FK (이 마커가 승격된 노드)
    linked_node_id: Mapped[str | None] = mapped_column(ForeignKey("nodes.id"))

    floor: Mapped[Floor] = relationship(back_populates="pois")  # 소속 층 (N:1)
    linked_node: Mapped[Node | None] = relationship(
        foreign_keys=[linked_node_id],
    )  # 원본 노드 객체 (linked_node_id 대응), 선택


