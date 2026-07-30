# 건물·층 ORM 엔티티.

from __future__ import annotations

from typing import TYPE_CHECKING

from sqlalchemy import JSON, Float, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base

if TYPE_CHECKING:
    from app.models.navigation import Edge, Node
    from app.models.place import Poi, Store


class Building(Base):
    __tablename__ = "buildings"

    id: Mapped[str] = mapped_column(String, primary_key=True)  # 건물 고유 id (예: thehyundai-seoul)
    name: Mapped[str] = mapped_column(String, nullable=False)  # 건물 표시 이름
    area_m2: Mapped[float | None] = mapped_column(Float)  # 건물 바닥 면적(㎡), 선택
    perimeter_m: Mapped[float | None] = mapped_column(Float)  # 건물 둘레(m), 선택
    footprint_local_m: Mapped[list[dict] | None] = mapped_column(JSON)  # 건물 외곽선 좌표(local_m 점 목록), 선택

    floors: Mapped[list[Floor]] = relationship(back_populates="building")  # 소속 층들 (1:N)


class Floor(Base):
    __tablename__ = "floors"
    __table_args__ = (UniqueConstraint("building_id", "name", name="uq_floors_building_name"),)

    id: Mapped[str] = mapped_column(String, primary_key=True)  # 층 고유 id (원천 데이터 내부 식별자, 불투명)
    building_id: Mapped[str] = mapped_column(
        String,
        ForeignKey("buildings.id"),
        nullable=False,
    )  # 소속 건물 FK

    # 사람이 보는 층 라벨 (예: B2, 1F). 사이니지 표기이며 "지하 2층"이 아님
    name: Mapped[str] = mapped_column(String, nullable=False)
    # 층 정렬용 정수 (지하 음수 B2=-2, 지상 양수 1F=1). 문자열 name은 정렬 불가라 별도로 둠
    level: Mapped[int] = mapped_column(Integer, nullable=False)
    map_calibration_version: Mapped[str] = mapped_column(
        String,
        nullable=False,
        default="unversioned",
    )  # 지도 좌표 보정 버전 (미보정 시 "unversioned")
    # 층 외곽선. 층마다 윤곽이 다르므로(지하 주차장이 지상보다 넓다) 건물 하나의
    # footprint를 전 층에 돌려쓰면 어느 층이든 1F 모양이 그려진다.
    footprint_local_m: Mapped[list[dict] | None] = mapped_column(JSON)  # 미터 좌표 점들의 리스트로 구현한 외곽 폴리곤

    building: Mapped[Building] = relationship(back_populates="floors")  # 소속 건물 (N:1)
    nodes: Mapped[list[Node]] = relationship(back_populates="floor")  # 이 층의 그래프 노드들
    edges: Mapped[list[Edge]] = relationship(back_populates="floor")  # 이 층의 그래프 간선들
    stores: Mapped[list[Store]] = relationship(back_populates="floor")  # 이 층의 매장들
    pois: Mapped[list[Poi]] = relationship(back_populates="floor")  # 이 층의 POI(엘리베이터·에스컬레이터 마커)들
