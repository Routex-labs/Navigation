"""건물/층/매장/지도/그래프 단순 조회 Query 함수.

- Session을 첫 인자로 받고 기존 API 응답과 동일한 dict를 조립한다.
- None은 존재하지 않는 Building/Floor, 빈 list는 검색 결과 없음을 뜻한다.
- HTTP 상태 코드 변환은 Router가 담당한다.
"""

from __future__ import annotations

from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.domain.georeference import GeoTransform
from app.domain.tiling import local_points_to_lnglat
from app.models import Building, Edge, Floor, Node, Poi, Store
from app.queries.geo_transform import fit_building_geo_transform


def list_buildings(session: Session) -> list[dict[str, Any]]:
    """전체 건물 요약 목록. selectinload로 층 목록 N+1을 제거한다."""
    buildings = session.scalars(
        select(Building).options(selectinload(Building.floors))
    ).all()
    return [_to_building_summary(building) for building in buildings]


def get_building(session: Session, building_id: str) -> dict[str, Any] | None:
    """건물 상세(footprint 포함). 없으면 None."""
    building = session.scalars(
        select(Building)
        .where(Building.id == building_id)
        .options(selectinload(Building.floors))
    ).one_or_none()
    if building is None:
        return None
    summary = _to_building_summary(building)
    summary["area_m2"] = building.area_m2
    summary["perimeter_m"] = building.perimeter_m
    summary["footprint_local_m"] = building.footprint_local_m or []
    return summary


def search_stores(
    session: Session,
    building_id: str,
    query: str,
) -> list[dict[str, Any]] | None:
    """건물 내 매장 이름 검색. 건물이 없으면 None, 결과 없으면 빈 리스트."""
    if session.get(Building, building_id) is None:
        return None
    stores = session.scalars(
        select(Store)
        .join(Floor, Store.floor_id == Floor.id)
        .where(Floor.building_id == building_id, Store.name.like(f"%{query}%"))
    ).all()
    transform = fit_building_geo_transform(session, building_id)
    return [_to_store_dict(store, transform) for store in stores]


def get_floor_map(
    session: Session,
    building_id: str,
    floor_name: str,
) -> dict[str, Any] | None:
    """층 지도 데이터(footprint + 벡터 지도 + 매장 폴리곤 + POI). 없으면 None."""
    floor = _find_floor(session, building_id, floor_name)
    if floor is None:
        return None
    building = session.get(Building, building_id)
    stores = session.scalars(
        select(Store).where(Store.floor_id == floor.id)
    ).all()
    pois = session.scalars(select(Poi).where(Poi.floor_id == floor.id)).all()
    transform = fit_building_geo_transform(session, building_id)
    return {
        "floor": {"id": floor.id, "name": floor.name, "level": floor.level},
        "navigation_coordinate_system": "local_m",
        "footprint_local_m": (building.footprint_local_m or []) if building else [],
        "footprint_wgs84": _footprint_wgs84(building, transform),
        # Flutter는 최초 층 지도 응답에서 이 그래프를 캐시해 클라이언트 다익스트라를 실행한다.
        "navigation_graph": _to_floor_graph_dict(session, floor),
        "stores": [_to_store_dict(store, transform) for store in stores],
        "pois": [_to_poi_dict(poi, transform) for poi in pois],
    }


def get_floor_graph(
    session: Session,
    building_id: str,
    floor_name: str,
) -> dict[str, Any] | None:
    """층 길찾기 그래프(nodes + edges). 없으면 None."""
    floor = _find_floor(session, building_id, floor_name)
    if floor is None:
        return None
    return _to_floor_graph_dict(session, floor)


def _to_floor_graph_dict(session: Session, floor: Floor) -> dict[str, Any]:
    """층 지도와 독립 그래프 API가 공유하는 길찾기 레이어 응답을 조립한다."""
    nodes = session.scalars(select(Node).where(Node.floor_id == floor.id)).all()
    edges = session.scalars(select(Edge).where(Edge.floor_id == floor.id)).all()
    return {
        "floor": {"id": floor.id, "name": floor.name},
        "nodes": [_to_node_dict(node) for node in nodes],
        "edges": [_to_edge_dict(edge) for edge in edges],
    }


def _find_floor(
    session: Session,
    building_id: str,
    floor_name: str,
) -> Floor | None:
    return session.scalars(
        select(Floor).where(
            Floor.building_id == building_id,
            Floor.name == floor_name,
        )
    ).one_or_none()


# --- ORM 객체 → API 응답 dict 변환 ---


def _to_building_summary(building: Building) -> dict[str, Any]:
    # level은 층 높이가 아니라 "위층부터 세는 표시 순서"다(6F=0 … 1F=5 … B1=6).
    # 내림차순으로 정렬해 지상 저층이 앞에 오게 한다. 클라이언트가 floors.first를
    # 초기 층으로 쓰기 때문에(indoor_map_screen) 1F가 먼저 와야 하고, 가로 층 칩도
    # 1F→4F로 읽힌다.
    # 주의: 지하층이 추가되면 level이 더 커서 B층이 앞으로 온다. 그때는 "기본 층"을
    # 정렬 순서로 정하지 말고 별도로 표현해야 한다(응답에 default_floor 등).
    floors = sorted(building.floors, key=lambda floor: floor.level, reverse=True)
    return {
        "id": building.id,
        "name": building.name,
        "floors": [floor.name for floor in floors],
    }


def _to_node_dict(node: Node) -> dict[str, Any]:
    return {
        "id": node.id,
        "type": node.type,
        "name": node.name,
        "x_m": node.x_m,
        "y_m": node.y_m,
        "lat": node.lat,
        "lng": node.lng,
    }


def _to_edge_dict(edge: Edge) -> dict[str, Any]:
    # 내부 from_node_id/to_node_id를 API에서는 짧은 from/to 키로 노출한다.
    return {
        "id": edge.id,
        "from": edge.from_node_id,
        "to": edge.to_node_id,
        "length_m": edge.length_m,
        "bidirectional": edge.bidirectional,
        "geometry_local_m": edge.geometry or [],
    }


def _to_store_dict(store: Store, transform: GeoTransform | None) -> dict[str, Any]:
    centroid_wgs84 = None
    polygon_wgs84 = None
    if transform is not None:
        lat, lng = transform.apply(store.centroid_x_m, store.centroid_y_m)
        centroid_wgs84 = {"lat": lat, "lng": lng}
        if store.polygon:
            polygon_wgs84 = [
                {"lng": lng, "lat": lat}
                for lng, lat in local_points_to_lnglat(store.polygon, transform)
            ]
    return {
        "id": store.id,
        "floor_id": store.floor_id,
        "name": store.name,
        "category": store.category,
        "subcategory": store.subcategory,
        "centroid_local_m": {"x": store.centroid_x_m, "y": store.centroid_y_m},
        "centroid_wgs84": centroid_wgs84,
        "polygon_wgs84": polygon_wgs84,
        "entrance_local_m": _optional_point(
            store.entrance_x_m,
            store.entrance_y_m,
            label=f"매장 {store.id} 입구",
        ),
        "entrance_node_id": store.entrance_node_id,
        "polygon_local_m": store.polygon,
    }


def _to_poi_dict(poi: Poi, transform: GeoTransform | None) -> dict[str, Any]:
    position_wgs84 = None
    if transform is not None:
        lat, lng = transform.apply(poi.x_m, poi.y_m)
        position_wgs84 = {"lat": lat, "lng": lng}
    return {
        "id": poi.id,
        "type": poi.type,
        "name": poi.name,
        "position_local_m": {"x": poi.x_m, "y": poi.y_m},
        "position_wgs84": position_wgs84,
        "linked_node_id": poi.linked_node_id,
    }


def _footprint_wgs84(
    building: Building | None,
    transform: GeoTransform | None,
) -> list[dict[str, float]] | None:
    if building is None or transform is None or not building.footprint_local_m:
        return None
    points = local_points_to_lnglat(building.footprint_local_m, transform)
    return [{"lng": lng, "lat": lat} for lng, lat in points]


def _optional_point(
    x: float | None,
    y: float | None,
    *,
    label: str,
) -> dict[str, float] | None:
    """선택 좌표는 x/y 모두 NULL일 때만 없음으로 처리하고, 한쪽만 있으면 오류다."""
    if x is None and y is None:
        return None
    if x is None or y is None:
        raise ValueError(f"{label} 좌표 값이 불완전합니다.")
    return {"x": x, "y": y}
